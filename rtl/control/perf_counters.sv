// rtl/control/perf_counters.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module perf_counters (
    input  logic        clk,
    input  logic        rst_n,

    // Control & Reset
    input  logic        perf_clear,     // Host clear via CSR CONTROL bit 2
    input  logic        counting_active, // Active while engine is between START and DONE

    // Event Predicates
    input  logic        compute_busy,   // Compute FSM is executing
    input  logic        dma_waiting,    // Stalled awaiting DMA transfer/arbitration
    input  logic        pipeline_stall, // Pipeline stalled due to backpressure/hazard
    input  logic        writeback_busy, // Output drain / packing path active
    input  logic        mac_active,     // Active computation (excluding padding/masking)

    // Hardware Counter Outputs (32-bit saturating)
    output logic [31:0] total_cycles,
    output logic [31:0] compute_cycles,
    output logic [31:0] dma_wait_cycles,
    output logic [31:0] stall_cycles,
    output logic [31:0] writeback_cycles,
    output logic [31:0] mac_active_cycles
);

    function automatic logic [31:0] sat_inc(input logic [31:0] val);
        if (val == 32'hFFFF_FFFF)
            return val;
        else
            return val + 1'b1;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles      <= '0;
            compute_cycles    <= '0;
            dma_wait_cycles   <= '0;
            stall_cycles      <= '0;
            writeback_cycles  <= '0;
            mac_active_cycles <= '0;
        end else if (perf_clear) begin
            total_cycles      <= '0;
            compute_cycles    <= '0;
            dma_wait_cycles   <= '0;
            stall_cycles      <= '0;
            writeback_cycles  <= '0;
            mac_active_cycles <= '0;
        end else if (counting_active) begin
            total_cycles <= sat_inc(total_cycles);

            if (compute_busy)
                compute_cycles <= sat_inc(compute_cycles);

            if (dma_waiting)
                dma_wait_cycles <= sat_inc(dma_wait_cycles);

            if (pipeline_stall)
                stall_cycles <= sat_inc(stall_cycles);

            if (writeback_busy)
                writeback_cycles <= sat_inc(writeback_cycles);

            if (mac_active)
                mac_active_cycles <= sat_inc(mac_active_cycles);
        end
    end

endmodule