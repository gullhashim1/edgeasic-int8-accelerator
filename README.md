# EdgeASIC INT8 Accelerator

Host-assisted INT8 Conv/GEMM and YOLOv8n inference accelerator for edge ASIC deployment.

## Architecture Overview (v5.0)

EdgeASIC is an edge inference accelerator featuring a 64-PE (8×8) weight-stationary systolic array with external accumulation, per-channel requantization, post-requantization 256-entry LUT-SiLU activation, and integrated memory double-buffering.

* **Compute Spine**: 8×8 Weight-Stationary PE Array, SDDU Deskew Unit, INT33 Accumulator Buffer (`ACC_BUFF=33`), Requantization Unit (24-bit scale, 8-bit shift, HALF_UP rounding, saturating INT8 output).
* **YOLOv8n Operators**: LUT-SiLU (Drain Path), Maxpool/SPPF & Dual-Scale Elementwise (Between-Layer Engines), Concat/Split/Upsample (Zero-overhead Addressing Operations).
* **Memory & Control**: 512-bit AXI DMA Master with 4KB boundary enforcement, Bank State Controller, Descriptor Ring, Tensor Table, and Graph Scheduler.

## Documentation

Full architectural specifications and implementation planning documents are located in [`docs/`](docs/):

- [`EdgeASIC_v5_0_Detailed_Full_Scope_Architecture_Specification.docx`](docs/EdgeASIC_v5_0_Detailed_Full_Scope_Architecture_Specification.docx) — Complete 20-chapter architecture specification.
- [`EdgeASIC_v5_0_RTL_Implementation_and_Verification_Specification.docx`](docs/EdgeASIC_v5_0_RTL_Implementation_and_Verification_Specification.docx) — RTL module contracts, bring-up gates G0–G12, test matrix, and assertions.
- [`EdgeASIC_v5_0_36_Week_Full_Scope_Implementation_Plan.docx`](docs/EdgeASIC_v5_0_36_Week_Full_Scope_Implementation_Plan.docx) — 36-week schedule (18 Aug 2026 – 30 Apr 2027) with work breakdown.
- [`EdgeASIC_Architecture_Change_Register_v4_8_to_v5_0.docx`](docs/EdgeASIC_Architecture_Change_Register_v4_8_to_v5_0.docx) — Change register (CR-01 to CR-25) and open decisions (OD-01 to OD-05).
- [`docs/diagrams/01_master_architecture_v5_0.png`](docs/diagrams/01_master_architecture_v5_0.png) — Poster-scale Master Architecture Map.

## Verification & Simulation

Run the complete regression suite:
```bash
make all      # Runs all 15 unit and subsystem testbenches
make core     # Compute datapath testbenches (PE, Array, SDDU, Accum, Requant)
make control  # Control plane testbenches (CSR, Descriptor, Dispatcher)
make memory   # Memory subsystem testbenches (BSC, Packing FIFO, DMA, Router, SRAMs)
make sweep    # Multi-seed randomized regression against Python golden model
```
