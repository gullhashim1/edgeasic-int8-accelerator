// tb/tb_perf_counters.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_perf_counters;

    logic        clk;
    logic        rst_n;
    logic        perf_clear;
    logic        counting_active;
    logic        compute_busy;
    logic        dma_waiting;
    logic        pipeline_stall;
    logic        writeback_busy;
    logic        mac_active;

    logic [31:0] total_cycles;
    logic [31:0] compute_cycles;
    logic [31:0] dma_wait_cycles;
    logic [31:0] stall_cycles;
    logic [31:0] writeback_cycles;
    logic [31:0] mac_active_cycles;

    // 200 MHz target clock
    always #2.5 clk = ~clk;

    perf_counters u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .perf_clear        (perf_clear),
        .counting_active   (counting_active),
        .compute_busy      (compute_busy),
        .dma_waiting       (dma_waiting),
        .pipeline_stall    (pipeline_stall),
        .writeback_busy    (writeback_busy),
        .mac_active        (mac_active),
        .total_cycles      (total_cycles),
        .compute_cycles    (compute_cycles),
        .dma_wait_cycles   (dma_wait_cycles),
        .stall_cycles      (stall_cycles),
        .writeback_cycles  (writeback_cycles),
        .mac_active_cycles (mac_active_cycles)
    );

    initial begin
        clk             = 0;
        rst_n           = 0;
        perf_clear      = 0;
        counting_active = 0;
        compute_busy    = 0;
        dma_waiting     = 0;
        pipeline_stall  = 0;
        writeback_busy  = 0;
        mac_active      = 0;

        #10 rst_n = 1;
        #10;

        // Run counting window for 10 cycles
        @(posedge clk);
        counting_active <= 1'b1;
        compute_busy    <= 1'b1;
        mac_active      <= 1'b1;

        repeat (10) @(posedge clk);

        // Turn off compute, simulate 5 cycles of DMA wait
        compute_busy <= 1'b0;
        mac_active   <= 1'b0;
        dma_waiting  <= 1'b1;

        repeat (5) @(posedge clk);

        counting_active <= 1'b0;
        dma_waiting     <= 1'b0;
        @(posedge clk);

        // Verify counts
        if (total_cycles == 15 && compute_cycles == 10 && dma_wait_cycles == 5) begin
            $display("[PASS] TC-PERF-001: Performance counters incremented accurately!");
        end else begin
            $display("[FAIL] Counter mismatch! Total=%0d, Compute=%0d, DMA=%0d", 
                     total_cycles, compute_cycles, dma_wait_cycles);
        end

        // Test clear
        perf_clear <= 1'b1;
        @(posedge clk);
        perf_clear <= 1'b0;
        @(posedge clk);

        if (total_cycles == 0 && compute_cycles == 0 && dma_wait_cycles == 0) begin
            $display("[PASS] TC-PERF-001: Counters cleared cleanly via perf_clear!");
        end else begin
            $display("[FAIL] Counters failed to clear!");
        end

        #20 $finish;
    end

endmodule