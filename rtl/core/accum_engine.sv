`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module accum_engine (
    input logic clk,
    input logic rst_n,
    input logic enable,

    // Stream Input Interface (Stage 1 Request)
    input logic in_valid,
    input logic signed [ARRAY_N*ACC_W-1:0] in_psum_bus,
    input logic in_k_tile_first,
    input logic in_k_tile_last,
    input logic [ACC_ADDR_W-1:0] in_acc_addr,
    input logic signed [ARRAY_N*BIAS_W-1:0] bias_in_bus,

    // SRAM Read Port Interface (Stage 1 Control / Stage 2 Data)
    output logic buf_read_en,
    output logic [ACC_ADDR_W-1:0] buf_read_addr,
    input  logic signed [ACC_BUFF*ARRAY_N-1:0] buf_read_data,

    // SRAM Write Port Interface (Stage 2 Control & Data)
    output logic buf_write_en,
    output logic [ACC_ADDR_W-1:0] buf_write_addr,
    output logic signed [ACC_BUFF*ARRAY_N-1:0] buf_write_data,

    // Stream Output Interface (Stage 2 Output)
    output logic out_valid,
    output logic out_k_tile_first,
    output logic out_k_tile_last,
    output logic [ACC_ADDR_W-1:0] out_acc_addr,
    output logic signed [ARRAY_N*ACC_BUFF-1:0] out_acc_bus
);

    // =========================================================================
    // STAGE 1: Read Request & Input Registering
    // =========================================================================
    logic s1_valid;
    logic signed [ARRAY_N*ACC_W-1:0] s1_psum_bus;
    logic signed [ARRAY_N*BIAS_W-1:0] s1_bias_in_bus;
    logic s1_k_tile_first;
    logic s1_k_tile_last;
    logic [ACC_ADDR_W-1:0] s1_acc_addr;

    // Issue SRAM Read Request for non-first tiles in Stage 1
    always_comb begin
        if (enable && in_valid && !in_k_tile_first) begin
            buf_read_en   = 1'b1;
            buf_read_addr = in_acc_addr;
        end else begin
            buf_read_en   = 1'b0;
            buf_read_addr = '0;
        end
    end

    // Stage 1 Pipeline Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid        <= 1'b0;
            s1_psum_bus     <= '0;
            s1_bias_in_bus  <= '0;
            s1_k_tile_first <= 1'b0;
            s1_k_tile_last  <= 1'b0;
            s1_acc_addr     <= '0;
        end else if (enable) begin
            s1_valid        <= in_valid;
            s1_psum_bus     <= in_psum_bus;
            s1_bias_in_bus  <= bias_in_bus;
            s1_k_tile_first <= in_k_tile_first;
            s1_k_tile_last  <= in_k_tile_last;
            s1_acc_addr     <= in_acc_addr;
        end
    end

    // =========================================================================
    // STAGE 2: Accumulate, RAW Hazard Bypass Forwarding & Output/Write-Back
    // =========================================================================
    
    // In-flight write tracking for RAW hazard bypass
    logic prev_s2_write_en;
    logic [ACC_ADDR_W-1:0] prev_s2_acc_addr;
    logic signed [ACC_BUFF*ARRAY_N-1:0] prev_s2_accum_result;

    logic raw_bypass_match;
    logic signed [ACC_BUFF*ARRAY_N-1:0] effective_read_data;
    logic signed [ACC_BUFF*ARRAY_N-1:0] s2_accum_result;

    // RAW Bypass Detection: Check if S1 read matches the write issued in S2 on previous cycle
    assign raw_bypass_match = s1_valid && !s1_k_tile_first && prev_s2_write_en && (s1_acc_addr == prev_s2_acc_addr);

    // Mux between forwarded write data and SRAM read output
    assign effective_read_data = raw_bypass_match ? prev_s2_accum_result : buf_read_data;

    // 8-Lane Parallel Vector Accumulation
    always_comb begin
        for (int i = 0; i < ARRAY_N; i = i + 1) begin
            if (s1_k_tile_first) begin
                s2_accum_result[i*ACC_BUFF +: ACC_BUFF] =
                    $signed(s1_bias_in_bus[i*BIAS_W +: BIAS_W]) +
                    $signed(s1_psum_bus[i*ACC_W +: ACC_W]);
            end else begin
                s2_accum_result[i*ACC_BUFF +: ACC_BUFF] =
                    $signed(effective_read_data[i*ACC_BUFF +: ACC_BUFF]) +
                    $signed(s1_psum_bus[i*ACC_W +: ACC_W]);
            end
        end
    end

    // SRAM Write Port Controls (Write back intermediate results for non-last tiles)
    always_comb begin
        if (enable && s1_valid && !s1_k_tile_last) begin
            buf_write_en   = 1'b1;
            buf_write_addr = s1_acc_addr;
            buf_write_data = s2_accum_result;
        end else begin
            buf_write_en   = 1'b0;
            buf_write_addr = '0;
            buf_write_data = '0;
        end
    end

    // Track write state for RAW bypass logic in the next clock cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_s2_write_en     <= 1'b0;
            prev_s2_acc_addr     <= '0;
            prev_s2_accum_result <= '0;
        end else if (enable) begin
            prev_s2_write_en     <= buf_write_en;
            prev_s2_acc_addr     <= buf_write_addr;
            prev_s2_accum_result <= s2_accum_result;
        end
    end

    // Stream Output Interface Controls (Emit result when last sub-tile completes)
    always_comb begin
        if (enable && s1_valid && s1_k_tile_last) begin
            out_valid        = 1'b1;
            out_k_tile_first = s1_k_tile_first;
            out_k_tile_last  = s1_k_tile_last;
            out_acc_addr     = s1_acc_addr;
            out_acc_bus      = s2_accum_result;
        end else begin
            out_valid        = 1'b0;
            out_k_tile_first = 1'b0;
            out_k_tile_last  = 1'b0;
            out_acc_addr     = '0;
            out_acc_bus      = '0;
        end
    end

endmodule