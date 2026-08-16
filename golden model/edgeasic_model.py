"""
edgeasic_model.py -- Bit-accurate golden reference model for the EdgeASIC INT8 accelerator.

This model mirrors the RTL datapath structurally, not just mathematically:

    activations/weights -> systolic array -> SDDU -> accumulator(+SRAM) -> requant -> activation

The distinction matters. A model written as `numpy.matmul(A, W) + bias` computes in
int64 and would silently agree with hardware right up until the 33-bit accumulator
wraps. This model reproduces the hardware's *numerical limits* as well as its math,
so overflow is detected automatically rather than by luck.

Widths are taken from rtl/pkg/config_pkg.sv. Keep Config in sync with that file.

Usage:
    from edgeasic_model import Config, AccumulatorModel, gemm_layer
    cfg = Config()
    out, report = gemm_layer(A, W, bias, scale, shift, cfg)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Tuple

import numpy as np


# ============================================================================
# Configuration -- mirrors rtl/pkg/config_pkg.sv
# ============================================================================

@dataclass(frozen=True)
class Config:
    """Datapath widths. Must match config_pkg.sv."""
    ARRAY_N: int = 8       # systolic array dimension
    DATA_W: int = 8        # INT8 activation / weight
    ACC_W: int = 32        # INT32 array partial-sum output
    ACC_BUFF: int = 33     # accumulator buffer width  <-- known-narrow, see check_headroom()
    BIAS_W: int = 32       # INT32 bias
    SCALE_W: int = 24      # requant multiplier
    SHIFT_W: int = 8       # requant right-shift
    OUT_W: int = 8         # INT8 output
    ACC_ADDR_W: int = 8    # accumulator SRAM address width

    @property
    def ACC_DEPTH(self) -> int:
        return 1 << self.ACC_ADDR_W

    @property
    def SCALED_W(self) -> int:
        """Width of acc * scale. Should equal types_pkg::int57_s."""
        return self.ACC_BUFF + self.SCALE_W


class RoundMode(Enum):
    """
    Requantisation rounding mode.

    NOTE -- THIS IS A SPEC DECISION, NOT AN IMPLEMENTATION DETAIL.
    The RTL requant block does not exist yet. Whichever mode is selected here
    becomes the specification that block must implement. Changing it later means
    re-verifying every downstream accuracy number.

    HALF_UP     : add (1 << (shift-1)) before shifting. Simplest in hardware
                  (one adder), and the most common choice in INT8 accelerators.
                  Biases very slightly positive on exact .5 cases.
    HALF_EVEN   : banker's rounding. Unbiased, but needs an extra LSB compare.
    TRUNCATE    : arithmetic shift only. Cheapest, but biases toward -inf and
                  will visibly cost accuracy over a deep network.

    Default is HALF_UP. Revisit only with measured accuracy data.
    """
    HALF_UP = "half_up"
    HALF_EVEN = "half_even"
    TRUNCATE = "truncate"


class ActMode(Enum):
    """Mirrors config_pkg::act_mode_e."""
    NONE = 0
    RELU = 1
    LUT_SILU = 2


# ============================================================================
# Fixed-width integer primitives
# ============================================================================

def wrap_signed(value: int, width: int) -> int:
    """
    Truncate to `width` bits and reinterpret as two's complement.
    Models what a hardware register physically does on overflow: silent wrap.
    """
    mask = (1 << width) - 1
    v = value & mask
    if v >= (1 << (width - 1)):
        v -= (1 << width)
    return v


def sat_signed(value: int, width: int) -> int:
    """Clamp to the signed range representable in `width` bits."""
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    return max(lo, min(hi, value))


def fits_signed(value: int, width: int) -> bool:
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    return lo <= value <= hi


def to_hex(value: int, width: int) -> str:
    """Format a signed value as fixed-width hex for $readmemh."""
    mask = (1 << width) - 1
    nibbles = (width + 3) // 4
    return format(value & mask, f"0{nibbles}x")


def pack_lanes(values: List[int], lane_width: int) -> int:
    """Pack lane values into one bus word, lane 0 in the LSBs (matches RTL +: slicing)."""
    mask = (1 << lane_width) - 1
    word = 0
    for i, v in enumerate(values):
        word |= (v & mask) << (i * lane_width)
    return word


def unpack_lanes(word: int, lane_width: int, n_lanes: int) -> List[int]:
    """Inverse of pack_lanes, returning signed values."""
    mask = (1 << lane_width) - 1
    out = []
    for i in range(n_lanes):
        raw = (word >> (i * lane_width)) & mask
        if raw >= (1 << (lane_width - 1)):
            raw -= (1 << lane_width)
        out.append(raw)
    return out


# ============================================================================
# Overflow reporting
# ============================================================================

@dataclass
class OverflowReport:
    """
    Records how close the accumulator came to its limit, and whether it blew past it.

    `max_abs_untruncated` is the headroom metric: it says what accumulator width the
    workload actually needed. Use it to size ACC_BUFF from evidence rather than guesswork.
    """
    events: int = 0
    max_abs_untruncated: int = 0
    first_event: Optional[Tuple[int, int, int]] = None  # (addr, lane, true_value)

    def note(self, addr: int, lane: int, true_value: int, wrapped: int) -> None:
        self.max_abs_untruncated = max(self.max_abs_untruncated, abs(true_value))
        if true_value != wrapped:
            self.events += 1
            if self.first_event is None:
                self.first_event = (addr, lane, true_value)

    def required_width(self) -> int:
        """Minimum ACC_BUFF that would have held every value seen."""
        if self.max_abs_untruncated == 0:
            return 1
        return self.max_abs_untruncated.bit_length() + 1

    def summary(self, cfg: Config) -> str:
        need = self.required_width()
        head = cfg.ACC_BUFF - need
        lines = [
            f"  accumulator overflow events : {self.events}",
            f"  max |value| observed        : {self.max_abs_untruncated}",
            f"  width required              : {need} bits",
            f"  ACC_BUFF configured         : {cfg.ACC_BUFF} bits  (headroom {head:+d})",
        ]
        if self.events:
            a, l, v = self.first_event
            lines.append(f"  !! FIRST OVERFLOW at addr=0x{a:02x} lane={l} true={v}")
        return "\n".join(lines)


# ============================================================================
# Accumulator -- bit-accurate model of accum_engine + accum_buffer
# ============================================================================

class AccumulatorModel:
    """
    Models rtl/core/accum_engine.sv + accum_buffer.sv at the value level.

    Reproduces exactly:
      - k_tile_first  -> seed with bias  (SRAM not read)
      - otherwise     -> read SRAM, add psum
      - k_tile_last   -> emit to output, do NOT write back
      - otherwise     -> write back to SRAM
      - every stored value truncated to ACC_BUFF bits (this is where overflow bites)

    Pipeline latency and the RAW bypass are deliberately NOT modelled. Those are
    timing behaviours already covered by the directed testbenches; mixing them in
    here would make the model harder to trust as a value reference.
    """

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.mem: List[List[int]] = [
            [0] * cfg.ARRAY_N for _ in range(cfg.ACC_DEPTH)
        ]
        self.report = OverflowReport()

    def step(
        self,
        psum: List[int],
        bias: List[int],
        addr: int,
        k_first: bool,
        k_last: bool,
    ) -> Optional[List[int]]:
        """
        Process one sub-tile beat. Returns the ACC_BUFF-wide output vector when
        k_last is set, otherwise None (result stayed in SRAM).
        """
        cfg = self.cfg
        assert len(psum) == cfg.ARRAY_N, "psum must have ARRAY_N lanes"
        assert 0 <= addr < cfg.ACC_DEPTH, f"addr {addr} out of range"

        result: List[int] = []
        for lane in range(cfg.ARRAY_N):
            p = psum[lane]
            assert fits_signed(p, cfg.ACC_W), f"psum lane {lane} exceeds ACC_W"

            if k_first:
                true_val = bias[lane] + p
            else:
                true_val = self.mem[addr][lane] + p

            wrapped = wrap_signed(true_val, cfg.ACC_BUFF)
            self.report.note(addr, lane, true_val, wrapped)
            result.append(wrapped)

        if not k_last:
            self.mem[addr] = list(result)
            return None
        return result


# ============================================================================
# Systolic array -- the math of rtl/core/systolic_array_8x8.sv
# ============================================================================

def systolic_tile(
    act_tile: np.ndarray,   # (M, 8) INT8 -- activations, M output rows
    wgt_tile: np.ndarray,   # (8, 8) INT8 -- weights, W[k][n] at PE(row=k, col=n)
    cfg: Config,
) -> np.ndarray:
    """
    One 8x8 weight-stationary tile: O[m][n] = sum_k A[m][k] * W[k][n].

    Computed in int64 then range-checked against ACC_W. The array itself cannot
    overflow INT32 (8 * 127 * 127 = 129,032 fits in 18 bits), so a failure here
    means malformed input rather than a real hardware limit.
    """
    a = act_tile.astype(np.int64)
    w = wgt_tile.astype(np.int64)
    out = a @ w

    lim = 1 << (cfg.ACC_W - 1)
    if np.any(out >= lim) or np.any(out < -lim):
        raise OverflowError("systolic tile exceeded ACC_W -- check input ranges")
    return out


def sddu_deskew(raw: np.ndarray, cfg: Config) -> np.ndarray:
    """
    Model of rtl/core/sddu.sv.

    In hardware, column n drains n cycles late, so the SDDU delays lane n by
    (ARRAY_N-1-n) cycles to realign. At the value level that is a pure identity:
    the same numbers come out, just time-aligned. Included explicitly so the
    model's structure matches the RTL block diagram, and as the hook for any
    future lane-masking behaviour.
    """
    return raw


# ============================================================================
# Requantisation and activation
# ============================================================================

def requantize(
    acc: int,
    scale: int,
    shift: int,
    cfg: Config,
    mode: RoundMode = RoundMode.HALF_UP,
) -> int:
    """
    INT33 accumulator -> INT8 output.

        product = acc * scale        (SCALED_W bits, == types_pkg::int57_s)
        shifted = round(product >> shift)
        out     = saturate(shifted, OUT_W)

    Saturation, not wrapping: a clipped activation is far less damaging to
    network accuracy than a sign flip.
    """
    assert fits_signed(acc, cfg.ACC_BUFF), "acc exceeds ACC_BUFF"
    assert 0 <= scale < (1 << cfg.SCALE_W), "scale out of range"
    assert 0 <= shift < (1 << cfg.SHIFT_W), "shift out of range"

    product = acc * scale
    if not fits_signed(product, cfg.SCALED_W):
        raise OverflowError(
            f"scaled product needs {product.bit_length()+1} bits, "
            f"SCALED_W is {cfg.SCALED_W}"
        )

    if shift == 0:
        shifted = product
    elif mode is RoundMode.TRUNCATE:
        shifted = product >> shift                      # arithmetic, floors toward -inf
    elif mode is RoundMode.HALF_UP:
        shifted = (product + (1 << (shift - 1))) >> shift
    elif mode is RoundMode.HALF_EVEN:
        half = 1 << (shift - 1)
        rem = product & ((1 << shift) - 1)
        shifted = product >> shift
        if rem > half or (rem == half and (shifted & 1)):
            shifted += 1
    else:
        raise ValueError(f"unknown rounding mode {mode}")

    return sat_signed(shifted, cfg.OUT_W)


def apply_activation(value: int, mode: ActMode, cfg: Config) -> int:
    """Mirrors config_pkg::act_mode_e. Applied after requantisation, on INT8."""
    if mode is ActMode.NONE:
        return value
    if mode is ActMode.RELU:
        return max(0, value)
    if mode is ActMode.LUT_SILU:
        raise NotImplementedError(
            "LUT-SiLU not modelled yet. Requires table generation plus an "
            "accuracy study against PyTorch -- treat as its own work item."
        )
    raise ValueError(f"unknown activation {mode}")


# ============================================================================
# Full tiled GEMM layer
# ============================================================================

@dataclass
class LayerResult:
    out_int8: np.ndarray          # (M, N) INT8, post requant + activation
    acc_int33: np.ndarray         # (M, N) accumulator values as hardware stored them
    acc_reference: np.ndarray     # (M, N) same, computed in int64 with no wrapping
    overflow: OverflowReport
    beats: List[dict] = field(default_factory=list)   # per-beat trace for vector gen

    @property
    def matches_reference(self) -> bool:
        return bool(np.array_equal(self.acc_int33, self.acc_reference))


def gemm_layer(
    A: np.ndarray,          # (M, K) INT8 activations
    W: np.ndarray,          # (K, N) INT8 weights
    bias: np.ndarray,       # (N,)   INT32
    scale: np.ndarray,      # (N,)   unsigned, SCALE_W bits
    shift: np.ndarray,      # (N,)   unsigned, SHIFT_W bits
    cfg: Config,
    act_mode: ActMode = ActMode.NONE,
    round_mode: RoundMode = RoundMode.HALF_UP,
    acc_addr_base: int = 0,
) -> LayerResult:
    """
    Full layer through the modelled datapath, tiled exactly as hardware runs it:
    K is split into ceil(K/8) sub-tiles, each accumulated through the SRAM.

    M and N must be multiples of ARRAY_N. Partial-tile lane masking is a separate
    feature (pipe_meta_t.lane_valid) and is not modelled yet.
    """
    n = cfg.ARRAY_N
    M, K = A.shape
    K2, N = W.shape
    assert K == K2, f"inner dimensions disagree: {K} vs {K2}"
    assert M % n == 0 and N % n == 0, f"M and N must be multiples of {n}"

    n_ktiles = (K + n - 1) // n
    K_pad = n_ktiles * n
    if K_pad != K:
        A = np.pad(A, ((0, 0), (0, K_pad - K)))
        W = np.pad(W, ((0, K_pad - K), (0, 0)))

    accum = AccumulatorModel(cfg)
    acc_hw = np.zeros((M, N), dtype=np.int64)
    beats: List[dict] = []

    n_col_tiles = N // n

    for m0 in range(0, M, n):
        for n0 in range(0, N, n):
            bias_tile = [int(bias[n0 + j]) for j in range(n)]

            for kt in range(n_ktiles):
                k0 = kt * n
                psum_tile = systolic_tile(
                    A[m0:m0 + n, k0:k0 + n],
                    W[k0:k0 + n, n0:n0 + n],
                    cfg,
                )
                k_first = (kt == 0)
                k_last = (kt == n_ktiles - 1)

                # Each output row is a separate beat AND a separate accumulator
                # address. Sharing an address across rows would make row r+1
                # clobber row r's partial sum.
                for r in range(n):
                    psum = [int(v) for v in psum_tile[r]]
                    beat_addr = acc_addr_base + (m0 + r) * n_col_tiles + (n0 // n)
                    assert beat_addr < cfg.ACC_DEPTH, (
                        f"accumulator depth exceeded: need addr {beat_addr}, "
                        f"ACC_DEPTH is {cfg.ACC_DEPTH}. Max concurrent output rows "
                        f"is ACC_DEPTH / (N/{n})."
                    )
                    out = accum.step(psum, bias_tile, beat_addr, k_first, k_last)

                    beats.append({
                        "psum": psum,
                        "bias": bias_tile if k_first else [0] * n,
                        "addr": beat_addr,
                        "k_first": k_first,
                        "k_last": k_last,
                        "expected": out,
                    })
                    if out is not None:
                        acc_hw[m0 + r, n0:n0 + n] = out

    # Untruncated reference for comparison
    acc_ref = (A.astype(np.int64) @ W.astype(np.int64)) + bias.astype(np.int64)[None, :]

    out8 = np.zeros((M, N), dtype=np.int8)
    for i in range(M):
        for j in range(N):
            q = requantize(int(acc_hw[i, j]), int(scale[j]), int(shift[j]), cfg, round_mode)
            out8[i, j] = apply_activation(q, act_mode, cfg)

    return LayerResult(
        out_int8=out8,
        acc_int33=acc_hw,
        acc_reference=acc_ref,
        overflow=accum.report,
        beats=beats,
    )


# ============================================================================
# Headroom analysis -- sizing ACC_BUFF from evidence
# ============================================================================

def check_headroom(K: int, cfg: Config, worst_case: bool = True) -> dict:
    """
    Analytic answer to 'how wide must ACC_BUFF be for a given K?'

    Worst case per sub-tile is 8 * 127 * 127 = 129,032, and there are ceil(K/8)
    sub-tiles, plus a full INT32 bias. Use this to set ACC_BUFF rather than
    guessing -- and note that csr_k is 16 bits, so the CSR currently accepts K
    values far beyond what a 33-bit accumulator can hold.
    """
    n = cfg.ARRAY_N
    n_ktiles = (K + n - 1) // n
    per_tile = n * (2 ** (cfg.DATA_W - 1)) ** 2 if worst_case else n * 127 * 127
    bias_max = 1 << (cfg.BIAS_W - 1)
    peak = bias_max + n_ktiles * per_tile
    need = peak.bit_length() + 1
    return {
        "K": K,
        "sub_tiles": n_ktiles,
        "peak_magnitude": peak,
        "required_width": need,
        "configured_width": cfg.ACC_BUFF,
        "safe": need <= cfg.ACC_BUFF,
        "headroom_bits": cfg.ACC_BUFF - need,
    }


def max_safe_K(cfg: Config) -> int:
    """Largest K the current ACC_BUFF can handle without overflow, worst case."""
    k = cfg.ARRAY_N
    while check_headroom(k + cfg.ARRAY_N, cfg)["safe"]:
        k += cfg.ARRAY_N
    return k
