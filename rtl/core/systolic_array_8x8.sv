`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module systolic_array_8x8(

    input logic clk,
    input logic rst_n,

    input logic enable,
    input logic [ARRAY_N-1:0] wgt_load,

    input logic signed [ARRAY_N*ACT_W-1:0] act_in_bus,
    input logic signed [ARRAY_N*WGT_W-1:0] wgt_in_bus,
    input logic signed [ARRAY_N*ACC_W-1:0] psum_in_bus,

    output logic signed [ARRAY_N*ACC_W-1:0] psum_out_bus,
    output logic signed [ARRAY_N*ACT_W-1:0] act_out_bus

);

logic signed [ACT_W-1:0] act_pipe [0:ARRAY_N-1][0:ARRAY_N];
logic signed [ACC_W-1:0] psum_pipe [0:ARRAY_N][0:ARRAY_N-1];

genvar row;
genvar col;

generate
    for(row=0;row<ARRAY_N;row=row+1) begin :gen_act_io
    assign act_pipe[row][0] = act_in_bus[row*ACT_W +:ACT_W];
    assign act_out_bus[row*ACT_W +:ACT_W] = act_pipe[row][ARRAY_N];
    end

    for (col = 0; col < ARRAY_N; col = col + 1) begin : gen_psum_io
            assign psum_pipe[0][col] = psum_in_bus[col*ACC_W +: ACC_W];
            assign psum_out_bus[col*ACC_W +: ACC_W] = psum_pipe[ARRAY_N][col];
        end
    for (row=0;row<ARRAY_N;row=row+1) begin : gen_pe_rows
        for(col=0;col<ARRAY_N;col=col+1) begin : gen_pe_cols

        pe_mac u_pe(

            .clk(clk),
            .rst_n(rst_n),
            .enable(enable),
            .clear_acc(1'b0),
            .wgt_load(wgt_load[row]),

            .act_in(act_pipe[row][col]),
            .wgt_in(wgt_in_bus[col*WGT_W +:WGT_W]),
            .psum_in(psum_pipe[row][col]),

            .act_out(act_pipe[row][col+1]),
            .psum_out(psum_pipe[row+1][col])
        );
        end
    end
endgenerate
endmodule

