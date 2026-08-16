// tb/tb_descriptor_manager.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_descriptor_manager;

    logic        clk;
    logic        rst_n;

    logic        desc_commit_pulse;
    op_type_e    csr_op_type;
    act_mode_e   csr_act_mode;
    logic [63:0] csr_a_base;
    logic [63:0] csr_w_base;
    logic [63:0] csr_o_base;
    logic [15:0] csr_m;
    logic [15:0] csr_n;
    logic [15:0] csr_k;

    logic        engine_busy;
    logic        commit_accept;
    descriptor_t active_desc;

    int errors = 0;

    always #2.5 clk = ~clk;

    descriptor_manager dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .desc_commit_pulse(desc_commit_pulse),
        .csr_op_type      (csr_op_type),
        .csr_act_mode     (csr_act_mode),
        .csr_a_base       (csr_a_base),
        .csr_w_base       (csr_w_base),
        .csr_o_base       (csr_o_base),
        .csr_m            (csr_m),
        .csr_n            (csr_n),
        .csr_k            (csr_k),
        .engine_busy      (engine_busy),
        .commit_accept    (commit_accept),
        .active_desc      (active_desc)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        desc_commit_pulse = 0;
        csr_op_type = OP_CONV_GEMM;
        csr_act_mode = ACT_NONE;
        csr_a_base = '0;
        csr_w_base = '0;
        csr_o_base = '0;
        csr_m = '0;
        csr_n = '0;
        csr_k = '0;
        engine_busy = 0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING DESCRIPTOR MANAGER (TC-DESC-001/002)");
        $display("=================================================");

        // TEST 1: Reset Defaults
        $display("\n[TEST 1] Checking Reset Default Active Descriptor");
        if (active_desc.op_type !== OP_CONV_GEMM || active_desc.m !== 16'd0) begin
            $display("  FAIL: Reset active_desc not matching defaults!");
            errors++;
        end else begin
            $display("  PASS: active_desc defaults verified.");
        end

        // TEST 2: TC-DESC-001 Commit While Idle (engine_busy = 0)
        $display("\n[TEST 2] TC-DESC-001: Commit While Idle");
        csr_op_type  = OP_CONV2D;
        csr_act_mode = ACT_RELU;
        csr_a_base   = 64'h1000_0000;
        csr_w_base   = 64'h2000_0000;
        csr_o_base   = 64'h3000_0000;
        csr_m        = 16'd64;
        csr_n        = 16'd32;
        csr_k        = 16'd128;
        engine_busy  = 1'b0;

        @(posedge clk);
        desc_commit_pulse <= 1'b1;
        @(posedge clk);
        desc_commit_pulse <= 1'b0;
        #1;

        if (active_desc.op_type !== OP_CONV2D ||
            active_desc.act_mode !== ACT_RELU ||
            active_desc.a_base !== 64'h1000_0000 ||
            active_desc.w_base !== 64'h2000_0000 ||
            active_desc.o_base !== 64'h3000_0000 ||
            active_desc.m !== 16'd64 ||
            active_desc.n !== 16'd32 ||
            active_desc.k !== 16'd128) begin
            $display("  FAIL: Active descriptor did not update to shadow values!");
            errors++;
        end else begin
            $display("  PASS: Active descriptor cleanly updated upon commit accept.");
        end

        // TEST 3: TC-DESC-002 Reject Unsafe Commit While Busy (engine_busy = 1)
        $display("\n[TEST 3] TC-DESC-002: Reject Unsafe Commit When Core is Busy");
        engine_busy = 1'b1;
        // Host tries to overwrite descriptor with illegal/new parameters while active
        csr_op_type  = OP_CONV_GEMM;
        csr_m        = 16'd999;

        @(posedge clk);
        desc_commit_pulse <= 1'b1;
        #1;
        if (commit_accept !== 1'b0) begin
            $display("  FAIL: commit_accept should be BLOCKED while engine is busy!");
            errors++;
        end else begin
            $display("  PASS: commit_accept remained 0 while engine_busy=1.");
        end

        @(posedge clk);
        desc_commit_pulse <= 1'b0;
        #1;
        if (active_desc.m !== 16'd64 || active_desc.op_type !== OP_CONV2D) begin
            $display("  FAIL: Active descriptor was corrupted during busy cycle!");
            errors++;
        end else begin
            $display("  PASS: Active descriptor protected against corruption while busy.");
        end

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL DESCRIPTOR MANAGER TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("DESCRIPTOR MANAGER TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
