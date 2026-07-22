//Metadata follows lane 0 / maximum-delay timing and is valid only when out_valid is high.
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module sddu (

    input logic clk,
    input logic rst_n,
    input logic in_valid,
    input logic enable,
    input logic signed [ARRAY_N*ACC_W-1:0] in_psum_bus,
    input logic in_k_tile_first,
    input logic in_k_tile_last,
    input logic [ACC_ADDR_W-1:0] in_acc_addr,

    output logic out_valid,
    output logic signed [ARRAY_N*ACC_W-1:0] out_psum_bus,
    output logic out_k_tile_first,
    output logic out_k_tile_last,
    output logic [ACC_ADDR_W-1:0] out_acc_addr

);

    localparam int MAX_DELAY=ARRAY_N-1;
    logic signed [ACC_W-1:0] psum_pipe [0:ARRAY_N-1][0:MAX_DELAY-1];
    logic valid_pipe [0:MAX_DELAY-1];
    logic k_tile_first_pipe [0:MAX_DELAY-1];
    logic k_tile_last_pipe [0:MAX_DELAY-1];
    logic [ACC_ADDR_W-1:0] acc_addr_pipe [0:MAX_DELAY-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0;i<ARRAY_N;i=i+1) begin
                for(int j=0;j<MAX_DELAY;j=j+1) begin
                    psum_pipe[i][j] <= '0;
                end
            end
            
            for (int i = 0;i<MAX_DELAY;i=i+1) begin
                valid_pipe[i] <= '0;
                k_tile_first_pipe[i] <= '0;
                k_tile_last_pipe[i] <= '0;
                acc_addr_pipe[i] <= '0;
            end
            
        end else if(enable) begin
        
        for (int i = 0;i<ARRAY_N;i=i+1) begin
            psum_pipe[i][0] <= $signed(in_psum_bus[i*ACC_W +:ACC_W]);
        for (int j=1; j<MAX_DELAY;j=j+1) begin
            psum_pipe[i][j] <= psum_pipe[i][j-1];
        end
        end
        valid_pipe[0] <= in_valid;
        k_tile_first_pipe[0] <= in_k_tile_first;
        k_tile_last_pipe[0] <= in_k_tile_last;
        acc_addr_pipe[0] <= in_acc_addr;
        for (int k=1;k<MAX_DELAY;k=k+1) begin
            valid_pipe[k] <= valid_pipe[k-1];
            k_tile_first_pipe[k] <= k_tile_first_pipe[k-1];
            k_tile_last_pipe[k] <= k_tile_last_pipe[k-1];
            acc_addr_pipe[k] <= acc_addr_pipe[k-1];
        end

    end
    end
    genvar c;
    generate
        for (c = 0; c< ARRAY_N;c=c+1) begin
            localparam int DELAY = MAX_DELAY-c;
            if (DELAY == 0) begin
                assign out_psum_bus[c*ACC_W +: ACC_W] = in_psum_bus[c*ACC_W +: ACC_W];
            end
            else begin
                assign out_psum_bus[c*ACC_W +: ACC_W] = psum_pipe[c][DELAY-1];
            end
            
        end
    endgenerate

    assign out_valid = valid_pipe[MAX_DELAY-1];
    assign out_k_tile_first = k_tile_first_pipe[MAX_DELAY-1];
    assign out_k_tile_last = k_tile_last_pipe[MAX_DELAY-1];
    assign out_acc_addr = acc_addr_pipe[MAX_DELAY-1];


endmodule
