# EdgeASIC v5.0 Documentation Package

Revision 5.0 — 17 August 2026. Supersedes the v4.8 document set.

## Documents

| File | Supersedes | Contents |
|---|---|---|
| `EdgeASIC_v5_0_Detailed_Full_Scope_Architecture_Specification.docx` | v4.8 Architecture Spec | 20 chapters. Operator attachment buckets, host contract, tensor/quantisation contract, CSR map, descriptor format, Tensor Table/ring/scheduler, DMA and banks, datapath behaviour, arithmetic and LUT sizing, window generator, YOLOv8n primitives, dispatch, throughput position, verification, reset/error, design rules, claim boundary. Five embedded figures. |
| `EdgeASIC_v5_0_RTL_Implementation_and_Verification_Specification.docx` | v4.8 RTL/Verif Spec | 15 sections. Module hierarchy, ownership, integration order, package and width rules, Icarus constraints, control/memory/datapath implementation contracts, driver contract, reset and errors, performance counters, verification environment, full test matrix, assertion plan, regression strategy, bring-up gates G0–G12, risk register. Three embedded figures. |
| `EdgeASIC_v5_0_36_Week_Full_Scope_Implementation_Plan.docx` | v4.8 32-Week Plan | 36-week schedule, 18 Aug 2026 → 30 Apr 2027. Week-by-week tables split by owner with deliverables, TC-IDs and exit gates. Landscape. |
| `EdgeASIC_Architecture_Change_Register_v4_8_to_v5_0.docx` | New | Every architectural difference as CR-01…CR-25, each with justification, cost and affected modules. Includes a "what did not change" section and five open decisions OD-01…OD-05. |

## Diagrams

`diagrams/` contains PNG renders and editable Mermaid sources.

| File | Used in |
|---|---|
| `01_master_architecture_v5_0.png` / `.mmd` | Architecture Spec Figure 1 — poster-scale master map (7568×9532) |
| `02_host_execution_flow` | Architecture Spec Figure 2 |
| `03_core_datapath_attach_points` | Architecture Spec Figure 3 |
| `04_control_plane_memory` | Architecture Spec Figure 4 |
| `05_architecture_delta` | Architecture Spec Figure 5, Change Register Figure 1 |
| `11_rtl_module_hierarchy` | RTL Spec Figure 1 |
| `12_verification_environment` | RTL Spec Figure 3 |
| `13_pipeline_stages_insertion` | RTL Spec Figure 2 |

Colour coding is consistent across every figure:
green = implemented and verified · yellow = scheduled primary target · blue = addressing-only ·
purple = control plane · grey = host software · orange = error/status path.

## Rendering the diagrams

```bash
mmdc -i diagrams/01_master_architecture_v5_0.mmd -o out.png -b white -w 3800 -s 2
```

## Open decisions blocking work

| ID | Decision | Needed by |
|---|---|---|
| OD-01 | Padding: zero-beat injection vs. downstream write suppression | Week 1 — blocks first RTL |
| OD-02 | Descriptor expressiveness for concat/split/upsample | Week 10 |
| OD-03 | `requant.sv` constant-select synthesis inference | Week 25 |
| OD-04 | Whether 200 MHz is achievable | Week 26 |
| OD-05 | Per-layer INT8 accuracy attribution | Week 24 |
