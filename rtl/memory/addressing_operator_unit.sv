// rtl/memory/addressing_operator_unit.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module addressing_operator_unit (
    input  logic                   clk,
    input  logic                   rst_n,

    // Control Handshake from Dispatcher / Core
    input  logic                   start,
    input  op_type_e               op_type,       // OP_SPLIT, OP_CONCAT, OP_UPSAMPLE
    input  logic [AXI_ADDR_W-1:0]  src_base,
    input  logic [AXI_ADDR_W-1:0]  dst_base,
    input  logic [15:0]            dim_h,
    input  logic [15:0]            dim_w,
    input  logic [15:0]            dim_c,
    input  logic [15:0]            split_offset,  // Channel/byte offset for split

    output logic                   busy,
    output logic                   done,

    // Memory Read / Write Addressing Stream
    output logic                   mem_read_en,
    output logic [AXI_ADDR_W-1:0]  mem_read_addr,
    output logic                   mem_write_en,
    output logic [AXI_ADDR_W-1:0]  mem_write_addr
);

    typedef enum logic [1:0] {
        IDLE,
        EXEC_OP,
        FINISH
    } state_e;

    state_e state;

    logic [15:0] cur_h, cur_w, cur_c;
    logic        repeat_w; // For 2x nearest-neighbour horizontal repeat
    logic        repeat_h; // For 2x nearest-neighbour vertical repeat

    assign busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            done           <= 1'b0;
            mem_read_en    <= 1'b0;
            mem_read_addr  <= '0;
            mem_write_en   <= 1'b0;
            mem_write_addr <= '0;
            cur_h          <= '0;
            cur_w          <= '0;
            cur_c          <= '0;
            repeat_w       <= 1'b0;
            repeat_h       <= 1'b0;
        end else begin
            done         <= 1'b0;
            mem_write_en <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        cur_h       <= '0;
                        cur_w       <= '0;
                        cur_c       <= '0;
                        repeat_w    <= 1'b0;
                        repeat_h    <= 1'b0;
                        state       <= EXEC_OP;
                        mem_read_en <= 1'b1;
                    end else begin
                        mem_read_en <= 1'b0;
                    end
                end

                EXEC_OP: begin
                    case (op_type)
                        // Concat: direct translation with adjacent destination base
                        OP_CONCAT: begin
                            mem_read_addr  <= src_base + ((cur_h * dim_w + cur_w) * dim_c + cur_c);
                            mem_write_addr <= dst_base + ((cur_h * dim_w + cur_w) * dim_c + cur_c);
                            mem_write_en   <= 1'b1;

                            if (cur_c + 1'b1 < dim_c) begin
                                cur_c <= cur_c + 1'b1;
                            end else begin
                                cur_c <= '0;
                                if (cur_w + 1'b1 < dim_w) begin
                                    cur_w <= cur_w + 1'b1;
                                end else begin
                                    cur_w <= '0;
                                    if (cur_h + 1'b1 < dim_h) begin
                                        cur_h <= cur_h + 1'b1;
                                    end else begin
                                        state <= FINISH;
                                    end
                                end
                            end
                        end

                        // Split: base-plus-offset address translation
                        OP_SPLIT: begin
                            mem_read_addr  <= src_base + split_offset + ((cur_h * dim_w + cur_w) * dim_c + cur_c);
                            mem_write_addr <= dst_base + ((cur_h * dim_w + cur_w) * dim_c + cur_c);
                            mem_write_en   <= 1'b1;

                            if (cur_c + 1'b1 < dim_c) begin
                                cur_c <= cur_c + 1'b1;
                            end else begin
                                cur_c <= '0;
                                if (cur_w + 1'b1 < dim_w) begin
                                    cur_w <= cur_w + 1'b1;
                                end else begin
                                    cur_w <= '0;
                                    if (cur_h + 1'b1 < dim_h) begin
                                        cur_h <= cur_h + 1'b1;
                                    end else begin
                                        state <= FINISH;
                                    end
                                end
                            end
                        end

                        // 2x Nearest Upsample: repeat each pixel in 2x2 grid
                        OP_UPSAMPLE: begin
                            mem_read_addr  <= src_base + ((cur_h * dim_w + cur_w) * dim_c + cur_c);
                            mem_write_addr <= dst_base + (((cur_h * 2 + repeat_h) * (dim_w * 2) + (cur_w * 2 + repeat_w)) * dim_c + cur_c);
                            mem_write_en   <= 1'b1;

                            // Step through 2x2 replication per element
                            if (repeat_w == 1'b0) begin
                                repeat_w <= 1'b1;
                            end else begin
                                repeat_w <= 1'b0;
                                if (repeat_h == 1'b0) begin
                                    repeat_h <= 1'b1;
                                end else begin
                                    repeat_h <= 1'b0;
                                    if (cur_c + 1'b1 < dim_c) begin
                                        cur_c <= cur_c + 1'b1;
                                    end else begin
                                        cur_c <= '0;
                                        if (cur_w + 1'b1 < dim_w) begin
                                            cur_w <= cur_w + 1'b1;
                                        end else begin
                                            cur_w <= '0;
                                            if (cur_h + 1'b1 < dim_h) begin
                                                cur_h <= cur_h + 1'b1;
                                            end else begin
                                                state <= FINISH;
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        default: state <= FINISH;
                    endcase
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