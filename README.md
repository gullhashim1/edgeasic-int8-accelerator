# EdgeASIC INT8 Accelerator

Host-assisted INT8 Conv/GEMM accelerator for edge CNN inference.

## Current Goal

Build and verify the baseline INT8 datapath:

1. Signed INT8 PE MAC
2. 8x8 systolic array
3. SDDU deskew unit
4. INT32 accumulation engine
5. Requantization pipeline
6. Activation unit
7. Conv/GEMM core integration

## Tools

- Ubuntu WSL
- Icarus Verilog
- GTKWave
- Python 3
- Make
