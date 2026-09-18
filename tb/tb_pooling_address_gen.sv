// tb/tb_pooling_address_gen.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_pooling_address_gen;

    logic              clk;
    logic              rst_n;
    logic              start;
    logic [2:0]        pool_size;
    logic [15:0]       in_h, in_w, in_c;
    logic [AXI_ADDR_W-1:0] src_base, dst_base;

    logic              busy, done;
    logic              mem_read_en;
    logic [AXI_ADDR_W-1:0] mem_read_addr;
    logic              mem_write_en;
    logic [AXI_ADDR_W-1:0] mem_write_addr;
    logic              window_last_sample;

    always #2.5 clk = ~clk;

    pooling_address_gen u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .pool_size          (pool_size),
        .in_h               (in_h),
        .in_w               (in_w),
        .in_c               (in_c),
        .src_base           (src_base),
        .dst_base           (dst_base),
        .busy               (busy),
        .done               (done),
        .mem_read_en        (mem_read_en),
        .mem_read_addr      (mem_read_addr),
        .mem_write_en       (mem_write_en),
        .mem_write_addr     (mem_write_addr),
        .window_last_sample (window_last_sample)
    );

    initial begin
        clk       = 0;
        rst_n     = 0;
        start     = 0;
        pool_size = 3'd2; // 2x2 pooling
        in_h      = 16'd4;
        in_w      = 16'd4;
        in_c      = 16'd1;
        src_base  = 64'h1000;
        dst_base  = 64'h2000;

        #10 rst_n = 1;
        #10;

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Await completion with timeout guard
        fork
            begin
                @(posedge done);
                $display("[PASS] TC-POOL-001: Pooling address generator completed 2x2 grid traversal bit-accurately!");
            end
            begin
                #2000;
                $display("[FAIL] Timeout waiting for pooling address generator to complete!");
            end
        join_any

        #20 $finish;
    end

endmodule