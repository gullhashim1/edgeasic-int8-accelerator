// tb/tb_bank_state_controller.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_bank_state_controller;

    localparam int NUM_BANKS = 2;

    logic                   clk;
    logic                   rst_n;
    logic                   pf_fill_done;
    logic [$clog2(NUM_BANKS)-1:0] pf_bank_idx;
    logic                   cf_consume_done;
    logic [$clog2(NUM_BANKS)-1:0] cf_bank_idx;
    logic [NUM_BANKS-1:0]   bank_valid;
    logic [NUM_BANKS-1:0]   bank_consumed;
    logic                   bsc_error;

    int errors = 0;

    always #2.5 clk = ~clk;

    bank_state_controller #(
        .NUM_BANKS(NUM_BANKS)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .pf_fill_done   (pf_fill_done),
        .pf_bank_idx    (pf_bank_idx),
        .cf_consume_done(cf_consume_done),
        .cf_bank_idx    (cf_bank_idx),
        .bank_valid     (bank_valid),
        .bank_consumed  (bank_consumed),
        .bsc_error      (bsc_error)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        pf_fill_done = 0;
        pf_bank_idx = 0;
        cf_consume_done = 0;
        cf_bank_idx = 0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING BANK STATE CONTROLLER (TC-BSC-001/002)");
        $display("=================================================");

        // TEST 1: Reset State Defaults
        $display("\n[TEST 1] Checking Reset State (All banks empty & free)");
        if (bank_valid !== 2'b00 || bank_consumed !== 2'b11 || bsc_error !== 1'b0) begin
            $display("  FAIL: Initial state mismatch! valid=%0b, consumed=%0b", bank_valid, bank_consumed);
            errors++;
        end else begin
            $display("  PASS: Reset state verified: valid=00, consumed=11, error=0.");
        end

        // TEST 2: TC-BSC-001 Legal Ping-Pong Transitions
        $display("\n[TEST 2] TC-BSC-001: Ping-Pong Double Buffering Fill & Consume");
        
        // 2a. DMA Prefetch finishes filling Bank 0
        @(posedge clk);
        pf_fill_done <= 1'b1;
        pf_bank_idx  <= 0;
        @(posedge clk);
        pf_fill_done <= 1'b0;
        #1;
        if (bank_valid !== 2'b01 || bank_consumed !== 2'b10) begin
            $display("  FAIL Bank 0 Fill: valid=%0b, consumed=%0b", bank_valid, bank_consumed);
            errors++;
        end else begin
            $display("  PASS: Bank 0 marked VALID=1, CONSUMED=0.");
        end

        // 2b. Compute Core finishes reading Bank 0 while DMA fills Bank 1
        @(posedge clk);
        cf_consume_done <= 1'b1;
        cf_bank_idx     <= 0;
        pf_fill_done    <= 1'b1;
        pf_bank_idx     <= 1;
        @(posedge clk);
        cf_consume_done <= 1'b0;
        pf_fill_done    <= 1'b0;
        #1;
        if (bank_valid !== 2'b10 || bank_consumed !== 2'b01) begin
            $display("  FAIL Ping-Pong: valid=%0b, consumed=%0b", bank_valid, bank_consumed);
            errors++;
        end else begin
            $display("  PASS: Ping-Pong swap successful: Bank 0 free, Bank 1 valid.");
        end

        // TEST 3: TC-BSC-002 Simultaneous Same-Bank Collision Rejection
        $display("\n[TEST 3] TC-BSC-002: Same-Bank Collision Detection");
        @(posedge clk);
        pf_fill_done    <= 1'b1;
        pf_bank_idx     <= 0;
        cf_consume_done <= 1'b1;
        cf_bank_idx     <= 0; // SAME BANK 0!
        @(posedge clk);
        pf_fill_done    <= 1'b0;
        cf_consume_done <= 1'b0;
        #1;
        if (bsc_error !== 1'b1) begin
            $display("  FAIL: bsc_error was not raised during same-bank collision!");
            errors++;
        end else begin
            $display("  PASS: bsc_error raised upon same-bank conflict.");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL BANK STATE CONTROLLER TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("BANK STATE CONTROLLER TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
