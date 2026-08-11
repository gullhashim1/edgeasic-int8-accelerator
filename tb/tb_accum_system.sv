`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_accum_system;

    logic clk;
    logic rst_n;
    logic enable;

    // Stream Input Interface
    logic in_valid;
    logic signed [ARRAY_N*ACC_W-1:0] in_psum_bus;
    logic in_k_tile_first;
    logic in_k_tile_last;
    logic [ACC_ADDR_W-1:0] in_acc_addr;
    logic signed [ARRAY_N*BIAS_W-1:0] bias_in_bus;

    // Interconnect between engine and 1R1W SRAM
    logic buf_read_en;
    logic [ACC_ADDR_W-1:0] buf_read_addr;
    logic signed [ACC_BUFF*ARRAY_N-1:0] buf_read_data;

    logic buf_write_en;
    logic [ACC_ADDR_W-1:0] buf_write_addr;
    logic signed [ACC_BUFF*ARRAY_N-1:0] buf_write_data;

    // Stream Output Interface
    logic out_valid;
    logic out_k_tile_first;
    logic out_k_tile_last;
    logic [ACC_ADDR_W-1:0] out_acc_addr;
    logic signed [ARRAY_N*ACC_BUFF-1:0] out_acc_bus;

    int errors;

    // Instantiate 2-Stage Pipelined Accumulator Engine
    accum_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .in_valid(in_valid),
        .in_psum_bus(in_psum_bus),
        .in_k_tile_first(in_k_tile_first),
        .in_k_tile_last(in_k_tile_last),
        .in_acc_addr(in_acc_addr),
        .bias_in_bus(bias_in_bus),

        .buf_read_en(buf_read_en),
        .buf_read_addr(buf_read_addr),
        .buf_read_data(buf_read_data),

        .buf_write_en(buf_write_en),
        .buf_write_addr(buf_write_addr),
        .buf_write_data(buf_write_data),

        .out_valid(out_valid),
        .out_k_tile_first(out_k_tile_first),
        .out_k_tile_last(out_k_tile_last),
        .out_acc_addr(out_acc_addr),
        .out_acc_bus(out_acc_bus)
    );

    // Instantiate 1R1W Synchronous SRAM Buffer
    accum_buffer ab_dut (
        .clk(clk),
        .read_enable(buf_read_en),
        .read_address(buf_read_addr),
        .read_data(buf_read_data),
        .write_enable(buf_write_en),
        .write_address(buf_write_addr),
        .write_data(buf_write_data)
    );

    // Clock Generator (100 MHz, 10ns period)
    always #5 clk = ~clk;

    task reset_dut();
    begin
        @(negedge clk);
        rst_n           = 1'b0;
        enable          = 1'b0;
        in_valid        = 1'b0;
        in_psum_bus     = '0;
        in_k_tile_first = 1'b0;
        in_k_tile_last  = 1'b0;
        in_acc_addr     = '0;
        bias_in_bus     = '0;
        repeat(2) @(posedge clk);
        @(negedge clk);
        rst_n           = 1'b1;
        enable          = 1'b1;
        #1;
        $display("[%0t ns] RESET COMPLETE", $time);
    end
    endtask

    // Drive subtile inputs on negedge clk
    task push_subtile_scalar(
        input logic valid,
        input logic k_first,
        input logic k_last,
        input logic [ACC_ADDR_W-1:0] acc_addr,
        input logic signed [ACC_W-1:0] psum_val,
        input logic signed [BIAS_W-1:0] bias_val
    );
        logic signed [ARRAY_N*ACC_W-1:0] p_bus;
        logic signed [ARRAY_N*BIAS_W-1:0] b_bus;
    begin
        for (int l = 0; l < ARRAY_N; l = l + 1) begin
            p_bus[l*ACC_W +: ACC_W]   = psum_val;
            b_bus[l*BIAS_W +: BIAS_W] = bias_val;
        end
        @(negedge clk);
        in_valid        = valid;
        in_k_tile_first = k_first;
        in_k_tile_last  = k_last;
        in_acc_addr     = acc_addr;
        in_psum_bus     = p_bus;
        bias_in_bus     = b_bus;
    end
    endtask

    initial begin
        clk    = 1'b0;
        errors = 0;

        reset_dut();

        // =====================================================================
        // TEST 1: Single Sub-tile (K=1, FIRST=1, LAST=1)
        // Latency: 1 cycle (driven on negedge, captured on posedge, output valid after posedge)
        // =====================================================================
        $display("\n--- TEST 1: Single Sub-tile (K=1, FIRST=1, LAST=1) ---");
        push_subtile_scalar(1'b1, 1'b1, 1'b1, 8'h01, 32'sd5, 32'sd10);

        @(posedge clk); #1;
        if (!out_valid) begin
            $error("FAIL TEST 1: out_valid expected high!");
            errors++;
        end else if (out_acc_addr !== 8'h01) begin
            $error("FAIL TEST 1: out_acc_addr expected 0x01, got 0x%0h", out_acc_addr);
            errors++;
        end else begin
            for (int l = 0; l < ARRAY_N; l++) begin
                logic signed [ACC_BUFF-1:0] act_s;
                act_s = $signed(out_acc_bus[l*ACC_BUFF +: ACC_BUFF]);
                if (act_s !== 33'sd15) begin
                    $error("FAIL TEST 1: Lane %0d sum expected 15, got %0d", l, act_s);
                    errors++;
                end
            end
            $display("TEST 1 PASSED: 10 + 5 = 15 correctly emitted after 1 clock cycle pipeline latency!");
        end

        // Clear input
        push_subtile_scalar(1'b0, 1'b0, 1'b0, 8'h00, 32'sd0, 32'sd0);

        // =====================================================================
        // TEST 2: Back-to-Back Same Address (K=3, RAW Hazard Bypass Check)
        // Sub-tile 0: FIRST=1, LAST=0, addr=0x05, bias=100, psum=20 -> Write 120
        // Sub-tile 1: FIRST=0, LAST=0, addr=0x05, psum=30 -> Bypass 120 -> Write 150
        // Sub-tile 2: FIRST=0, LAST=1, addr=0x05, psum=50 -> Bypass 150 -> Output 200
        // =====================================================================
        $display("\n--- TEST 2: Back-to-Back Same Address (RAW Hazard Bypass Test) ---");
        reset_dut();

        // Cycle 0: Inject Sub-tile 0
        $display(" Injecting Sub-tile 0 (k=0, FIRST=1, LAST=0, addr=0x05): bias=100, psum=20");
        push_subtile_scalar(1'b1, 1'b1, 1'b0, 8'h05, 32'sd20, 32'sd100);

        // Cycle 1: Inject Sub-tile 1 immediately back-to-back
        $display(" Injecting Sub-tile 1 (k=1, FIRST=0, LAST=0, addr=0x05): psum=30");
        push_subtile_scalar(1'b1, 1'b0, 1'b0, 8'h05, 32'sd30, 32'sd0);

        // Cycle 2: Inject Sub-tile 2 immediately back-to-back
        $display(" Injecting Sub-tile 2 (k=2, FIRST=0, LAST=1, addr=0x05): psum=50");
        push_subtile_scalar(1'b1, 1'b0, 1'b1, 8'h05, 32'sd50, 32'sd0);

        // Check output on posedge clk when Sub-tile 2 is processed in S2
        @(posedge clk); #1;
        if (!out_valid) begin
            $error("FAIL TEST 2: out_valid expected high!");
            errors++;
        end else if (out_acc_addr !== 8'h05) begin
            $error("FAIL TEST 2: out_acc_addr expected 0x05, got 0x%0h", out_acc_addr);
            errors++;
        end else begin
            for (int l = 0; l < ARRAY_N; l++) begin
                logic signed [ACC_BUFF-1:0] act_s;
                act_s = $signed(out_acc_bus[l*ACC_BUFF +: ACC_BUFF]);
                if (act_s !== 33'sd200) begin
                    $error("FAIL TEST 2: Lane %0d sum expected 200, got %0d", l, act_s);
                    errors++;
                end
            end
            $display("TEST 2 PASSED: 100 + 20 + 30 + 50 = 200 verified with RAW bypass forwarding!");
        end

        // Clear input
        push_subtile_scalar(1'b0, 1'b0, 1'b0, 8'h00, 32'sd0, 32'sd0);

        // =====================================================================
        // TEST 3: Interleaved Multi-Address Streaming
        // Address 0x0A (K=2) and Address 0x0B (K=2) interleaved
        // =====================================================================
        $display("\n--- TEST 3: Interleaved Multi-Address Streaming ---");
        reset_dut();

        // Cycle 0: Addr 0x0A, Tile 0 (FIRST=1, LAST=0, bias=10, psum=10 -> 20)
        push_subtile_scalar(1'b1, 1'b1, 1'b0, 8'h0A, 32'sd10, 32'sd10);

        // Cycle 1: Addr 0x0B, Tile 0 (FIRST=1, LAST=0, bias=40, psum=10 -> 50)
        push_subtile_scalar(1'b1, 1'b1, 1'b0, 8'h0B, 32'sd10, 32'sd40);

        // Cycle 2: Addr 0x0A, Tile 1 (FIRST=0, LAST=1, psum=15 -> 35)
        push_subtile_scalar(1'b1, 1'b0, 1'b1, 8'h0A, 32'sd15, 32'sd0);

        // Sample Output for 0x0A at posedge clk right after Tile 1 processing
        @(posedge clk); #1;
        if (!out_valid || out_acc_addr !== 8'h0A) begin
            $error("FAIL TEST 3 (0x0A): Expected valid output at 0x0A, got addr 0x%0h valid=%b", out_acc_addr, out_valid);
            errors++;
        end else begin
            logic signed [ACC_BUFF-1:0] s0a;
            s0a = $signed(out_acc_bus[0 +: ACC_BUFF]);
            if (s0a !== 33'sd35) begin
                $error("FAIL TEST 3 (0x0A): Expected sum 35, got %0d", s0a);
                errors++;
            end else begin
                $display("  -> Streamed Output 1 (0x0A): 10 + 10 + 15 = 35 VERIFIED!");
            end
        end

        // Cycle 3: Addr 0x0B, Tile 1 (FIRST=0, LAST=1, psum=25 -> 75)
        push_subtile_scalar(1'b1, 1'b0, 1'b1, 8'h0B, 32'sd25, 32'sd0);

        // Sample Output for 0x0B at posedge clk right after Tile 1 processing
        @(posedge clk); #1;
        if (!out_valid || out_acc_addr !== 8'h0B) begin
            $error("FAIL TEST 3 (0x0B): Expected valid output at 0x0B, got addr 0x%0h valid=%b", out_acc_addr, out_valid);
            errors++;
        end else begin
            logic signed [ACC_BUFF-1:0] s0b;
            s0b = $signed(out_acc_bus[0 +: ACC_BUFF]);
            if (s0b !== 33'sd75) begin
                $error("FAIL TEST 3 (0x0B): Expected sum 75, got %0d", s0b);
                errors++;
            end else begin
                $display("  -> Streamed Output 2 (0x0B): 40 + 10 + 25 = 75 VERIFIED!");
            end
        end
        $display("TEST 3 PASSED: Interleaved dual-address accumulation streaming verified!");

        // Clear input
        push_subtile_scalar(1'b0, 1'b0, 1'b0, 8'h00, 32'sd0, 32'sd0);

        // =====================================================================
        // TEST 4: Signed Arithmetic Test (Negative Values)
        // Sub-tile 0: bias = -100, psum = 20 -> -80
        // Sub-tile 1: psum = -30 -> -110
        // Sub-tile 2: psum = 10 -> -100
        // =====================================================================
        $display("\n--- TEST 4: Signed Arithmetic Test (Negative Values) ---");
        reset_dut();

        push_subtile_scalar(1'b1, 1'b1, 1'b0, 8'h08, 32'sd20, -32'sd100);
        push_subtile_scalar(1'b1, 1'b0, 1'b0, 8'h08, -32'sd30, 32'sd0);
        push_subtile_scalar(1'b1, 1'b0, 1'b1, 8'h08, 32'sd10, 32'sd0);

        @(posedge clk); #1;
        if (!out_valid || out_acc_addr !== 8'h08) begin
            $error("FAIL TEST 4: Expected output at addr 0x08");
            errors++;
        end else begin
            logic signed [ACC_BUFF-1:0] s_neg;
            s_neg = $signed(out_acc_bus[0 +: ACC_BUFF]);
            if (s_neg !== -33'sd100) begin
                $error("FAIL TEST 4: Expected sum -100, got %0d", s_neg);
                errors++;
            end else begin
                $display("TEST 4 PASSED: -100 + 20 - 30 + 10 = -100 VERIFIED!");
            end
        end

        // Clear input
        push_subtile_scalar(1'b0, 1'b0, 1'b0, 8'h00, 32'sd0, 32'sd0);

        // =====================================================================
        // SUMMARY REPORT
        // =====================================================================
        $display("\n============================================");
        if (errors == 0) begin
            $display("ALL 1R1W PIPELINED ACCUMULATOR TESTS PASSED!");
        end else begin
            $display("ERROR: %0d test failures detected in Accumulator System!", errors);
        end
        $display("============================================\n");

        $finish;
    end

endmodule