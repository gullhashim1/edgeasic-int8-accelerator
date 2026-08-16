`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module requant (
    // Future Pipelining Controls
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               enable,

    // Stream Input Interface (from accum_engine)
    input  logic                               in_valid,
    input  logic [ACC_ADDR_W-1:0]              in_acc_addr,
    input  logic signed [ARRAY_N*ACC_BUFF-1:0] in_acc_bus,

    // Layer Quantization & Activation Parameters (Unsigned)
    input  logic [ARRAY_N*SCALE_W-1:0]         scale_bus,
    input  logic [ARRAY_N*SHIFT_W-1:0]         shift_bus,
    input  act_mode_e                          act_mode,

    // Stream Output Interface (INT8 post-requant & activation)
    output logic                               out_valid,
    output logic [ACC_ADDR_W-1:0]              out_acc_addr,
    output logic signed [ARRAY_N*OUT_W-1:0]    out_data_bus
);

    // =========================================================================
    // CONTROL METADATA FORWARDING
    // =========================================================================
    always_comb begin
        if (enable && in_valid) begin
            out_valid    = 1'b1;
            out_acc_addr = in_acc_addr;
        end else begin
            out_valid    = 1'b0;
            out_acc_addr = '0;
        end
    end

    // =========================================================================
    // PARALLEL REQUANTIZATION & ACTIVATION LANES (0 to ARRAY_N-1)
    // =========================================================================
    generate
        for (genvar lane = 0; lane < ARRAY_N; lane++) begin : gen_lane_requant
            int33_s                 acc_val;
            logic [SCALE_W-1:0]     scale_val;
            logic [SHIFT_W-1:0]     shift_val;

            int57_s                 product;
            logic                   round_bit;
            int57_s                 shifted_raw;
            int57_s                 rounded_product;
            int8_s                  clamped_val;
            int8_s                  activated_val;

            always_comb begin
                if (enable && in_valid) begin
                    // 1. Unpack per-lane slice
                    acc_val   = in_acc_bus[lane*ACC_BUFF +: ACC_BUFF];
                    scale_val = scale_bus[lane*SCALE_W +: SCALE_W];
                    shift_val = shift_bus[lane*SHIFT_W +: SHIFT_W];

                    // 2. Signed (33-bit) * Unsigned (24-bit) -> 57-bit signed product
                    product = acc_val * $signed({1'b0, scale_val});

                    // 3. Shift-then-Increment HALF_UP Rounding:
                    // Identity: (x + 2^(s-1)) >> s == (x >>> s) + x[s-1]
                    // Eliminates the 58-bit variable left-shifter and full adder
                    if (shift_val == 0) begin
                        rounded_product = product;
                    end else if (shift_val < 57) begin
                        round_bit       = product[shift_val - 1];
                        shifted_raw     = product >>> shift_val;
                        rounded_product = shifted_raw + $signed({56'd0, round_bit});
                    end else begin
                        rounded_product = 57'sd0;
                    end

                    // 4. INT8 Saturation / Clamping to [-128, +127]
                    if (rounded_product > 57'sd127) begin
                        clamped_val = 8'sd127;
                    end else if (rounded_product < -57'sd128) begin
                        clamped_val = -8'sd128;
                    end else begin
                        clamped_val = rounded_product[OUT_W-1:0];
                    end

                    // 5. Activation Function
                    case (act_mode)
                        ACT_NONE:     activated_val = clamped_val;
                        ACT_RELU:     activated_val = (clamped_val < 8'sd0) ? 8'sd0 : clamped_val;
                        ACT_LUT_SILU: activated_val = clamped_val; // Target for Week 27 LUT ROM integration
                        default:      activated_val = clamped_val;
                    endcase
                end else begin
                    acc_val         = '0;
                    scale_val       = '0;
                    shift_val       = '0;
                    product         = '0;
                    round_bit       = '0;
                    shifted_raw     = '0;
                    rounded_product = '0;
                    clamped_val     = '0;
                    activated_val   = '0;
                end
            end

            // 6. Pack into output bus
            assign out_data_bus[lane*OUT_W +: OUT_W] = activated_val;
        end
    endgenerate

endmodule
