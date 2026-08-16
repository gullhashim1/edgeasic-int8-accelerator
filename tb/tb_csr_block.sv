// tb/tb_csr_block.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_csr_block;

    logic        clk;
    logic        rst_n;
    logic [7:0]  host_addr;
    logic        host_write;
    logic        host_read;
    logic [31:0] host_wdata;
    logic [31:0] host_rdata;

    logic        start_pulse;
    logic        soft_reset;
    logic        perf_clear;

    logic        engine_busy;
    logic        error_axi_boundary;
    logic        error_unsupported_op;

    int errors = 0;
    logic [31:0] rd_val;

    always #2.5 clk = ~clk;

    csr_block dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .host_addr           (host_addr),
        .host_write          (host_write),
        .host_read           (host_read),
        .host_wdata          (host_wdata),
        .host_rdata          (host_rdata),
        .start_pulse         (start_pulse),
        .soft_reset          (soft_reset),
        .perf_clear          (perf_clear),
        .engine_busy         (engine_busy),
        .error_axi_boundary  (error_axi_boundary),
        .error_unsupported_op(error_unsupported_op)
    );

    // Host write task
    task host_wr(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        host_addr  <= addr;
        host_wdata <= data;
        host_write <= 1'b1;
        host_read  <= 1'b0;
        @(posedge clk);
        host_write <= 1'b0;
    endtask

    // Host read task
    task host_rd(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        host_addr  <= addr;
        host_read  <= 1'b1;
        host_write <= 1'b0;
        #1; // Combinational read
        data = host_rdata;
        @(posedge clk);
        host_read  <= 1'b0;
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        host_addr = '0;
        host_write = 0;
        host_read = 0;
        host_wdata = '0;
        engine_busy = 0;
        error_axi_boundary = 0;
        error_unsupported_op = 0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING CSR BLOCK VERIFICATION (TC-CSR-001/002)");
        $display("=================================================");

        // TEST 1: TC-CSR-001 Reset Defaults
        $display("\n[TEST 1] TC-CSR-001: Checking Reset Default Values");
        if (start_pulse !== 1'b0 || soft_reset !== 1'b0 || perf_clear !== 1'b0) begin
            $display("  FAIL: Internal control lines not zeroed on reset!");
            errors++;
        end else begin
            $display("  PASS: Internal control lines reset correctly.");
        end

        host_rd(8'h04, rd_val); // Read status register
        if (rd_val !== 32'h0) begin
            $display("  FAIL: Status register not zero at reset! Got 0x%08X", rd_val);
            errors++;
        end else begin
            $display("  PASS: Status register defaults to 0x00000000.");
        end

        // TEST 2: Control Register Write & Auto-Clearing Pulses
        $display("\n[TEST 2] Writing Control Register (Start Pulse & Soft Reset)");
        host_wr(8'h00, 32'h00000003); // START (bit 0) and SOFT_RESET (bit 1)
        #1;
        if (start_pulse !== 1'b1 || soft_reset !== 1'b1) begin
            $display("  FAIL: Start pulse or soft reset failed to assert! start=%0b, soft=%0b", start_pulse, soft_reset);
            errors++;
        end else begin
            $display("  PASS: Start pulse and soft reset asserted on write.");
        end

        @(posedge clk);
        #1;
        if (start_pulse !== 1'b0) begin
            $display("  FAIL: start_pulse did not auto-clear after 1 cycle!");
            errors++;
        end else begin
            $display("  PASS: start_pulse correctly auto-cleared in next cycle.");
        end

        if (soft_reset !== 1'b1) begin
            $display("  FAIL: soft_reset should remain latched!");
            errors++;
        end else begin
            $display("  PASS: soft_reset remains latched.");
        end

        // TEST 3: Dynamic Status Register Reading (Engine Busy)
        $display("\n[TEST 3] Dynamic Status Mirroring (engine_busy)");
        engine_busy = 1'b1;
        #1;
        host_rd(8'h04, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("  FAIL: Status bit 0 (engine_busy) not reflected! Got 0x%08X", rd_val);
            errors++;
        end else begin
            $display("  PASS: Status bit 0 reflects engine_busy = 1.");
        end
        engine_busy = 1'b0;

        // TEST 4: TC-CSR-002 Sticky Error Capture & W1C Clearing
        $display("\n[TEST 4] TC-CSR-002: Sticky Errors and W1C Clearing");
        @(posedge clk);
        error_axi_boundary <= 1'b1;
        error_unsupported_op <= 1'b1;
        @(posedge clk);
        error_axi_boundary <= 1'b0;
        error_unsupported_op <= 1'b0;
        @(posedge clk);

        host_rd(8'h04, rd_val);
        if (rd_val[4] !== 1'b1 || rd_val[2] !== 1'b1) begin
            $display("  FAIL: Sticky errors not latched in status! Got 0x%08X", rd_val);
            errors++;
        end else begin
            $display("  PASS: Both sticky errors latched (AXI err bit 4, OP err bit 2).");
        end

        // Clear only AXI error with W1C
        $display("  Clearing AXI error (writing 1 to bit 4)...");
        host_wr(8'h04, 32'h00000010);
        host_rd(8'h04, rd_val);
        if (rd_val[4] !== 1'b0 || rd_val[2] !== 1'b1) begin
            $display("  FAIL: AXI error should be cleared and OP error remain! Got 0x%08X", rd_val);
            errors++;
        end else begin
            $display("  PASS: AXI error cleared, OP error still set.");
        end

        // Clear Op error with W1C
        $display("  Clearing Op error (writing 1 to bit 2)...");
        host_wr(8'h04, 32'h00000004);
        host_rd(8'h04, rd_val);
        if (rd_val[2] !== 1'b0) begin
            $display("  FAIL: OP error not cleared! Got 0x%08X", rd_val);
            errors++;
        end else begin
            $display("  PASS: All sticky errors cleanly cleared via W1C.");
        end

        // TEST 5: Unmapped Address Diagnostic Read
        $display("\n[TEST 5] Unmapped Address Diagnostic Code");
        host_rd(8'h7C, rd_val);
        if (rd_val !== 32'hDEADBEEF) begin
            $display("  FAIL: Expected 0xDEADBEEF for unmapped read, got 0x%08X", rd_val);
            errors++;
        end else begin
            $display("  PASS: Unmapped address returns 0xDEADBEEF.");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL CSR BLOCK TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("CSR BLOCK TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
