// tb/tb_axi_dma_master_abs.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_axi_dma_master_abs;

    logic        clk;
    logic        rst_n;

    logic        dma_req_valid;
    logic        dma_req_ready;
    logic [63:0] dma_req_addr;
    logic [15:0] dma_req_bytes;
    logic        dma_req_write;

    logic        dma_done;
    logic        dma_error;
    logic        error_axi_boundary;

    logic [63:0] axi_addr;
    logic        axi_valid;
    logic        axi_ready;

    int errors = 0;

    always #2.5 clk = ~clk;

    axi_dma_master_abs dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .dma_req_valid     (dma_req_valid),
        .dma_req_ready     (dma_req_ready),
        .dma_req_addr      (dma_req_addr),
        .dma_req_bytes     (dma_req_bytes),
        .dma_req_write     (dma_req_write),
        .dma_done          (dma_done),
        .dma_error         (dma_error),
        .error_axi_boundary(error_axi_boundary),
        .axi_addr          (axi_addr),
        .axi_valid         (axi_valid),
        .axi_ready         (axi_ready)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        dma_req_valid = 0;
        dma_req_addr = '0;
        dma_req_bytes = '0;
        dma_req_write = 0;
        axi_ready = 0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING AXI DMA MASTER TESTS (TC-DMA-001/002)");
        $display("=================================================");

        // TEST 1: Reset Defaults
        $display("\n[TEST 1] Checking Reset State");
        if (dma_req_ready !== 1'b1 || axi_valid !== 1'b0 || dma_done !== 1'b0) begin
            $display("  FAIL: Initial state mismatch! req_ready=%0b, axi_valid=%0b", dma_req_ready, axi_valid);
            errors++;
        end else begin
            $display("  PASS: DMA Master idle and ready on reset.");
        end

        // TEST 2: Legal Request (within 4KB page)
        $display("\n[TEST 2] Legal Transfer (Addr 0x1000, 256 Bytes -> Stays inside 4KB page)");
        @(posedge clk);
        dma_req_valid <= 1'b1;
        dma_req_addr  <= 64'h0000_1000;
        dma_req_bytes <= 16'd256;
        dma_req_write <= 1'b0;
        @(posedge clk);
        dma_req_valid <= 1'b0;
        #1;

        if (axi_valid !== 1'b1 || axi_addr !== 64'h0000_1000) begin
            $display("  FAIL: axi_valid failed to assert for legal request! axi_valid=%0b", axi_valid);
            errors++;
        end else begin
            $display("  PASS: Legal transfer issued to external AXI bus model.");
        end

        // AXI Slave handshakes
        @(posedge clk);
        axi_ready <= 1'b1;
        @(posedge clk);
        axi_ready <= 1'b0;
        #1;

        if (dma_done !== 1'b1 || dma_error !== 1'b0 || error_axi_boundary !== 1'b0) begin
            $display("  FAIL: Transfer did not complete cleanly! done=%0b, err=%0b", dma_done, dma_error);
            errors++;
        end else begin
            $display("  PASS: Transfer completed successfully with dma_done=1, dma_error=0.");
        end

        // TEST 3: TC-DMA-001 4KB Page Boundary Crossing Rejection
        $display("\n[TEST 3] TC-DMA-001: 4KB Boundary Violation Rejection (Addr 0x1F00 + 512 Bytes > 4KB boundary)");
        @(posedge clk);
        // Base addr lower 12 bits = 0xF00 (3840). 3840 + 512 = 4352 > 4096!
        dma_req_valid <= 1'b1;
        dma_req_addr  <= 64'h0000_1F00;
        dma_req_bytes <= 16'd512;
        dma_req_write <= 1'b0;
        @(posedge clk);
        dma_req_valid <= 1'b0;
        #1;

        if (dma_done !== 1'b1 || dma_error !== 1'b1 || error_axi_boundary !== 1'b1) begin
            $display("  FAIL: 4KB violation was not rejected locally! done=%0b, err=%0b, axi_err=%0b",
                     dma_done, dma_error, error_axi_boundary);
            errors++;
        end else begin
            $display("  PASS: 4KB boundary violation caught locally: dma_done=1, dma_error=1, error_axi_boundary=1.");
        end

        if (axi_valid !== 1'b0) begin
            $display("  FAIL: Illegal request was mistakenly issued to external AXI bus!");
            errors++;
        end else begin
            $display("  PASS: External AXI bus untouched (axi_valid=0).");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL AXI DMA MASTER TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("AXI DMA MASTER TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
