// rtl/pkg/types_pkg.sv
package types_pkg;
    import config_pkg::*;

    // Standard Precision Types
    typedef logic signed [DATA_W-1:0]      int8_s;
    typedef logic signed [15:0]            int16_s;
    typedef logic signed [ACC_W-1:0]       int32_s;
    typedef logic signed [ACC_BUFF-1:0]    int33_s;
    typedef logic signed [56:0]            int57_s;

    // Dynamic Pipeline Metadata (Travels cycle-by-cycle with compute data)
    typedef struct packed {
        logic                  valid;
        logic                  k_tile_first;
        logic                  k_tile_last;
        logic [ACC_ADDR_W-1:0] acc_addr;
        logic [CHAN_W-1:0]     out_chan_base;
        logic [N-1:0]          lane_valid;
        logic [TENSOR_ID_W-1:0] dst_tensor_id;
    } pipe_meta_t;

    // Static Operation Descriptor (v5.0 Full-Scope Layout)
    typedef struct packed {
        op_type_e              op_type;
        act_mode_e             act_mode;

        // Base Addresses
        logic [AXI_ADDR_W-1:0] a_base;
        logic [AXI_ADDR_W-1:0] w_base;
        logic [AXI_ADDR_W-1:0] o_base;
        logic [AXI_ADDR_W-1:0] bq_base;
        logic [AXI_ADDR_W-1:0] input1_base; // Residual second-operand base
        logic [AXI_ADDR_W-1:0] lut_base;    // SiLU table base

        // Tile & Convolution Geometry
        logic [15:0]           m;
        logic [15:0]           n;
        logic [15:0]           k;
        logic [3:0]            kernel;      // 1=1x1, 3=3x3
        logic [3:0]            stride;      // 1 or 2
        logic [3:0]            pad;         // Padding mode / size

        // Feature Enables
        logic                  residual_en;
        logic                  partial_tile_en;
        logic                  tensor_table_en;

        // Graph / Tensor IDs
        logic [TENSOR_ID_W-1:0] src0_tensor_id;
        logic [TENSOR_ID_W-1:0] dst_tensor_id;
    } descriptor_t;

    // Tensor Table Entry Format
    typedef struct packed {
        logic [AXI_ADDR_W-1:0] base;
        logic [15:0]           h;
        logic [15:0]           w;
        logic [15:0]           c;
        logic [15:0]           row_stride;
        logic [15:0]           chan_stride;
        logic [7:0]            consumer_count;
        logic                  valid;
    } tensor_entry_t;

endpackage