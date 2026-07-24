// rtl/pkg/config_pkg.sv
package config_pkg;

    // Computational Core Parameters
    localparam int N = 8;                  // Array dimension (8x8 grid)[cite: 1, 2]
    localparam int ARRAY_N = N;            // Alias for array dimension (8)
    localparam int PE_COUNT = 64;          // Total processing elements[cite: 1, 2]

    // Datapath Bit-Widths
    localparam int DATA_W = 8;             // INT8 Activation and Weight precision[cite: 1, 8]
    localparam int ACT_W  = DATA_W;        // INT8 Activation precision alias
    localparam int WGT_W  = DATA_W;        // INT8 Weight precision alias
    localparam int OUT_W  = DATA_W;        // INT8 Output precision alias
    localparam int ACC_W = 32;             // INT32 Accumulator precision[cite: 1, 8]
    localparam int ACC_BUFF = 33;          // INT33 Accumulation buffer precision
    localparam int BIAS_W = 32;            // INT32 Bias precision
    localparam int SCALE_W = 24;           // INT24 Quantization fixed-point scale precision[cite: 8]
    localparam int SHIFT_W = 8;            // Right-shift parameter precision

    // Memory Bus Parameters
    localparam int AXI_DATA_W = 512;       // External AXI memory data bus width[cite: 1, 8]
    localparam int AXI_ADDR_W = 64;        // External address width

    // Local Memory Configuration
    localparam int ACC_ADDR_W = 8;         // Depth address width for accumulation buffer[cite: 8]
    localparam int CHAN_W = 8;             // Channel index bit-width[cite: 8]
    localparam int TENSOR_ID_W = 4;        // Up to 16 entries in the Tensor Table[cite: 8]

    // Operation Types (OP_TYPE encodings)[cite: 8]
    typedef enum logic [3:0] {
        OP_CONV_GEMM   = 4'h0,             // Baseline dense tiled GEMM[cite: 8]
        OP_CONV2D      = 4'h1,             // Spatial convolution windowing[cite: 8]
        OP_SPLIT       = 4'h2,             // Tensor split[cite: 8]
        OP_CONCAT      = 4'h3,             // Tensor concat[cite: 8]
        OP_UPSAMPLE    = 4'h4,             // Nearest upsample[cite: 8]
        OP_MAXPOOL     = 4'h5,             // Maxpool[cite: 8]
        OP_SPPF        = 4'h6,             // SPPF sequencing[cite: 8]
        OP_LUT_SILU    = 4'h7,             // LUT-SiLU activation[cite: 8]
        OP_RAW_EXPORT  = 4'h8              // Output raw detection tensor[cite: 8]
    } op_type_e;

    // Activation Modes (ACT_MODE encodings)[cite: 8]
    typedef enum logic [1:0] {
        ACT_NONE       = 2'b00,            // Passthrough[cite: 8]
        ACT_RELU       = 2'b01,            // ReLU rectification[cite: 8]
        ACT_LUT_SILU   = 2'b10             // SiLU via Look-Up Table[cite: 8]
    } act_mode_e;

endpackage