// tb/tb_sddu_meta.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_sddu_meta;

    logic clk;
    logic rst_n;
    logic enable;

    // DUT Inputs
    logic                                  in_valid;
    logic signed [ARRAY_N*ACC_W-1:0]       in_psum_bus;
    logic                                  in_k_tile_first;
    logic                                  in_k_tile_last;
    logic        [ACC_ADDR_W-1:0]          in_acc_addr;

    // DUT Outputs
    logic                                  out_valid;
    logic signed [ARRAY_N*ACC_W-1:0]       out_psum_bus;
    logic                                  out_k_tile_first;
    logic                                  out_k_tile_last;
    logic        [ACC_ADDR_W-1:0]          out_acc_addr;

    // Clock Generation (200 MHz)
    always #2.5 clk = ~clk;

    // 1. Direct DUT Instantiation
    sddu u_sddu (
        .clk              (clk),
        .rst_n            (rst_n),
        .enable           (enable),
        .in_valid         (in_valid),
        .in_psum_bus      (in_psum_bus),
        .in_k_tile_first  (in_k_tile_first),
        .in_k_tile_last   (in_k_tile_last),
        .in_acc_addr      (in_acc_addr),
        .out_valid        (out_valid),
        .out_psum_bus     (out_psum_bus),
        .out_k_tile_first (out_k_tile_first),
        .out_k_tile_last  (out_k_tile_last),
        .out_acc_addr     (out_acc_addr)
    );

    // 2. Simulator-Agnostic Assertions
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            if ($isunknown(out_k_tile_first) || $isunknown(out_k_tile_last) || $isunknown(out_acc_addr)) begin
                $error("[FAIL] Procedural Check: Metadata contains X/Z when out_valid is asserted!");
            end
        end
    end

    // 3. Stimulus & Lane-by-Lane Data Integrity Verification
    int timeout_count;
    bit data_mismatch;
    int32_s expected_val;
    int32_s actual_val;

    initial begin
        clk             = 0;
        rst_n           = 0;
        enable          = 1;
        in_valid        = 0;
        in_psum_bus     = '0;
        in_k_tile_first = 0;
        in_k_tile_last  = 0;
        in_acc_addr     = '0;
        timeout_count   = 0;
        data_mismatch   = 0;

        // Reset Sequence
        #10 rst_n = 1;
        #10;

        $display("[TEST] Injecting staggered diagonal partial sums into real SDDU DUT...");
        for (int cycle = 0; cycle < ARRAY_N; cycle++) begin
            @(posedge clk);
            in_valid        <= 1'b1;
            in_k_tile_first <= (cycle == 0);
            in_k_tile_last  <= (cycle == ARRAY_N - 1);
            in_acc_addr     <= 8'h4A;

            // Drive unique test value per lane
            for (int lane = 0; lane < ARRAY_N; lane++) begin
                if (lane == cycle) begin
                    in_psum_bus[lane*ACC_W +: ACC_W] <= int32_s'(32'h100 + cycle);
                end
            end
        end

        // Clear Inputs
        @(posedge clk);
        in_valid    <= 1'b0;
        in_psum_bus <= '0;

        // Wait for Deskew Pipeline Delay
        while (!out_valid && timeout_count < 25) begin
            @(posedge clk);
            timeout_count++;
        end

        if (timeout_count >= 25) begin
            $display("[FAIL] Timeout reached waiting for SDDU out_valid!");
        end else begin
            $display("[TEST] out_valid received. Checking data integrity across all lanes...");

            // Verify metadata
            if (out_k_tile_first !== 1'b1 || out_acc_addr !== 8'h4A) begin
                $display("[FAIL] Metadata mismatch: first=%0b, addr=0x%0h", out_k_tile_first, out_acc_addr);
                data_mismatch = 1;
            end

            // Verify arithmetic output integrity on all 8 lanes simultaneously
            for (int lane = 0; lane < ARRAY_N; lane++) begin
                expected_val = int32_s'(32'h100 + lane);
                actual_val   = out_psum_bus[lane*ACC_W +: ACC_W];

                if (actual_val !== expected_val) begin
                    $display("[FAIL] Lane %0d mismatch! Expected: 0x%0h, Actual: 0x%0h", lane, expected_val, actual_val);
                    data_mismatch = 1;
                end
            end

            if (!data_mismatch) begin
                $display("[PASS] TC-SDDU-001 & TC-SDDU-002: All %0d lanes verified with 100%% data and metadata integrity!", ARRAY_N);
            end
        end

        #20 $finish;
    end

endmodule
