`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module accum_buffer(

    input logic clk,
    input logic read_enable,

    input logic [ACC_ADDR_W-1:0] read_address,
    output logic signed [ACC_BUFF*ARRAY_N-1:0] read_data,

    input logic write_enable,
    input logic [ACC_ADDR_W-1:0] write_address,
    input logic signed [ACC_BUFF*ARRAY_N-1:0] write_data
    
);

    logic signed [ACC_BUFF*ARRAY_N-1:0] mem [0:2**ACC_ADDR_W-1];

    always_comb begin
        if (write_enable) begin
            mem[write_address] = write_data;
        end
        else begin
            mem[write_address] = '0;
        end

        if (read_enable) begin
            read_data = mem[read_address];
        end
        else begin
            read_data = '0;

        end
    end

endmodule
