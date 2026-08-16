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
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import math
from typing import List, Optional, Tuple

import numpy as np


# ============================================================================
# Datapath configuration (matches rtl/pkg/config_pkg.sv)
# ============================================================================

@dataclass(frozen=True)
class Config:
    """Datapath widths. Must match config_pkg.sv."""
    ARRAY_N: int = 8       # systolic array dimension
    DATA_W: int = 8        # INT8 activation / weight
    ACC_W: int = 32        # INT32 array partial-sum output
    ACC_BUFF: int = 33     # accumulator buffer width  <-- known-narrow, see check_headroom()
    BIAS_W: int = 32       # INT32 bias
    SCALE_W: int = 24      # requant multiplier (unsigned)
    SHIFT_W: int = 8       # requant right-shift (unsigned)
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

    HALF_UP     : add (1 << (shift-1)) before shifting. Mathematically identical
                  to (x >>> s) + x[s-1]. Standard in INT8 accelerators.
    HALF_EVEN   : banker's rounding. Unbiased, but needs an extra LSB compare.
    TRUNCATE    : arithmetic shift only.
    """
    HALF_UP = "HALF_UP"
    HALF_EVEN = "HALF_EVEN"
    TRUNCATE = "TRUNCATE"


class ActMode(Enum):
    """Activation function. Mirrors config_pkg::act_mode_e."""
    NONE = 0
    RELU = 1
    LUT_SILU = 2


# ============================================================================
# Fixed-width signed arithmetic helpers
# ============================================================================

def wrap_signed(val: int, bits: int) -> int:
    """Simulate hardware two's-complement wrapping to `bits` signed."""
    mask = (1 << bits) - 1
    val = val & mask
    sign_bit = 1 << (bits - 1)
    return (val ^ sign_bit) - sign_bit


def sat_signed(val: int, bits: int) -> int:
    """Simulate hardware saturation (clamping) to `bits` signed."""
    min_val = -(1 << (bits - 1))
    max_val = (1 << (bits - 1)) - 1
    if val < min_val:
        return min_val
    if val > max_val:
        return max_val
    return val


def fits_signed(val: int, bits: int) -> bool:
    """True if val can be represented in `bits` signed without wrapping."""
    min_val = -(1 << (bits - 1))
    max_val = (1 << (bits - 1)) - 1
    return min_val <= val <= max_val


def pack_lanes(values: List[int], width: int) -> int:
    """Pack a list of ints into a single wide integer (lane 0 in LSBs)."""
    out = 0
    mask = (1 << width) - 1
    for i, v in enumerate(values):
        out |= (int(v) & mask) << (i * width)
    return out


def unpack_lanes(packed: int, width: int, n: int) -> List[int]:
    """Unpack a wide integer into `n` signed values of `width` bits."""
    out = []
    mask = (1 << width) - 1
    for i in range(n):
        raw = (packed >> (i * width)) & mask
        out.append(wrap_signed(raw, width))
    return out


def to_hex(packed: int, width: int) -> str:
    """Format a wide integer as a fixed-width hex string for $readmemh."""
    val = int(packed) & ((1 << width) - 1)
    chars = math.ceil(width / 4)
    return f"{val:0{chars}X}"


# ============================================================================
# Core datapath stages
# ============================================================================

def systolic_tile(
    act: np.ndarray,
    wgt: np.ndarray,
    cfg: Config,
) -> np.ndarray:
    """
    Simulates the 8x8 systolic array output for a single sub-tile.
    act : (ARRAY_N, ARRAY_N) signed INT8
    wgt : (ARRAY_N, ARRAY_N) signed INT8
    returns : (ARRAY_N, ARRAY_N) signed INT32 partial sums
    """
    assert act.shape == (cfg.ARRAY_N, cfg.ARRAY_N)
    assert wgt.shape == (cfg.ARRAY_N, cfg.ARRAY_N)
    assert act.dtype == np.int64 or np.issubdtype(act.dtype, np.signedinteger)
    assert wgt.dtype == np.int64 or np.issubdtype(wgt.dtype, np.signedinteger)

    return (act.astype(np.int64) @ wgt.astype(np.int64)).astype(np.int64)


# ============================================================================
# Accumulator model and headroom tracker
# ============================================================================

@dataclass
class OverflowReport:
    """Diagnostic capture of overflow events across an accumulation run."""
    events: int = 0
    max_abs_untruncated: int = 0
    first_event_info: Optional[dict] = None

    def record(self, true_val: int, wrapped_val: int, info: dict) -> None:
        abs_v = abs(true_val)
        if abs_v > self.max_abs_untruncated:
            self.max_abs_untruncated = abs_v
        if true_val != wrapped_val:
            self.events += 1
            if self.first_event_info is None:
                self.first_event_info = {
                    "true_value": true_val,
                    "wrapped_value": wrapped_val,
                    **info,
                }

    def required_width(self) -> int:
        """Bits needed to hold max_abs_untruncated without wrapping."""
        if self.max_abs_untruncated == 0:
            return 1
        return int(self.max_abs_untruncated).bit_length() + 1

    def summary(self, cfg: Config) -> str:
        req = self.required_width()
        lines = [
            f"Overflow events       : {self.events}",
            f"Max magnitude reached : {self.max_abs_untruncated:,}",
            f"Required signed width : {req} bits (hardware ACC_BUFF is {cfg.ACC_BUFF})",
            f"Headroom remaining    : {cfg.ACC_BUFF - req} bits",
        ]
        if self.events > 0:
            lines.append("FIRST OVERFLOW EVENT:")
            for k, v in self.first_event_info.items():
                lines.append(f"  {k}: {v}")
        return "\n".join(lines)


class AccumulatorModel:
    """
    Bit-accurate model of rtl/core/accum_engine.sv + accum_buffer.sv.

    Tracks both the wrapped (hardware-faithful) value and the untruncated truth
    so silently wrapped sums are caught.
    """
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.sram_hw = np.zeros((cfg.ACC_DEPTH, cfg.ARRAY_N), dtype=np.int64)
        self.sram_true = np.zeros((cfg.ACC_DEPTH, cfg.ARRAY_N), dtype=np.int64)
        self.report = OverflowReport()

    def reset(self) -> None:
        self.sram_hw.fill(0)
        self.sram_true.fill(0)
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
        Mirror one beat through accum_engine.

        Returns:
            List[int] of length ARRAY_N if k_last is True (emitted output beat).
            None if intermediate sub-tile (result remains in SRAM).
        """
        assert len(psum) == self.cfg.ARRAY_N
        assert len(bias) == self.cfg.ARRAY_N
        assert 0 <= addr < self.cfg.ACC_DEPTH

        out_hw: List[int] = []
        for lane in range(self.cfg.ARRAY_N):
            p = psum[lane]
            b = bias[lane]
            assert fits_signed(p, self.cfg.ACC_W), f"psum[{lane}] exceeds ACC_W"
            assert fits_signed(b, self.cfg.BIAS_W), f"bias[{lane}] exceeds BIAS_W"

            # Mirror the 1R1W read-modify-write
            old_hw = 0 if k_first else self.sram_hw[addr, lane]
            old_true = 0 if k_first else self.sram_true[addr, lane]

            addend = b if k_first else 0
            new_true = old_true + addend + p
            new_hw = wrap_signed(old_hw + addend + p, self.cfg.ACC_BUFF)

            self.report.record(new_true, new_hw, {
                "addr": addr,
                "lane": lane,
                "k_first": k_first,
                "k_last": k_last,
            })

            self.sram_true[addr, lane] = new_true
            self.sram_hw[addr, lane] = new_hw
            out_hw.append(new_hw)

        return out_hw if k_last else None


def check_headroom(k_depth: int, cfg: Config) -> dict:
    """
    Theoretical worst-case headroom check for a given K depth.
    """
    sub_tiles = (k_depth + cfg.ARRAY_N - 1) // cfg.ARRAY_N

    peak_subtile = cfg.ARRAY_N * 128 * 128
    worst_psum = sub_tiles * peak_subtile
    worst_bias = (1 << (cfg.BIAS_W - 1)) - 1
    worst_total = worst_psum + worst_bias

    req_bits = worst_total.bit_length() + 1
    safe = req_bits <= cfg.ACC_BUFF

    return {
        "K": k_depth,
        "sub_tiles": sub_tiles,
        "worst_total": worst_total,
        "required_width": req_bits,
        "acc_buff_width": cfg.ACC_BUFF,
        "headroom_bits": cfg.ACC_BUFF - req_bits,
        "safe": safe,
    }


def max_safe_K(cfg: Config) -> int:
    """Return the largest K dimension that cannot overflow ACC_BUFF."""
    max_acc = (1 << (cfg.ACC_BUFF - 1)) - 1
    worst_bias = (1 << (cfg.BIAS_W - 1)) - 1
    avail_for_psum = max_acc - worst_bias
    peak_subtile = cfg.ARRAY_N * 128 * 128
    sub_tiles = avail_for_psum // peak_subtile
    return int(sub_tiles * cfg.ARRAY_N)


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
        # Shift-then-increment identity: (product + (1 << (shift-1))) >> shift
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
    A: np.ndarray,
    W: np.ndarray,
    bias: np.ndarray,
    scale: np.ndarray,
    shift: np.ndarray,
    cfg: Config = Config(),
    round_mode: RoundMode = RoundMode.HALF_UP,
    act_mode: ActMode = ActMode.NONE,
) -> LayerResult:
    """
    Run an entire (M, K) x (K, N) layer through the model.
    """
    M, K = A.shape
    Kw, N = W.shape
    assert K == Kw, "inner dimensions must match"
    assert M % cfg.ARRAY_N == 0, "M must be a multiple of ARRAY_N"
    assert N % cfg.ARRAY_N == 0, "N must be a multiple of ARRAY_N"
    assert K % cfg.ARRAY_N == 0, "K must be a multiple of ARRAY_N"
    assert bias.shape == (N,)
    assert scale.shape == (N,)
    assert shift.shape == (N,)

    accum = AccumulatorModel(cfg)
    acc_hw = np.zeros((M, N), dtype=np.int64)

    beats: List[dict] = []

    for m0 in range(0, M, cfg.ARRAY_N):
        for n0 in range(0, N, cfg.ARRAY_N):
            for k0 in range(0, K, cfg.ARRAY_N):
                k_first = (k0 == 0)
                k_last = (k0 == K - cfg.ARRAY_N)

                act_tile = A[m0:m0 + cfg.ARRAY_N, k0:k0 + cfg.ARRAY_N]
                wgt_tile = W[k0:k0 + cfg.ARRAY_N, n0:n0 + cfg.ARRAY_N]
                psums = systolic_tile(act_tile, wgt_tile, cfg)

                for r in range(cfg.ARRAY_N):
                    addr = (m0 + r) % cfg.ACC_DEPTH
                    p_lane = [int(psums[r, c]) for c in range(cfg.ARRAY_N)]
                    b_lane = [int(bias[n0 + c]) for c in range(cfg.ARRAY_N)] if k_first else [0] * cfg.ARRAY_N

                    out = accum.step(p_lane, b_lane, addr, k_first, k_last)
                    beats.append({
                        "m": m0 + r,
                        "n_base": n0,
                        "k_tile": k0 // cfg.ARRAY_N,
                        "addr": addr,
                        "k_first": k_first,
                        "k_last": k_last,
                        "psum": p_lane,
                        "bias": b_lane,
                        "expected": out,
                    })
                    if out is not None:
                        acc_hw[m0 + r, n0:n0 + cfg.ARRAY_N] = out

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
