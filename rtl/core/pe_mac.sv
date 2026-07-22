`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module pe_mac (

    input  logic clk,
    input  logic rst_n,

    input  logic enable,
    input  logic clear_acc,
    input  logic wgt_load,

    input  logic signed [ACT_W-1:0] act_in,
    input  logic signed [WGT_W-1:0] wgt_in,
    input  logic signed [ACC_W-1:0] psum_in,

    output logic signed [ACT_W-1:0] act_out,
    output logic signed [ACC_W-1:0] psum_out

);

    logic signed [WGT_W-1:0] wgt_reg;
    logic signed [ACT_W+WGT_W-1:0] product;

    always_comb begin
        product = act_in * wgt_reg;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_reg  <= '0;
            act_out  <= '0;
            psum_out <= '0;
        end else begin

            if (wgt_load) begin
                wgt_reg <= wgt_in;
            end

            if (enable) begin
                act_out <= act_in;

                if (clear_acc) begin
                    psum_out <= product;
                end else begin
                    psum_out <= psum_in + product;
                end
            end

        end
    end

endmodule