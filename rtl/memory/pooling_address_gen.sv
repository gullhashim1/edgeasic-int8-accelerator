// rtl/memory/pooling_address_gen.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module pooling_address_gen (
    input  logic              clk,
    input  logic              rst_n,

    // Control Handshake from Dispatcher / Core
    input  logic              start,
    input  logic [2:0]        pool_size,    // 2 for 2x2, 5 for 5x5
    input  logic [15:0]       in_h,
    input  logic [15:0]       in_w,
    input  logic [15:0]       in_c,
    input  logic [AXI_ADDR_W-1:0] src_base,
    input  logic [AXI_ADDR_W-1:0] dst_base,

    output logic              busy,
    output logic              done,

    // Memory Read Address Stream to Output/Activation SRAM
    output logic              mem_read_en,
    output logic [AXI_ADDR_W-1:0] mem_read_addr,

    // Memory Write Address Stream for Downsampled Output
    output logic              mem_write_en,
    output logic [AXI_ADDR_W-1:0] mem_write_addr,
    output logic              window_last_sample // Pulses high on the final pixel of a window
);

    typedef enum logic [1:0] {
        IDLE,
        GEN_WINDOW,
        WRITE_DRAIN,
        FINISH
    } state_e;

    state_e state;

    logic [15:0] cur_oh, cur_ow, cur_c;
    logic [2:0]  win_h, win_w;

    assign busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            done               <= 1'b0;
            mem_read_en        <= 1'b0;
            mem_read_addr      <= '0;
            mem_write_en       <= 1'b0;
            mem_write_addr     <= '0;
            window_last_sample <= 1'b0;
            cur_oh             <= '0;
            cur_ow             <= '0;
            cur_c              <= '0;
            win_h              <= '0;
            win_w              <= '0;
        end else begin
            done               <= 1'b0;
            mem_write_en       <= 1'b0;
            window_last_sample <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state       <= GEN_WINDOW;
                        cur_oh      <= '0;
                        cur_ow      <= '0;
                        cur_c       <= '0;
                        win_h       <= '0;
                        win_w       <= '0;
                        mem_read_en <= 1'b1;
                    end else begin
                        mem_read_en <= 1'b0;
                    end
                end

                GEN_WINDOW: begin
                    // Compute flattened byte offset: ((cur_oh + win_h) * in_w + (cur_ow + win_w)) * in_c + cur_c
                    mem_read_addr <= src_base + (((cur_oh + win_h) * in_w + (cur_ow + win_w)) * in_c + cur_c);

                    if (win_w == pool_size - 1'b1 && win_h == pool_size - 1'b1) begin
                        window_last_sample <= 1'b1;
                        state              <= WRITE_DRAIN;
                    end else if (win_w == pool_size - 1'b1) begin
                        win_w <= '0;
                        win_h <= win_h + 1'b1;
                    end else begin
                        win_w <= win_w + 1'b1;
                    end
                end

                WRITE_DRAIN: begin
                    mem_write_en   <= 1'b1;
                    mem_write_addr <= dst_base + ((cur_oh * (in_w / pool_size) + cur_ow) * in_c + cur_c);

                    // Step across channels and spatial output points
                    win_h <= '0;
                    win_w <= '0;

                    if (cur_c + 1'b1 < in_c) begin
                        cur_c <= cur_c + 1'b1;
                        state <= GEN_WINDOW;
                    end else begin
                        cur_c <= '0;
                        if (cur_ow + pool_size < in_w) begin
                            cur_ow <= cur_ow + pool_size;
                            state  <= GEN_WINDOW;
                        end else begin
                            cur_ow <= '0;
                            if (cur_oh + pool_size < in_h) begin
                                cur_oh <= cur_oh + pool_size;
                                state  <= GEN_WINDOW;
                            end else begin
                                state <= FINISH;
                            end
                        end
                    end
                end

                FINISH: begin
                    mem_read_en <= 1'b0;
                    done        <= 1'b1;
                    state       <= IDLE;
                end
            endcase
        end
    end

endmodule