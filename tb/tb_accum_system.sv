`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_accum_system;

    logic clk;
    logic rst_n;
    logic enable;

    logic in_valid;
    logic signed [ARRAY_N*ACC_W-1:0] in_psum_bus;
    logic in_k_tile_first;
    logic in_k_tile_last;
    logic [ACC_ADDR_W-1:0] in_acc_addr;
    logic signed [ARRAY_N*BIAS_W-1:0] bias_in_bus;

    logic signed [ACC_BUFF*ARRAY_N-1:0] buf_read_data;
    logic buf_read_en;
    logic signed [ACC_BUFF*ARRAY_N-1:0] buf_write_data;
    logic [ACC_ADDR_W-1:0] buf_write_addr;

    logic out_valid;
    logic out_k_tile_first;
    logic out_k_tile_last;
    logic [ACC_ADDR_W-1:0] out_acc_addr;
    logic buf_write_en;
    logic [ACC_ADDR_W-1:0] buf_read_addr;
    logic signed [ARRAY_N*ACC_BUFF-1:0] out_acc_bus;

    int errors;

    accum_engine dut(
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .in_valid(in_valid),
        .in_psum_bus(in_psum_bus),
        .in_k_tile_first(in_k_tile_first),
        .in_k_tile_last(in_k_tile_last),
        .in_acc_addr(in_acc_addr),
        .bias_in_bus(bias_in_bus),
        .buf_read_data(buf_read_data),
        .buf_read_en(buf_read_en),
        .buf_write_data(buf_write_data),
        .buf_write_addr(buf_write_addr),
        .out_valid(out_valid),
        .out_k_tile_first(out_k_tile_first),
        .out_k_tile_last(out_k_tile_last),
        .out_acc_addr(out_acc_addr),
        .buf_write_en(buf_write_en),
        .buf_read_addr(buf_read_addr),
        .out_acc_bus(out_acc_bus)
    );

    accum_buffer ab_dut(
        .clk(clk),
        .read_enable(buf_read_en),
        .read_address(buf_read_addr),
        .read_data(buf_read_data),
        .write_enable(buf_write_en),
        .write_address(buf_write_addr),
        .write_data(buf_write_data)
    );

    always #5 clk = ~clk;

    task reset_dut();
    begin
        @(negedge clk);
        rst_n = 1'b0;
        enable = 1'b0;
        in_valid = 1'b0;
        in_psum_bus = '0;
        in_k_tile_first = 1'b0;
        in_k_tile_last = 1'b0;
        in_acc_addr = '0;
        bias_in_bus = '0;
        repeat(2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        $display("RESET COMPLETE");
    end
    endtask

    task drive_inputs(
        input logic en,
        input logic signed [ACC_W-1:0] psum_val,
        input logic k_first,
        input logic k_last,
        input logic signed [BIAS_W-1:0] bias_val,
        input logic valid,
        input logic [ACC_ADDR_W-1:0] acc_addr,
        input logic exp_out_valid,
        input logic exp_write_en,
        input logic exp_read_en,
        input logic signed [ACC_BUFF-1:0] exp_sum
    );
    begin 
        @(negedge clk);
        enable          = en;
        in_valid        = valid;
        in_k_tile_first = k_first;
        in_k_tile_last  = k_last;
        in_acc_addr     = acc_addr;

        // Fill all 8 lanes in parallel
        for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
            in_psum_bus[lane*ACC_W +: ACC_W]   = psum_val;
            bias_in_bus[lane*BIAS_W +: BIAS_W] = bias_val;
        end

        // Wait for clock edge + 1 time-unit sampling delay
        @(posedge clk);
        #1;

        $display("  -> Inputs: psum_lane=%0d, bias_lane=%0d, addr=%0d, FIRST=%b, LAST=%b, valid=%b",
                 $signed(psum_val), $signed(bias_val), acc_addr, k_first, k_last, valid);

        // Self-checking assertions
        if (out_valid !== exp_out_valid) begin
            $error("FAIL: out_valid mismatch! Expected %b, Got %b", exp_out_valid, out_valid);
            errors++;
        end

        if (buf_write_en !== exp_write_en) begin
            $error("FAIL: buf_write_en mismatch! Expected %b, Got %b", exp_write_en, buf_write_en);
            errors++;
        end

        if (buf_read_en !== exp_read_en) begin
            $error("FAIL: buf_read_en mismatch! Expected %b, Got %b", exp_read_en, buf_read_en);
            errors++;
        end

        if (exp_out_valid) begin
            for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                logic signed [ACC_BUFF-1:0] act_sum;
                act_sum = $signed(out_acc_bus[lane*ACC_BUFF +: ACC_BUFF]);
                if (act_sum !== exp_sum) begin
                    $error("FAIL: Lane %0d output mismatch! Expected %0d, Got %0d", lane, $signed(exp_sum), act_sum);
                    errors++;
                end
            end
            $display("  -> VERIFIED 8-LANE ACCUMULATED OUTPUT VECTOR = %0d (out_valid=1)", $signed(exp_sum));
        end
    end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        enable = 1'b0;
        in_valid = 1'b0;
        in_psum_bus = '0;
        in_k_tile_first = 1'b0;
        in_k_tile_last = 1'b0;
        in_acc_addr = '0;
        bias_in_bus = '0;
        errors = 0;

        reset_dut();

        // ==========================================
        // TEST 1: Single Sub-tile (K=1, FIRST=1, LAST=1)
        // ==========================================
        $display("\n--- TEST 1: Single Sub-tile (K=1, FIRST=1, LAST=1) ---");
        drive_inputs(1'b1, 32'sd5, 1'b1, 1'b1, 32'sd10, 1'b1, 8'h01,
                     1'b1, 1'b0, 1'b0, 33'sd15); // Exp: valid=1, write=0, read=0, sum=15

        // ==========================================
        // TEST 2: Clock Gating Check (enable=0)
        // ==========================================
        $display("\n--- TEST 2: Clock Gating Check (enable=0) ---");
        drive_inputs(1'b0, 32'sd5, 1'b1, 1'b1, 32'sd10, 1'b1, 8'h01,
                     1'b0, 1'b0, 1'b0, 33'sd0); // Exp: valid=0, write=0, read=0

        // ==========================================
        // TEST 3: Continuous Multi-K Transaction (K=3, Addr=0x05)
        // ==========================================
        $display("\n--- TEST 3: Continuous Multi-K Transaction (K=3, Addr=0x05) ---");
        reset_dut();

        $display(" Sub-tile 1 (k=0, FIRST=1, LAST=0): Seed Bias=100 + Psum=20");
        drive_inputs(1'b1, 32'sd20, 1'b1, 1'b0, 32'sd100, 1'b1, 8'h05,
                     1'b0, 1'b1, 1'b0, 33'sd120); // Exp: valid=0, write=1 (RAM=120), read=0

        $display(" Sub-tile 2 (k=1, FIRST=0, LAST=0): Add Psum=30 to RAM[0x05]");
        drive_inputs(1'b1, 32'sd30, 1'b0, 1'b0, 32'sd0, 1'b1, 8'h05,
                     1'b0, 1'b1, 1'b1, 33'sd150); // Exp: valid=0, write=1 (RAM=150), read=1

        $display(" Sub-tile 3 (k=2, FIRST=0, LAST=1): Final Psum=50 + RAM[0x05]");
        drive_inputs(1'b1, 32'sd50, 1'b0, 1'b1, 32'sd0, 1'b1, 8'h05,
                     1'b1, 1'b0, 1'b1, 33'sd200); // Exp: valid=1, write=0, read=1, sum=200!

        // ==========================================
        // SUMMARY REPORT
        // ==========================================
        $display("\n============================================");
        if (errors == 0) begin
            $display("ALL ACCUMULATOR SYSTEM TESTS PASSED SUCCESSFULLY!");
        end else begin
            $display("ERROR: %0d test failures detected in Accumulator System!", errors);
        end
        $display("============================================\n");

        $finish;
    end

endmodule