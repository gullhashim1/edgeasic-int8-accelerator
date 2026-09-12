// rtl/control/operator_dispatcher.sv
module operator_dispatcher
    import config_pkg::*;
    import types_pkg::*;
(
    input  logic              clk,
    input  logic              rst_n,

    // Dispatch Trigger & Config
    input  logic              start_dispatch,
    input  wire descriptor_t  desc,

    // Core Compute Engine Enables
    output logic              conv_gemm_en,
    output logic              conv2d_en,
    output logic              maxpool_sppf_en,
    output logic              lut_silu_en,
    output logic              raw_export_en,

    // Addressing-Only Flag
    output logic              addressing_only_op,

    // Error Reporting
    output logic              error_unsupported_op
);

    always_comb begin
        conv_gemm_en         = 1'b0;
        conv2d_en            = 1'b0;
        maxpool_sppf_en      = 1'b0;
        lut_silu_en          = 1'b0;
        raw_export_en        = 1'b0;
        addressing_only_op   = 1'b0;
        error_unsupported_op = 1'b0;

        if (start_dispatch) begin
            case (desc.op_type)
                OP_CONV_GEMM:   conv_gemm_en    = 1'b1;
                OP_CONV2D:      conv2d_en       = 1'b1;
                OP_MAXPOOL,
                OP_SPPF:        maxpool_sppf_en = 1'b1;
                OP_LUT_SILU:    lut_silu_en     = 1'b1;
                OP_RAW_EXPORT:  raw_export_en   = 1'b1;

                // Addressing-only operators: Handled purely via descriptor base/offset math
                OP_SPLIT,
                OP_CONCAT,
                OP_UPSAMPLE:    addressing_only_op = 1'b1;

                default:        error_unsupported_op = 1'b1;
            endcase
        end
    end

endmodule