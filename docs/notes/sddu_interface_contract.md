# SDDU Interface Contract Notes

## Timing and Valid Signal Contract

`in_valid` indicates that the lane-0 systolic drain stream is valid. For a full `ARRAY_N`-row tile, it remains asserted for `ARRAY_N` enabled cycles. Lane `c`’s corresponding data stream begins `c` enabled cycles later. 

The SDDU produces aligned output vectors after `MAX_DELAY` enabled cycles, with `out_valid` asserted for the same number of valid output rows (`ARRAY_N` enabled cycles).

* **Input Window**: `in_valid` is asserted for `ARRAY_N` cycles.
* **Output Window**: `out_valid` is asserted for `ARRAY_N` cycles, delayed by `MAX_DELAY = ARRAY_N - 1` enabled clock cycles.
* **Metadata Alignment**: Tile-level metadata flags (such as `in_k_tile_first` and `in_k_tile_last`) are aligned with the start/end of the tile's lane 0 inputs, and propagate through a matching `MAX_DELAY` stage pipeline to remain aligned with the corresponding aligned outputs on the same clock cycle.
* **Clock Enable Gating**: When `enable = 0`, the complete pipeline (including valid and metadata pipelines) freezes, holding all internal state and outputs stable.
