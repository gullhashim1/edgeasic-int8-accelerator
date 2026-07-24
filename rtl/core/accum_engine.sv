`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module accum_engine (
    
    input logic clk,
    input logic rst_n,
    input logic enable,

    input logic in_valid,
    input logic signed [ARRAY_N*ACC_W-1:0] in_psum_bus,
    input logic in_k_tile_first,
    input logic in_k_tile_last,
    input logic [ACC_ADDR_W-1:0] in_acc_addr,
    input logic [ARRAY_N*BIAS_W-1:0] bias_in_bus,

    input logic signed [ACC_BUFF*ARRAY_N-1:0] buf_read_data,
    
    output logic buf_read_en,
    output logic signed [ACC_BUFF*ARRAY_N-1:0] buf_write_data,
    output logic [ACC_ADDR_W-1:0] buf_write_addr,

    output logic out_valid,
    output logic out_k_tile_first,
    output logic out_k_tile_last,
    output logic [ACC_ADDR_W-1:0] out_acc_addr,

    output logic buf_write_en,
    output logic [ACC_ADDR_W-1:0] buf_read_addr,
    output logic signed [ARRAY_N*ACC_BUFF-1:0] out_acc_bus
);


    always_comb begin
        for (int i=0;i<ARRAY_N;i++) begin
            if (in_k_tile_first == 1) begin
                buf_write_data[i*ACC_BUFF+:ACC_BUFF] = $signed(bias_in_bus[i*BIAS_W+:BIAS_W]) + $signed(in_psum_bus[i*ACC_W+:ACC_W]);
            end
            else begin
                buf_write_data[i*ACC_BUFF+:ACC_BUFF] = $signed(buf_read_data[i*ACC_BUFF+:ACC_BUFF]) + $signed(in_psum_bus[i*ACC_W+:ACC_W]);
            end
        end
        if (enable == 1 && in_valid == 1) begin
            if(in_k_tile_last == 1) begin
                buf_write_en = 0;
                buf_write_addr = '0;
            end
            else begin
                buf_write_en = 1;
                buf_write_addr = in_acc_addr;
            end
            if(in_k_tile_first == 1) begin
                buf_read_en = 0;
                buf_read_addr = '0;
            end
            else begin
                buf_read_en = 1;
                buf_read_addr = in_acc_addr;
            end

            if(in_k_tile_last == 1) begin
                out_valid = in_valid;
            end
            else begin
                out_valid = 0;
            end
        out_k_tile_first = in_k_tile_first;
        out_k_tile_last = in_k_tile_last;
        out_acc_addr = in_acc_addr;

        out_acc_bus = buf_write_data;
        end
        else begin
            buf_write_en = 0;
            buf_write_addr = '0;
            buf_read_en = 0;
            buf_read_addr = '0;
            out_valid = 0;
            out_k_tile_first = '0;
            out_k_tile_last = '0;
            out_acc_addr = '0;
            out_acc_bus = '0;
        end
    end

endmodule