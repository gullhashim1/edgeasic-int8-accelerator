"""
test_model.py -- Self-tests for the golden model.

A reference model that has not itself been tested is not a reference, it is a
second opinion of unknown quality. These tests pin down the primitives, then
check the full datapath against independent numpy computation.

Run:  python3 test_model.py
"""

import sys

import numpy as np

from edgeasic_model import (
    ActMode, Config, RoundMode, AccumulatorModel,
    apply_activation, check_headroom, gemm_layer, max_safe_K,
    pack_lanes, requantize, sat_signed, systolic_tile, unpack_lanes,
    wrap_signed,
)

cfg = Config()
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}  {detail}")
        failures.append(name)


# ---------------------------------------------------------------- primitives
print("\n[1] Fixed-width primitives")

check("wrap_signed identity in range", wrap_signed(100, 33) == 100)
check("wrap_signed at +max", wrap_signed((1 << 32) - 1, 33) == (1 << 32) - 1)
check("wrap_signed wraps to negative", wrap_signed(1 << 32, 33) == -(1 << 32))
check("wrap_signed 8-bit rollover", wrap_signed(128, 8) == -128)
check("wrap_signed -1 all ones", wrap_signed(-1, 33) == -1)

check("sat_signed clamps high", sat_signed(1000, 8) == 127)
check("sat_signed clamps low", sat_signed(-1000, 8) == -128)
check("sat_signed passes through", sat_signed(42, 8) == 42)

lanes = [1, -2, 3, -4, 5, -6, 7, -8]
check("lane pack/unpack round-trip",
      unpack_lanes(pack_lanes(lanes, 33), 33, 8) == lanes)
check("lane 0 occupies LSBs", (pack_lanes([5, 0, 0, 0, 0, 0, 0, 0], 33) & 0x1F) == 5)


# ------------------------------------------------------------------ rounding
print("\n[2] Requantisation rounding modes")

# product = 5 * 2 = 10, shift 2 -> 10/4 = 2.5, the interesting case
check("HALF_UP rounds .5 away from zero",
      requantize(5, 2, 2, cfg, RoundMode.HALF_UP) == 3)
check("HALF_EVEN rounds .5 to even",
      requantize(5, 2, 2, cfg, RoundMode.HALF_EVEN) == 2)
check("TRUNCATE floors",
      requantize(5, 2, 2, cfg, RoundMode.TRUNCATE) == 2)

# 3*2 = 6, shift 2 -> 1.5 -> HALF_EVEN goes to 2 (even)
check("HALF_EVEN 1.5 -> 2", requantize(3, 2, 2, cfg, RoundMode.HALF_EVEN) == 2)
check("HALF_UP 1.5 -> 2", requantize(3, 2, 2, cfg, RoundMode.HALF_UP) == 2)

check("requant saturates high", requantize(100000, 1000, 0, cfg) == 127)
check("requant saturates low", requantize(-100000, 1000, 0, cfg) == -128)
check("negative truncate floors toward -inf",
      requantize(-5, 2, 2, cfg, RoundMode.TRUNCATE) == -3)


# ---------------------------------------------------------------- activation
print("\n[3] Activation")
check("ACT_NONE passthrough", apply_activation(-42, ActMode.NONE, cfg) == -42)
check("ACT_RELU clips negative", apply_activation(-42, ActMode.RELU, cfg) == 0)
check("ACT_RELU passes positive", apply_activation(42, ActMode.RELU, cfg) == 42)


# ------------------------------------------------------------ systolic array
print("\n[4] Systolic tile")

rng = np.random.default_rng(0xED6E)
a = rng.integers(-128, 128, size=(8, 8), dtype=np.int64)
w = rng.integers(-128, 128, size=(8, 8), dtype=np.int64)
check("tile matches numpy matmul",
      np.array_equal(systolic_tile(a, w, cfg), a @ w))

amax = np.full((8, 8), -128, dtype=np.int64)
wmax = np.full((8, 8), -128, dtype=np.int64)
peak = int(systolic_tile(amax, wmax, cfg).max())
check("worst-case tile is 8*128*128", peak == 8 * 128 * 128, f"got {peak}")
check("worst-case tile fits ACC_W", peak < (1 << 31))


# ---------------------------------------------------------------- accumulator
print("\n[5] Accumulator (mirrors accum_engine.sv)")

acc = AccumulatorModel(cfg)
z = [0] * 8

# Single sub-tile: first and last -> bias + psum, emitted immediately
out = acc.step([5] * 8, [10] * 8, addr=1, k_first=True, k_last=True)
check("single sub-tile emits bias+psum", out == [15] * 8, f"got {out}")

# Three sub-tiles at one address, mirroring the RTL testbench
acc = AccumulatorModel(cfg)
r0 = acc.step([20] * 8, [100] * 8, 5, True, False)
r1 = acc.step([30] * 8, z, 5, False, False)
r2 = acc.step([50] * 8, z, 5, False, True)
check("mid sub-tiles return None (stay in SRAM)", r0 is None and r1 is None)
check("final sub-tile emits 100+20+30+50", r2 == [200] * 8, f"got {r2}")

# Independent addresses must not interfere
acc = AccumulatorModel(cfg)
acc.step([10] * 8, [10] * 8, 0x0A, True, False)
acc.step([40] * 8, [10] * 8, 0x0B, True, False)
ra = acc.step([15] * 8, z, 0x0A, False, True)
rb = acc.step([25] * 8, z, 0x0B, False, True)
check("interleaved addr 0x0A", ra == [35] * 8, f"got {ra}")
check("interleaved addr 0x0B", rb == [75] * 8, f"got {rb}")

# Distinct per-lane values -- catches lane-indexing bugs
acc = AccumulatorModel(cfg)
psum = [i + 1 for i in range(8)]
bias = [(i + 1) * 10 for i in range(8)]
out = acc.step(psum, bias, 3, True, True)
check("distinct per-lane values", out == [(i + 1) * 11 for i in range(8)], f"got {out}")

# Signed accumulation
acc = AccumulatorModel(cfg)
acc.step([20] * 8, [-100] * 8, 8, True, False)
acc.step([-30] * 8, z, 8, False, False)
neg = acc.step([10] * 8, z, 8, False, True)
check("signed accumulation -100+20-30+10", neg == [-100] * 8, f"got {neg}")


# ------------------------------------------------------------- overflow model
print("\n[6] Overflow detection")

acc = AccumulatorModel(cfg)
big = 1 << 28
for i in range(40):
    acc.step([big] * 8, z, 0x20, i == 0, False)
final = acc.step([big] * 8, z, 0x20, False, True)
rep = acc.report
check("overflow was detected", rep.events > 0, f"events={rep.events}")
check("required width exceeds ACC_BUFF",
      rep.required_width() > cfg.ACC_BUFF,
      f"needs {rep.required_width()}")
check("wrapped result differs from truth",
      final[0] != rep.max_abs_untruncated)

acc = AccumulatorModel(cfg)
acc.step([100] * 8, [100] * 8, 0, True, True)
check("no false positive on small values", acc.report.events == 0)


# ------------------------------------------------------------- headroom sizing
print("\n[7] ACC_BUFF headroom analysis")

# Worst case per sub-tile is 8*128*128 = 131,072 (2^17), NOT the full ACC_W range.
# The psum bus is 32 bits wide but the array can only ever drive ~18 bits of it.
# That bound is what makes ACC_BUFF=33 sufficient.
CSR_K_MAX = (1 << 16) - 1          # csr_k is 16 bits in the descriptor
for K in (64, 1024, 8192, CSR_K_MAX):
    h = check_headroom(K, cfg)
    print(f"        K={K:<6} subtiles={h['sub_tiles']:<5} "
          f"needs {h['required_width']} bits  safe={h['safe']}")

check("K=64 safe at 33 bits", check_headroom(64, cfg)["safe"])
check("K=1024 safe at 33 bits", check_headroom(1024, cfg)["safe"])
check("entire 16-bit csr_k range is safe",
      check_headroom(CSR_K_MAX, cfg)["safe"],
      "ACC_BUFF=33 would be undersized")
check("max safe K exceeds csr_k range", max_safe_K(cfg) > CSR_K_MAX,
      f"max safe K = {max_safe_K(cfg)}")
print(f"        max safe K at ACC_BUFF={cfg.ACC_BUFF}: {max_safe_K(cfg)} "
      f"(csr_k caps at {CSR_K_MAX})")

# 32 bits would NOT be enough -- confirms 33 is a real requirement, not padding
cfg32 = Config(ACC_BUFF=32)
check("ACC_BUFF=32 would be unsafe", not check_headroom(1024, cfg32)["safe"],
      "33rd bit is load-bearing")


# --------------------------------------------------------------- full layer
print("\n[8] End-to-end tiled GEMM")

M, K, N = 16, 32, 16
A = rng.integers(-128, 128, size=(M, K), dtype=np.int64)
W = rng.integers(-128, 128, size=(K, N), dtype=np.int64)
bias = rng.integers(-10000, 10000, size=(N,), dtype=np.int64)
scale = np.full(N, 1 << 14, dtype=np.int64)
shift = np.full(N, 20, dtype=np.int64)

res = gemm_layer(A, W, bias, scale, shift, cfg)
check("tiled accumulation matches untruncated reference",
      res.matches_reference,
      f"max diff {np.abs(res.acc_int33 - res.acc_reference).max()}")
check("no overflow at K=32", res.overflow.events == 0)
check("output is INT8 range",
      res.out_int8.min() >= -128 and res.out_int8.max() <= 127)

res_relu = gemm_layer(A, W, bias, scale, shift, cfg, act_mode=ActMode.RELU)
check("ReLU output non-negative", res_relu.out_int8.min() >= 0)
check("ReLU matches manual clip",
      np.array_equal(res_relu.out_int8, np.maximum(res.out_int8, 0)))

# Beat trace should carry exactly one emitted result per output row
emitted = sum(1 for b in res.beats if b["expected"] is not None)
check("one emitted beat per output row", emitted == M * (N // cfg.ARRAY_N),
      f"got {emitted}")


# ------------------------------------------------------------------- summary
print("\n" + "=" * 60)
if failures:
    print(f"MODEL SELF-TEST FAILED: {len(failures)} failure(s)")
    for f in failures:
        print(f"   - {f}")
    print("=" * 60)
    sys.exit(1)
print("ALL MODEL SELF-TESTS PASSED -- model is safe to use as reference")
print("=" * 60)
