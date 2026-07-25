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

    // Driver task supporting packed vectors and clean combinational/sequential assertions
    task drive_inputs_packed(
        input logic en,
        input logic signed [ARRAY_N*ACC_W-1:0] psum_bus_in,
        input logic k_first,
        input logic k_last,
        input logic signed [ARRAY_N*BIAS_W-1:0] bias_bus_in,
        input logic valid,
        input logic [ACC_ADDR_W-1:0] acc_addr,
        input logic exp_out_valid,
        input logic exp_write_en,
        input logic exp_read_en,
        input logic signed [ARRAY_N*ACC_BUFF-1:0] exp_sum_bus_in
    );
    begin 
        @(negedge clk);
        enable          = en;
        in_valid        = valid;
        in_k_tile_first = k_first;
        in_k_tile_last  = k_last;
        in_acc_addr     = acc_addr;
        in_psum_bus     = psum_bus_in;
        bias_in_bus     = bias_bus_in;

        #1; // Settle combinational logic on negedge clk BEFORE write clock edge!

        $display("  -> Inputs: addr=%0d, FIRST=%b, LAST=%b, valid=%b, enable=%b",
                 acc_addr, k_first, k_last, valid, en);

        // 1. Check control signals using !== (detects X and Z)
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

        // 2. Direct Buffer Address & Write Data Assertions (Sampled before write edge!)
        if (exp_write_en) begin
            if (buf_write_addr !== acc_addr) begin
                $error("FAIL: buf_write_addr mismatch! Expected %0d, Got %0d", acc_addr, buf_write_addr);
                errors++;
            end
            for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                logic signed [ACC_BUFF-1:0] act_wdata, exp_wdata;
                act_wdata = $signed(buf_write_data[lane*ACC_BUFF +: ACC_BUFF]);
                exp_wdata = $signed(exp_sum_bus_in[lane*ACC_BUFF +: ACC_BUFF]);
                if (act_wdata !== exp_wdata) begin
                    $error("FAIL: Lane %0d write data expected %0d, got %0d", lane, exp_wdata, act_wdata);
                    errors++;
                end
            end
        end

        if (exp_read_en) begin
            if (buf_read_addr !== acc_addr) begin
                $error("FAIL: buf_read_addr mismatch! Expected %0d, Got %0d", acc_addr, buf_read_addr);
                errors++;
            end
        end

        // 3. Advance to posedge clk and verify output metadata & vector when exp_out_valid=1
        @(posedge clk);
        #1;

        if (exp_out_valid) begin
            if (out_acc_addr !== acc_addr) begin
                $error("FAIL: out_acc_addr expected %0d, got %0d", acc_addr, out_acc_addr);
                errors++;
            end
            if (out_k_tile_first !== k_first) begin
                $error("FAIL: out_k_tile_first mismatch! Expected %b, Got %b", k_first, out_k_tile_first);
                errors++;
            end
            if (out_k_tile_last !== k_last) begin
                $error("FAIL: out_k_tile_last mismatch! Expected %b, Got %b", k_last, out_k_tile_last);
                errors++;
            end

            for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                logic signed [ACC_BUFF-1:0] act_sum, exp_s;
                act_sum = $signed(out_acc_bus[lane*ACC_BUFF +: ACC_BUFF]);
                exp_s   = $signed(exp_sum_bus_in[lane*ACC_BUFF +: ACC_BUFF]);
                if (act_sum !== exp_s) begin
                    $error("FAIL: Lane %0d output sum expected %0d, got %0d", lane, exp_s, act_sum);
                    errors++;
                end
                $display("     Lane %0d: psum=%0d | bias=%0d | out_acc_bus=%0d",
                         lane, $signed(in_psum_bus[lane*ACC_W +: ACC_W]),
                         $signed(bias_in_bus[lane*BIAS_W +: BIAS_W]), act_sum);
            end
            $display("  -> VERIFIED FULL 8-LANE ACCUMULATED OUTPUT VECTOR & METADATA!");
        end
    end
    endtask

    // Helper task for uniform scalar lane values
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
        logic signed [ARRAY_N*ACC_W-1:0] psum_bus_tmp;
        logic signed [ARRAY_N*BIAS_W-1:0] bias_bus_tmp;
        logic signed [ARRAY_N*ACC_BUFF-1:0] exp_bus_tmp;
    begin
        for (int l = 0; l < ARRAY_N; l = l + 1) begin
            psum_bus_tmp[l*ACC_W +: ACC_W]      = psum_val;
            bias_bus_tmp[l*BIAS_W +: BIAS_W]    = bias_val;
            exp_bus_tmp[l*ACC_BUFF +: ACC_BUFF] = exp_sum;
        end
        drive_inputs_packed(en, psum_bus_tmp, k_first, k_last, bias_bus_tmp, valid, acc_addr,
                            exp_out_valid, exp_write_en, exp_read_en, exp_bus_tmp);
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
                     1'b1, 1'b0, 1'b0, 33'sd15);

        // ==========================================
        // TEST 2: Enable Stall & Resume Check
        // ==========================================
        $display("\n--- TEST 2: Enable Stall & Resume Check ---");
        reset_dut();

        $display(" Sub-tile 1 (k=0, FIRST=1, LAST=0): Seed Bias=100 + Psum=20 => RAM[0x05] = 120");
        drive_inputs(1'b1, 32'sd20, 1'b1, 1'b0, 32'sd100, 1'b1, 8'h05,
                     1'b0, 1'b1, 1'b0, 33'sd120);

        $display(" STALL FOR 2 CYCLES (enable=0)");
        drive_inputs(1'b0, 32'sd99, 1'b0, 1'b0, 32'sd99, 1'b1, 8'h05,
                     1'b0, 1'b0, 1'b0, 33'sd0);
        drive_inputs(1'b0, 32'sd99, 1'b0, 1'b0, 32'sd99, 1'b1, 8'h05,
                     1'b0, 1'b0, 1'b0, 33'sd0);

        $display(" RESUME Sub-tile 2 (k=1, FIRST=0, LAST=0): Add Psum=30 => RAM[0x05] = 150");
        drive_inputs(1'b1, 32'sd30, 1'b0, 1'b0, 32'sd0, 1'b1, 8'h05,
                     1'b0, 1'b1, 1'b1, 33'sd150);

        $display(" RESUME Sub-tile 3 (k=2, FIRST=0, LAST=1): Final Psum=50 => Output = 200");
        drive_inputs(1'b1, 32'sd50, 1'b0, 1'b1, 32'sd0, 1'b1, 8'h05,
                     1'b1, 1'b0, 1'b1, 33'sd200);

        // ==========================================
        // TEST 3: Distinct Per-Lane Ordering Test
        // ==========================================
        $display("\n--- TEST 3: Distinct Per-Lane Ordering Test ---");
        reset_dut();
        begin
            logic signed [ARRAY_N*ACC_W-1:0] p_bus;
            logic signed [ARRAY_N*BIAS_W-1:0] b_bus;
            logic signed [ARRAY_N*ACC_BUFF-1:0] e_bus;
            for (int l = 0; l < ARRAY_N; l = l + 1) begin
                p_bus[l*ACC_W +: ACC_W]       = l + 1;                  // Lane 0=1, Lane 1=2, ... Lane 7=8
                b_bus[l*BIAS_W +: BIAS_W]     = (l + 1) * 10;           // Lane 0=10, Lane 1=20, ... Lane 7=80
                e_bus[l*ACC_BUFF +: ACC_BUFF] = (l + 1) + (l + 1) * 10; // Lane 0=11, Lane 1=22, ... Lane 7=88
            end
            drive_inputs_packed(1'b1, p_bus, 1'b1, 1'b1, b_bus, 1'b1, 8'h0A,
                                1'b1, 1'b0, 1'b0, e_bus);
        end

        // ==========================================
        // TEST 4: Signed Arithmetic Test (Negative Values)
        // ==========================================
        $display("\n--- TEST 4: Signed Arithmetic Test (Negative Values) ---");
        reset_dut();

        $display(" Sub-tile 1 (k=0, FIRST=1, LAST=0): Bias=-100 + Psum=20 => RAM[0x08] = -80");
        drive_inputs(1'b1, 32'sd20, 1'b1, 1'b0, -32'sd100, 1'b1, 8'h08,
                     1'b0, 1'b1, 1'b0, -33'sd80);

        $display(" Sub-tile 2 (k=1, FIRST=0, LAST=0): Psum=-30 + RAM[0x08] => RAM[0x08] = -110");
        drive_inputs(1'b1, -32'sd30, 1'b0, 1'b0, 32'sd0, 1'b1, 8'h08,
                     1'b0, 1'b1, 1'b1, -33'sd110);

        $display(" Sub-tile 3 (k=2, FIRST=0, LAST=1): Psum=10 + RAM[0x08] => Output = -100");
        drive_inputs(1'b1, 32'sd10, 1'b0, 1'b1, 32'sd0, 1'b1, 8'h08,
                     1'b1, 1'b0, 1'b1, -33'sd100);

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