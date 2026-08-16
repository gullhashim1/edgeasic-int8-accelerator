// tb/tb_dma_read_router.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_dma_read_router;

    logic         clk;
    logic         rst_n;

    logic         axi_rvalid;
    logic         axi_rready;
    logic [511:0] axi_rdata;

    logic [1:0]   target_sram_sel;
    logic         target_bank_idx;

    logic         sram_we;
    logic [511:0] sram_wdata;

    int errors = 0;

    always #2.5 clk = ~clk;

    dma_read_router dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .axi_rvalid     (axi_rvalid),
        .axi_rready     (axi_rready),
        .axi_rdata      (axi_rdata),
        .target_sram_sel(target_sram_sel),
        .target_bank_idx(target_bank_idx),
        .sram_we        (sram_we),
        .sram_wdata     (sram_wdata)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        axi_rvalid = 0;
        axi_rdata = '0;
        target_sram_sel = 2'b00;
        target_bank_idx = 1'b0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING DMA READ ROUTER TESTS (TC-DMA-003)");
        $display("=================================================");

        // TEST 1: Idle state
        $display("\n[TEST 1] Idle State (axi_rvalid = 0)");
        if (sram_we !== 1'b0 || axi_rready !== 1'b1) begin
            $display("  FAIL: sram_we should be 0 when axi_rvalid is low!");
            errors++;
        end else begin
            $display("  PASS: sram_we is 0 when idle.");
        end

        // TEST 2: Routing Activation Beat
        $display("\n[TEST 2] Routing 512-bit Activation Beat to SRAM");
        target_sram_sel = 2'b00; // Act SRAM
        target_bank_idx = 1'b0;
        axi_rvalid = 1'b1;
        axi_rdata  = {64{8'h5A}};
        #1;

        if (sram_we !== 1'b1 || sram_wdata !== {64{8'h5A}}) begin
            $display("  FAIL: sram_we failed to assert or data mismatch!");
            errors++;
        end else begin
            $display("  PASS: 512-bit word mapped and sram_we asserted.");
        end

        // TEST 3: Routing Weight Beat
        $display("\n[TEST 3] Routing 512-bit Weight Beat to SRAM");
        target_sram_sel = 2'b01; // Wgt SRAM
        target_bank_idx = 1'b1;
        axi_rvalid = 1'b1;
        axi_rdata  = {64{8'hA5}};
        #1;

        if (sram_we !== 1'b1 || sram_wdata !== {64{8'hA5}}) begin
            $display("  FAIL: Weight beat routing failed!");
            errors++;
        end else begin
            $display("  PASS: Weight beat correctly forwarded to SRAM write port.");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL DMA READ ROUTER TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("DMA READ ROUTER TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
