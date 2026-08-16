"""
gen_vectors.py -- Generate $readmemh stimulus and expected-value files from the model.

This is what lets verification scale past hand-computed constants. Instead of
writing `check_lane(i, 33'sd200)` by hand, the model emits thousands of beats and
the testbench compares against them automatically.

Emitted files (one hex value per line, one line per beat):

    stim_psum.hex   ARRAY_N*ACC_W   bits   packed psum vector, lane 0 in LSBs
    stim_bias.hex   ARRAY_N*BIAS_W  bits   packed bias vector
    stim_ctrl.hex   16              bits   {valid, k_first, k_last, addr[7:0]}
    exp_valid.hex   4               bits   1 if this beat emits an output
    exp_acc.hex     ARRAY_N*ACC_BUFF bits  expected out_acc_bus (0 when not valid)

Run:
    python3 gen_vectors.py                      # default random regression
    python3 gen_vectors.py --beats 5000         # longer run
    python3 gen_vectors.py --seed 42 --out ../tb/vectors
"""

from __future__ import annotations

import argparse
import os
import random
from typing import List

from edgeasic_model import AccumulatorModel, Config, pack_lanes, to_hex

CTRL_W = 16          # {valid, k_first, k_last, reserved[4:0], addr[7:0]}


def encode_ctrl(valid: bool, k_first: bool, k_last: bool, addr: int) -> int:
    return (
        (int(valid) << 15)
        | (int(k_first) << 14)
        | (int(k_last) << 13)
        | (addr & 0xFF)
    )


def gen_random_stream(
    cfg: Config,
    n_beats: int,
    seed: int,
    n_addrs: int = 8,
    max_k_tiles: int = 6,
    psum_bound: int = 131072,   # 8 * 128 * 128, the true array output limit
    bias_bound: int = 1 << 20,
) -> List[dict]:
    """
    Build a randomised but legal beat stream.

    Multiple accumulator addresses are kept in flight simultaneously, and beats
    from different addresses are interleaved. That is the case most likely to
    expose address-tracking and RAW-bypass bugs, and it is exactly what the
    directed tests do not cover.

    psum_bound defaults to the real systolic array limit rather than the full
    ACC_W range -- driving values the array cannot produce would test overflow
    behaviour that hardware never actually sees.
    """
    rng = random.Random(seed)

    def new_chain(addr: int) -> List[dict]:
        """One accumulation chain: k_tiles sub-tiles sharing an address."""
        k_tiles = rng.randint(1, max_k_tiles)
        bias = [rng.randint(-bias_bound, bias_bound) for _ in range(cfg.ARRAY_N)]
        return [{
            "addr": addr,
            "psum": [rng.randint(-psum_bound, psum_bound) for _ in range(cfg.ARRAY_N)],
            "bias": bias if kt == 0 else [0] * cfg.ARRAY_N,
            "k_first": kt == 0,
            "k_last": kt == k_tiles - 1,
        } for kt in range(k_tiles)]

    # Keep n_addrs chains in flight at once and refill as they complete, so
    # beats from different addresses stay interleaved for the whole run.
    pending = {a: new_chain(a) for a in range(n_addrs)}
    stream: List[dict] = []

    while len(stream) < n_beats:
        addr = rng.choice(list(pending.keys()))
        stream.append(pending[addr].pop(0))
        if not pending[addr]:
            pending[addr] = new_chain(addr)   # refill with a fresh chain

        # Occasional bubble -- exercises the valid-gating path
        if rng.random() < 0.15 and len(stream) < n_beats:
            stream.append({"bubble": True})

    return stream[:n_beats]


def write_vectors(cfg: Config, stream: List[dict], outdir: str) -> dict:
    os.makedirs(outdir, exist_ok=True)
    accum = AccumulatorModel(cfg)

    f_psum = open(os.path.join(outdir, "stim_psum.hex"), "w")
    f_bias = open(os.path.join(outdir, "stim_bias.hex"), "w")
    f_ctrl = open(os.path.join(outdir, "stim_ctrl.hex"), "w")
    f_ev = open(os.path.join(outdir, "exp_valid.hex"), "w")
    f_eacc = open(os.path.join(outdir, "exp_acc.hex"), "w")

    n_emit = 0
    zeros = [0] * cfg.ARRAY_N

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


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate golden vectors for RTL testbenches")
    ap.add_argument("--beats", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=0xED6E)
    ap.add_argument("--addrs", type=int, default=8)
    ap.add_argument("--out", default="../tb/vectors")
    args = ap.parse_args()

    cfg = Config()
    stream = gen_random_stream(cfg, args.beats, args.seed, n_addrs=args.addrs)
    stats = write_vectors(cfg, stream, args.out)

    print(f"Wrote vectors to {os.path.abspath(args.out)}")
    print(f"  beats        : {stats['beats']}")
    print(f"  output beats : {stats['emitted']}")
    print(f"  bubbles      : {stats['bubbles']}")
    print(f"  seed         : 0x{args.seed:X}")
    print("Accumulator headroom over this run:")
    print(stats["overflow"].summary(cfg))


if __name__ == "__main__":
    main()
