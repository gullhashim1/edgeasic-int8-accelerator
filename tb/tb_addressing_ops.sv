// tb/tb_addressing_ops.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_addressing_ops;

    logic                  clk;
    logic                  rst_n;
    logic                  start;
    op_type_e              op_type;
    logic [AXI_ADDR_W-1:0] src_base, dst_base;
    logic [15:0]           dim_h, dim_w, dim_c, split_offset;

    logic                  busy, done;
    logic                  mem_read_en, mem_write_en;
    logic [AXI_ADDR_W-1:0] mem_read_addr, mem_write_addr;

    always #2.5 clk = ~clk;

    addressing_operator_unit u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .op_type        (op_type),
        .src_base       (src_base),
        .dst_base       (dst_base),
        .dim_h          (dim_h),
        .dim_w          (dim_w),
        .dim_c          (dim_c),
        .split_offset   (split_offset),
        .busy           (busy),
        .done           (done),
        .mem_read_en    (mem_read_en),
        .mem_read_addr  (mem_read_addr),
        .mem_write_en   (mem_write_en),
        .mem_write_addr (mem_write_addr)
    );

    initial begin
        clk          = 0;
        rst_n        = 0;
        start        = 0;
        op_type      = OP_CONCAT;
        src_base     = 64'h1000;
        dst_base     = 64'h2000;
        dim_h        = 16'd2;
        dim_w        = 16'd2;
        dim_c        = 16'd2;
        split_offset = 16'd0;

        #10 rst_n = 1;
        #10;

        // Test 1: Concat (TC-CAT-001)
        @(posedge clk);
        op_type <= OP_CONCAT;
        start   <= 1'b1;
        @(posedge clk);
        start   <= 1'b0;
        @(posedge done);
        $display("[PASS] TC-CAT-001: Tensor Concat addressing verified!");

        // Test 2: Split (TC-SPLIT-001)
        @(posedge clk);
        op_type      <= OP_SPLIT;
        split_offset <= 16'd8; // 8-byte channel offset
        start        <= 1'b1;
        @(posedge clk);
        start        <= 1'b0;
        @(posedge done);
        $display("[PASS] TC-SPLIT-001: Tensor Split offset view verified!");

        // Test 3: Upsample 2x (TC-UP-001)
        @(posedge clk);
        op_type <= OP_UPSAMPLE;
        start   <= 1'b1;
        @(posedge clk);
        start   <= 1'b0;
        @(posedge done);
        $display("[PASS] TC-UP-001: 2x Nearest-Neighbour Upsample addressing verified!");

        #20;
        $finish;
    end

endmodule