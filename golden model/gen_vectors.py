"""
gen_vectors.py -- Generate $readmemh stimulus and expected-value files from the model.

Emitted accumulator files:
    stim_psum.hex        ARRAY_N*ACC_W   bits   packed psum vector
    stim_bias.hex        ARRAY_N*BIAS_W  bits   packed bias vector
    stim_ctrl.hex        16              bits   {valid, k_first, k_last, addr[7:0]}
    exp_valid.hex        4               bits   1 if output is valid
    exp_acc.hex          ARRAY_N*ACC_BUFF bits  expected out_acc_bus

Emitted requantization files:
    stim_req_acc.hex     ARRAY_N*ACC_BUFF bits  packed 33-bit acc vector
    stim_req_scale.hex   ARRAY_N*SCALE_W  bits  packed 24-bit scale vector
    stim_req_shift.hex   ARRAY_N*SHIFT_W  bits  packed 8-bit shift vector
    stim_req_ctrl.hex    16               bits  {enable, valid, act_mode[1:0], addr[7:0]}
    exp_req_valid.hex    4                bits  1 if out_valid is high
    exp_req_out.hex      ARRAY_N*OUT_W    bits  packed INT8 output vector

Run:
    python3 gen_vectors.py --target all --beats 5000
"""

from __future__ import annotations

import argparse
import os
import random
from typing import List, Tuple

from edgeasic_model import (
    AccumulatorModel,
    ActMode,
    Config,
    RoundMode,
    apply_activation,
    pack_lanes,
    requantize,
    to_hex,
)

CTRL_W = 16          # {valid, k_first, k_last, reserved[4:0], addr[7:0]}
REQ_CTRL_W = 16      # {enable, in_valid, act_mode[1:0], reserved[3:0], addr[7:0]}


def encode_ctrl(valid: bool, k_first: bool, k_last: bool, addr: int) -> int:
    return (
        (int(valid) << 15)
        | (int(k_first) << 14)
        | (int(k_last) << 13)
        | (addr & 0xFF)
    )


def encode_req_ctrl(enable: bool, valid: bool, act_mode: ActMode, addr: int) -> int:
    return (
        (int(enable) << 15)
        | (int(valid) << 14)
        | ((act_mode.value & 0x3) << 12)
        | (addr & 0xFF)
    )


# ============================================================================
# Accumulator Stream Generation
# ============================================================================

def gen_accum_stream(
    cfg: Config,
    n_beats: int,
    seed: int,
    n_addrs: int = 8,
    max_k_tiles: int = 6,
    psum_bound: int = 131072,   # 8 * 128 * 128
    bias_bound: int = 1 << 20,
) -> List[dict]:
    rng = random.Random(seed)

    def new_chain(addr: int) -> List[dict]:
        k_tiles = rng.randint(1, max_k_tiles)
        bias = [rng.randint(-bias_bound, bias_bound) for _ in range(cfg.ARRAY_N)]
        return [{
            "addr": addr,
            "psum": [rng.randint(-psum_bound, psum_bound) for _ in range(cfg.ARRAY_N)],
            "bias": bias if kt == 0 else [0] * cfg.ARRAY_N,
            "k_first": kt == 0,
            "k_last": kt == k_tiles - 1,
        } for kt in range(k_tiles)]

    pending = {a: new_chain(a) for a in range(n_addrs)}
    stream: List[dict] = []

    while len(stream) < n_beats:
        addr = rng.choice(list(pending.keys()))
        stream.append(pending[addr].pop(0))
        if not pending[addr]:
            pending[addr] = new_chain(addr)

        if rng.random() < 0.15 and len(stream) < n_beats:
            stream.append({"bubble": True})

    return stream[:n_beats]


def write_accum_vectors(cfg: Config, stream: List[dict], outdir: str) -> dict:
    os.makedirs(outdir, exist_ok=True)
    accum = AccumulatorModel(cfg)

    f_psum = open(os.path.join(outdir, "stim_psum.hex"), "w")
    f_bias = open(os.path.join(outdir, "stim_bias.hex"), "w")
    f_ctrl = open(os.path.join(outdir, "stim_ctrl.hex"), "w")
    f_ev = open(os.path.join(outdir, "exp_valid.hex"), "w")
    f_eacc = open(os.path.join(outdir, "exp_acc.hex"), "w")

    n_emit = 0

    for beat in stream:
        if beat.get("bubble"):
            f_psum.write(to_hex(0, cfg.ARRAY_N * cfg.ACC_W) + "\n")
            f_bias.write(to_hex(0, cfg.ARRAY_N * cfg.BIAS_W) + "\n")
            f_ctrl.write(to_hex(encode_ctrl(False, False, False, 0), CTRL_W) + "\n")
            f_ev.write("0\n")
            f_eacc.write(to_hex(0, cfg.ARRAY_N * cfg.ACC_BUFF) + "\n")
            continue

        out = accum.step(
            beat["psum"], beat["bias"], beat["addr"],
            beat["k_first"], beat["k_last"],
        )

        f_psum.write(to_hex(pack_lanes(beat["psum"], cfg.ACC_W),
                            cfg.ARRAY_N * cfg.ACC_W) + "\n")
        f_bias.write(to_hex(pack_lanes(beat["bias"], cfg.BIAS_W),
                            cfg.ARRAY_N * cfg.BIAS_W) + "\n")
        f_ctrl.write(to_hex(encode_ctrl(True, beat["k_first"], beat["k_last"],
                                        beat["addr"]), CTRL_W) + "\n")

        if out is None:
            f_ev.write("0\n")
            f_eacc.write(to_hex(0, cfg.ARRAY_N * cfg.ACC_BUFF) + "\n")
        else:
            n_emit += 1
            f_ev.write("1\n")
            f_eacc.write(to_hex(pack_lanes(out, cfg.ACC_BUFF),
                                cfg.ARRAY_N * cfg.ACC_BUFF) + "\n")

    for f in (f_psum, f_bias, f_ctrl, f_ev, f_eacc):
        f.close()

    return {
        "beats": len(stream),
        "emitted": n_emit,
        "bubbles": sum(1 for b in stream if b.get("bubble")),
        "overflow": accum.report,
    }


# ============================================================================
# Requantization Stream Generation
# ============================================================================

def gen_requant_stream(cfg: Config, n_beats: int, seed: int) -> List[dict]:
    """
    Generates a rigorous test stream for requant.sv covering:
    - Normal random cases
    - Saturation high (+127) and low (-128)
    - Zero/extreme shifts (0 to 60)
    - Small/large scales
    - ReLU vs Passthrough
    - Bubbles (in_valid=0) and enable=0
    """
    rng = random.Random(seed)
    stream: List[dict] = []

    # Corner case sets
    corner_accs = [
        0, 1, -1, 127, -128, 32767, -32768,
        (1 << 31) - 1, -(1 << 31),
        (1 << 32) - 1, -(1 << 32),
        1000000, -1000000
    ]
    corner_scales = [0, 1, 2, (1 << 12), (1 << 23), (1 << 24) - 1]
    corner_shifts = [0, 1, 2, 7, 8, 15, 16, 23, 24, 31, 32, 56, 57, 58, 60]

    for i in range(n_beats):
        # 10% bubbles / idle
        if rng.random() < 0.10:
            stream.append({"enable": True, "valid": False, "addr": i & 0xFF,
                           "acc": [0] * cfg.ARRAY_N, "scale": [0] * cfg.ARRAY_N,
                           "shift": [0] * cfg.ARRAY_N, "act_mode": ActMode.NONE})
            continue

        # 5% disabled
        if rng.random() < 0.05:
            stream.append({"enable": False, "valid": True, "addr": i & 0xFF,
                           "acc": [rng.randint(-1000, 1000) for _ in range(cfg.ARRAY_N)],
                           "scale": [1] * cfg.ARRAY_N, "shift": [0] * cfg.ARRAY_N,
                           "act_mode": ActMode.NONE})
            continue

        act_mode = ActMode.RELU if (i % 3 == 0) else ActMode.NONE
        addr = i & 0xFF

        # Alternate between corner cases and uniform random
        if i < 200:
            acc_lanes = [rng.choice(corner_accs) for _ in range(cfg.ARRAY_N)]
            scale_lanes = [rng.choice(corner_scales) for _ in range(cfg.ARRAY_N)]
            shift_lanes = [rng.choice(corner_shifts) for _ in range(cfg.ARRAY_N)]
        else:
            acc_lanes = [rng.randint(-(1 << 32), (1 << 32) - 1) for _ in range(cfg.ARRAY_N)]
            scale_lanes = [rng.randint(0, (1 << cfg.SCALE_W) - 1) for _ in range(cfg.ARRAY_N)]
            shift_lanes = [rng.randint(0, 45) for _ in range(cfg.ARRAY_N)]

        stream.append({
            "enable": True,
            "valid": True,
            "addr": addr,
            "acc": acc_lanes,
            "scale": scale_lanes,
            "shift": shift_lanes,
            "act_mode": act_mode,
        })

    return stream[:n_beats]


def write_requant_vectors(cfg: Config, stream: List[dict], outdir: str) -> dict:
    os.makedirs(outdir, exist_ok=True)

    f_acc = open(os.path.join(outdir, "stim_req_acc.hex"), "w")
    f_scale = open(os.path.join(outdir, "stim_req_scale.hex"), "w")
    f_shift = open(os.path.join(outdir, "stim_req_shift.hex"), "w")
    f_ctrl = open(os.path.join(outdir, "stim_req_ctrl.hex"), "w")
    f_ev = open(os.path.join(outdir, "exp_req_valid.hex"), "w")
    f_eout = open(os.path.join(outdir, "exp_req_out.hex"), "w")

    n_valid = 0

    for beat in stream:
        enable = beat["enable"]
        valid = beat["valid"]
        addr = beat["addr"]
        acc_lanes = beat["acc"]
        scale_lanes = beat["scale"]
        shift_lanes = beat["shift"]
        act_mode = beat["act_mode"]

        f_acc.write(to_hex(pack_lanes(acc_lanes, cfg.ACC_BUFF),
                           cfg.ARRAY_N * cfg.ACC_BUFF) + "\n")
        f_scale.write(to_hex(pack_lanes(scale_lanes, cfg.SCALE_W),
                             cfg.ARRAY_N * cfg.SCALE_W) + "\n")
        f_shift.write(to_hex(pack_lanes(shift_lanes, cfg.SHIFT_W),
                             cfg.ARRAY_N * cfg.SHIFT_W) + "\n")
        f_ctrl.write(to_hex(encode_req_ctrl(enable, valid, act_mode, addr),
                            REQ_CTRL_W) + "\n")

        if enable and valid:
            n_valid += 1
            out_lanes = []
            for lane in range(cfg.ARRAY_N):
                q = requantize(acc_lanes[lane], scale_lanes[lane], shift_lanes[lane],
                               cfg, RoundMode.HALF_UP)
                act = apply_activation(q, act_mode, cfg)
                out_lanes.append(act)

            f_ev.write("1\n")
            f_eout.write(to_hex(pack_lanes(out_lanes, cfg.OUT_W),
                                cfg.ARRAY_N * cfg.OUT_W) + "\n")
        else:
            f_ev.write("0\n")
            f_eout.write(to_hex(0, cfg.ARRAY_N * cfg.OUT_W) + "\n")

    for f in (f_acc, f_scale, f_shift, f_ctrl, f_ev, f_eout):
        f.close()

    return {
        "beats": len(stream),
        "valid_beats": n_valid,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate golden vectors for RTL testbenches")
    ap.add_argument("--beats", type=int, default=5000)
    ap.add_argument("--seed", type=int, default=0xED6E)
    ap.add_argument("--target", choices=["accum", "requant", "all"], default="all")
    ap.add_argument("--out", default="../tb/vectors")
    args = ap.parse_args()

    cfg = Config()

    if args.target in ("accum", "all"):
        accum_stream = gen_accum_stream(cfg, args.beats, args.seed)
        stats_acc = write_accum_vectors(cfg, accum_stream, args.out)
        print(f"[ACCUM] Wrote {stats_acc['beats']} beats to {args.out} ({stats_acc['emitted']} outputs)")

    if args.target in ("requant", "all"):
        req_stream = gen_requant_stream(cfg, args.beats, args.seed)
        stats_req = write_requant_vectors(cfg, req_stream, args.out)
        print(f"[REQUANT] Wrote {stats_req['beats']} beats to {args.out} ({stats_req['valid_beats']} valid outputs)")


if __name__ == "__main__":
    main()
