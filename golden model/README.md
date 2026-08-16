# EdgeASIC Golden Reference Model

Bit-accurate Python model of the INT8 datapath. The RTL is correct if and only if
it matches this model.

```
activations/weights -> systolic array -> SDDU -> accumulator(+SRAM) -> requant -> activation
```

## Files

| File | Purpose |
|---|---|
| `edgeasic_model.py` | Core model. Widths mirror `rtl/pkg/config_pkg.sv`. |
| `test_model.py` | Self-tests. **Run these before trusting the model.** |
| `gen_vectors.py` | Emits `$readmemh` stimulus + expected files. |
| `../tb/tb_accum_golden.sv` | SV harness that consumes the vectors. |

## Quick start

```bash
make model      # model self-tests (40 checks)
make golden     # generate vectors + run RTL regression
make sweep      # multi-seed random regression
```

## Why not just numpy.matmul

A model written as `numpy.matmul(A, W) + bias` computes in int64. It agrees with
hardware right up until the 33-bit accumulator wraps, then silently diverges.

This model reproduces the hardware's *numerical limits*, not only its math:
`AccumulatorModel.step()` truncates every stored value to `ACC_BUFF` bits, exactly
as the RTL register does. Overflow is therefore detected automatically on every
run rather than by writing a stress test that happens to provoke it.

`LayerResult.matches_reference` compares the wrapped result against the
untruncated int64 computation. Any divergence is an overflow, reported with the
address, lane, and true value.

---

## Spec decisions this model pins down

These were undecided in the RTL. Whatever this model does becomes the spec.

### 1. Requantisation rounding: `HALF_UP` (default)

```
product = acc * scale          # 33 + 24 = 57 bits, matches types_pkg::int57_s
shifted = (product + (1 << (shift-1))) >> shift
out     = saturate(shifted, 8)
```

`HALF_UP` costs one adder and is the common choice in INT8 accelerators. It biases
very slightly positive on exact `.5` cases. `HALF_EVEN` is unbiased but needs an
extra LSB compare; `TRUNCATE` is cheapest but biases toward −inf and will cost
visible accuracy over a deep network.

**Change this only with measured accuracy data.** Once the requant RTL is built,
changing the mode invalidates every accuracy number you have gathered.

### 2. Saturation, not wrapping, at the INT8 output

A clipped activation degrades network accuracy far less than a sign flip.

### 3. Activation applied *after* requantisation, on INT8

Matters for ReLU: clipping before vs after the shift gives different results when
`scale` is negative.

---

## ACC_BUFF sizing — corrected analysis

An earlier review of this project claimed `ACC_BUFF = 33` overflows at realistic K.
**That claim was wrong**, and the model is what disproved it.

The error was driving `psum = 0x10000000` in a stress test. The systolic array
cannot produce that. Real bound per sub-tile:

```
8 lanes x 128 x 128 = 131,072   (2^17)
```

Worst case across the full 16-bit `csr_k` range:

```
peak = |bias|max + ceil(K/8) * 131,072
     = 2^31 + 8192 * 131,072
     = 3,221,225,472
33-bit signed max = 4,294,967,295          -> SAFE
```

| K | sub-tiles | bits needed | safe at 33? |
|---|---|---|---|
| 64 | 8 | 33 | yes |
| 1024 | 128 | 33 | yes |
| 8192 | 1024 | 33 | yes |
| 65535 (csr_k max) | 8192 | 33 | yes |

`ACC_BUFF = 33` is correct and the 33rd bit is load-bearing — `test_model.py`
asserts that 32 bits would be unsafe. Max safe K is 131,064, comfortably beyond
the 16-bit `csr_k` limit.

Two genuine observations remain:

- **The psum bus is over-provisioned.** `ACC_W = 32`, but the array can only drive
  ~18 bits. Not a bug; a small area cost worth noting at synthesis.
- **The bound depends on bias fitting INT32.** If bias ever widens, redo this
  analysis. `check_headroom()` and `max_safe_K()` exist for exactly that.

---

## Extending the model

**Requant RTL (Phase 1).** `requantize()` is already the spec. Generate vectors
across the full `acc x scale x shift` space, especially near saturation and at
exact `.5` boundaries.

**Lane masking.** `pipe_meta_t.lane_valid` exists for M/N not divisible by 8.
`gemm_layer()` currently asserts both are multiples of `ARRAY_N`. Add masking to
`AccumulatorModel.step()` when the RTL gains it.

**LUT-SiLU.** `apply_activation()` raises `NotImplementedError` deliberately.
Needs table generation plus an accuracy study against PyTorch — its own work item,
not a drop-in.

**PyTorch cross-check.** The layer above is `gemm_layer` vs `torch.nn.quantized`.
That is what validates the *quantisation scheme*; this model validates the *RTL*.
Both are needed and they answer different questions.

## Keeping in sync

`Config` duplicates `config_pkg.sv` by hand. If you change a width in one, change
it in both. A `make check-config` target that diffs them would remove this
footgun — worth adding.
