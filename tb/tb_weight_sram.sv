// tb/tb_weight_sram.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_weight_sram;

    localparam int ADDR_W = 10;
    localparam int DATA_W = 512;

    logic              clk;
    logic              we_a;
    logic [ADDR_W-1:0] addr_a;
    logic [DATA_W-1:0] wdata_a;
    logic [ADDR_W-1:0] addr_b;
    logic [DATA_W-1:0] rdata_b;

    int errors = 0;

    always #2.5 clk = ~clk;

    weight_sram #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .clk    (clk),
        .we_a   (we_a),
        .addr_a (addr_a),
        .wdata_a(wdata_a),
        .addr_b (addr_b),
        .rdata_b(rdata_b)
    );

    initial begin
        clk = 0;
        we_a = 0;
        addr_a = '0;
        wdata_a = '0;
        addr_b = '0;

        #10;

        $display("=================================================");
        $display("STARTING WEIGHT SRAM TESTS (TC-MEM-001)");
        $display("=================================================");

        // Write 4 lines
        $display("\n[TEST 1] Writing 4 lines to Port A (Addresses 0..3)");
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            we_a    <= 1'b1;
            addr_a  <= i[ADDR_W-1:0];
            wdata_a <= {16{32'hB000_0000 + i}};
        end
        @(posedge clk);
        we_a <= 1'b0;

        // Readback
        $display("\n[TEST 2] Reading back from Port B");
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            addr_b <= i[ADDR_W-1:0];
            @(posedge clk);
            #1;
            if (rdata_b !== {16{32'hB000_0000 + i}}) begin
                $display("  FAIL Addr %0d: Expected 0x%0128X, Got 0x%0128X", i, {16{32'hB000_0000 + i}}, rdata_b);
                errors++;
            end else begin
                $display("  PASS: Addr %0d read matched expected weight line.", i);
            end
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL WEIGHT SRAM TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("WEIGHT SRAM TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
