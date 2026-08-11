`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

// 1R1W (1 Read Port, 1 Write Port) Synchronous SRAM Macro Model
module accum_buffer (
    input  logic clk,

    // Read Port (Synchronous 1-cycle latency)
    input  logic read_enable,
    input  logic [ACC_ADDR_W-1:0] read_address,
    output logic signed [ACC_BUFF*ARRAY_N-1:0] read_data,

    // Write Port (Synchronous write)
    input  logic write_enable,
    input  logic [ACC_ADDR_W-1:0] write_address,
    input  logic signed [ACC_BUFF*ARRAY_N-1:0] write_data
);

    // 256 entries x 264 bits memory array
    logic signed [ACC_BUFF*ARRAY_N-1:0] mem [0:2**ACC_ADDR_W-1];

    // 1. Synchronous Read Port (Sampled on posedge clk)
    always_ff @(posedge clk) begin
        if (read_enable) begin
            read_data <= mem[read_address];
        end
    end

    // 2. Synchronous Write Port (Committed on posedge clk)
    always_ff @(posedge clk) begin
        if (write_enable) begin
            mem[write_address] <= write_data;
        end
    end

endmodule
