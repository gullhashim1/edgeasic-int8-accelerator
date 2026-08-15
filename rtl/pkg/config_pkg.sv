// rtl/pkg/config_pkg.sv
package config_pkg;

    // Computational Core Parameters
    localparam int N = 8;                  // Array dimension (8x8 grid)
    localparam int PE_COUNT = 64;          // Total processing elements

    // Datapath Bit-Widths
    localparam int DATA_W = 8;             // INT8 Activation and Weight precision
    localparam int ACC_W = 32;             // INT32 Accumulator precision
    localparam int BIAS_W = 32;            // INT32 Bias precision
    localparam int SCALE_W = 24;           // INT24 Quantization fixed-point scale precision
    localparam int SHIFT_W = 8;            // Right-shift parameter precision

    // Memory Bus Parameters
    localparam int AXI_DATA_W = 512;       // External AXI memory data bus width
    localparam int AXI_ADDR_W = 64;        // External address width

    // Local Memory Configuration
    localparam int ACC_ADDR_W = 8;         // Depth address width for accumulation buffer
    localparam int CHAN_W = 8;             // Channel index bit-width
    localparam int TENSOR_ID_W = 4;        // Up to 16 entries in the Tensor Table

    // Operation Types (OP_TYPE encodings)
    typedef enum logic [3:0] {
        OP_CONV_GEMM   = 4'h0,             // Baseline dense tiled GEMM
        OP_CONV2D      = 4'h1,             // Spatial convolution windowing
        OP_SPLIT       = 4'h2,             // Tensor split
        OP_CONCAT      = 4'h3,             // Tensor concat
        OP_UPSAMPLE    = 4'h4,             // Nearest upsample
        OP_MAXPOOL     = 4'h5,             // Maxpool
        OP_SPPF        = 4'h6,             // SPPF sequencing
        OP_LUT_SILU    = 4'h7,             // LUT-SiLU activation
        OP_RAW_EXPORT  = 4'h8              // Output raw detection tensor
    } op_type_e;

    // Activation Modes (ACT_MODE encodings)
    typedef enum logic [1:0] {
        ACT_NONE       = 2'b00,            // Passthrough
        ACT_RELU       = 2'b01,            // ReLU rectification
        ACT_LUT_SILU   = 2'b10             // SiLU via Look-Up Table
    } act_mode_e;

endpackage