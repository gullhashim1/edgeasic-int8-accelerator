// tb/tb_operator_dispatcher.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_operator_dispatcher;

    logic        clk;
    logic        rst_n;

    logic        start_pulse;
    descriptor_t active_desc;

    logic        start_conv_gemm;
    logic        start_conv2d_engine;
    logic        error_unsupported_op;

    int errors = 0;

    always #2.5 clk = ~clk;

    operator_dispatcher dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start_pulse         (start_pulse),
        .active_desc         (active_desc),
        .start_conv_gemm     (start_conv_gemm),
        .start_conv2d_engine (start_conv2d_engine),
        .error_unsupported_op(error_unsupported_op)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        start_pulse = 0;
        active_desc = '0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING OPERATOR DISPATCHER TESTS (TC-ERR-001)");
        $display("=================================================");

        // TEST 1: Dispatch Baseline OP_CONV_GEMM
        $display("\n[TEST 1] Dispatching OP_CONV_GEMM");
        active_desc.op_type = OP_CONV_GEMM;
        @(posedge clk);
        start_pulse <= 1'b1;
        @(posedge clk);
        start_pulse <= 1'b0;
        #1;
        if (start_conv_gemm !== 1'b1 || start_conv2d_engine !== 1'b0 || error_unsupported_op !== 1'b0) begin
            $display("  FAIL: Failed to trigger start_conv_gemm!");
            errors++;
        end else begin
            $display("  PASS: start_conv_gemm pulsed high for 1 cycle.");
        end

        @(posedge clk);
        #1;
        if (start_conv_gemm !== 1'b0) begin
            $display("  FAIL: start_conv_gemm did not auto-clear!");
            errors++;
        end else begin
            $display("  PASS: start_conv_gemm correctly auto-cleared.");
        end

        // TEST 2: Dispatch OP_CONV2D
        $display("\n[TEST 2] Dispatching OP_CONV2D");
        active_desc.op_type = OP_CONV2D;
        @(posedge clk);
        start_pulse <= 1'b1;
        @(posedge clk);
        start_pulse <= 1'b0;
        #1;
        if (start_conv2d_engine !== 1'b1 || start_conv_gemm !== 1'b0 || error_unsupported_op !== 1'b0) begin
            $display("  FAIL: Failed to trigger start_conv2d_engine!");
            errors++;
        end else begin
            $display("  PASS: start_conv2d_engine pulsed high for 1 cycle.");
        end

        // TEST 3: TC-ERR-001 Unsupported Opcode Flags Sticky Error
        $display("\n[TEST 3] TC-ERR-001: Unsupported Opcode Rejection");
        active_desc.op_type = op_type_e'(4'hF); // Illegal/unsupported opcode
        @(posedge clk);
        start_pulse <= 1'b1;
        @(posedge clk);
        start_pulse <= 1'b0;
        #1;
        if (error_unsupported_op !== 1'b1 || start_conv_gemm !== 1'b0 || start_conv2d_engine !== 1'b0) begin
            $display("  FAIL: error_unsupported_op failed to assert!");
            errors++;
        end else begin
            $display("  PASS: error_unsupported_op pulsed and engines stayed inactive.");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL OPERATOR DISPATCHER TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("OPERATOR DISPATCHER TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
