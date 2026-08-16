// tb/tb_packing_fifo.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_packing_fifo;

    logic         clk;
    logic         rst_n;

    // Input vector from datapath (8 bytes per cycle)
    logic         vec_valid;
    logic         vec_ready;
    logic [63:0]  vec_data;

    // Output beat to AXI DMA Master (64 bytes per beat)
    logic         axi_wvalid;
    logic         axi_wready;
    logic [511:0] axi_wdata;

    logic         fifo_full;

    int errors = 0;
    logic [511:0] expected_512;

    always #2.5 clk = ~clk;

    packing_fifo dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .vec_valid  (vec_valid),
        .vec_ready  (vec_ready),
        .vec_data   (vec_data),
        .axi_wvalid (axi_wvalid),
        .axi_wready (axi_wready),
        .axi_wdata  (axi_wdata),
        .fifo_full  (fifo_full)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        vec_valid = 0;
        vec_data = '0;
        axi_wready = 0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING PACKING FIFO VERIFICATION (TC-FIFO-001/002)");
        $display("=================================================");

        // TEST 1: Reset Defaults
        $display("\n[TEST 1] Checking Reset Defaults");
        if (axi_wvalid !== 1'b0 || fifo_full !== 1'b0 || vec_ready !== 1'b1) begin
            $display("  FAIL: Initial flags mismatch! axi_wvalid=%0b, fifo_full=%0b, vec_ready=%0b",
                     axi_wvalid, fifo_full, vec_ready);
            errors++;
        end else begin
            $display("  PASS: Reset state verified.");
        end

        // TEST 2: TC-FIFO-001 8-Chunk Accumulation into 512-bit Beat
        $display("\n[TEST 2] TC-FIFO-001: Pushing 8 Chunks of 8 Bytes (64B AXI Beat)");
        axi_wready = 1'b1;

        for (int i = 0; i < 7; i++) begin
            @(posedge clk);
            vec_valid <= 1'b1;
            vec_data  <= {32'hAAAA_0000, 32'(i)};
            #1;
            if (axi_wvalid !== 1'b0) begin
                $display("  FAIL: axi_wvalid asserted prematurely at chunk %0d!", i);
                errors++;
            end
        end

        // 8th chunk (completing 64-byte beat)
        @(posedge clk);
        vec_valid <= 1'b1;
        vec_data  <= {32'hAAAA_0000, 32'd7};
        #1;
        if (axi_wvalid !== 1'b1) begin
            $display("  FAIL: axi_wvalid failed to assert on 8th chunk!");
            errors++;
        end else begin
            $display("  PASS: axi_wvalid asserted on 8th chunk.");
        end

        // Check 512-bit assembled data
        expected_512 = {
            {32'hAAAA_0000, 32'd7},
            {32'hAAAA_0000, 32'd6},
            {32'hAAAA_0000, 32'd5},
            {32'hAAAA_0000, 32'd4},
            {32'hAAAA_0000, 32'd3},
            {32'hAAAA_0000, 32'd2},
            {32'hAAAA_0000, 32'd1},
            {32'hAAAA_0000, 32'd0}
        };

        if (axi_wdata !== expected_512) begin
            $display("  FAIL: axi_wdata mismatch! Got 0x%0128X", axi_wdata);
            errors++;
        end else begin
            $display("  PASS: 512-bit word assembled with exact byte ordering.");
        end

        // TEST 3: TC-FIFO-002 Backpressure Stall & Buffer Full Flag
        $display("\n[TEST 3] TC-FIFO-002: Backpressure (axi_wready = 0 stalls datapath)");
        @(posedge clk);
        vec_valid <= 1'b0;
        axi_wready <= 1'b0; // Downstream DMA not ready
        @(posedge clk);

        // Fill 7 chunks
        for (int i = 0; i < 7; i++) begin
            @(posedge clk);
            vec_valid <= 1'b1;
            vec_data  <= {32'hBBBB_0000, 32'(i)};
        end

        // Drive 8th chunk with axi_wready = 0
        @(posedge clk);
        vec_valid <= 1'b1;
        vec_data  <= {32'hBBBB_0000, 32'd7};
        #1;

        if (fifo_full !== 1'b1 || vec_ready !== 1'b0) begin
            $display("  FAIL: fifo_full should be 1 and vec_ready 0 when backpressured!");
            errors++;
        end else begin
            $display("  PASS: fifo_full correctly asserts and throttles vec_ready.");
        end

        // Release downstream backpressure
        @(posedge clk);
        axi_wready <= 1'b1;
        vec_valid  <= 1'b0;
        @(posedge clk);
        #1;
        if (fifo_full !== 1'b0 || vec_ready !== 1'b1) begin
            $display("  FAIL: FIFO did not clear after axi_wready pulse!");
            errors++;
        end else begin
            $display("  PASS: FIFO successfully drained and cleared backpressure.");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL PACKING FIFO TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("PACKING FIFO TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
