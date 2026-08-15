// rtl/pkg/types_pkg.sv
package types_pkg;
    import config_pkg::*; // Bring in our parameters

    // Signed arithmetic shorthand types for Person A's datapath
    typedef logic signed [DATA_W-1:0]  int8_s;
    typedef logic signed [15:0]        int16_s;  // Product width
    typedef logic signed [ACC_W-1:0]   int32_s;  // Accumulator width
    typedef logic signed [32:0]        int33_s;  // Accumulator + Bias
    typedef logic signed [56:0]        int57_s;  // Scaled product

    // DYNAMIC PIPELINE METADATA PACKET
    // This bundle travels along the compute units cycle-by-cycle
    typedef struct packed {
        logic                  valid;           // Payload validity flag
        logic                  k_tile_first;    // Signals accumulator to seed bias
        logic                  k_tile_last;     // Signals accumulator to drain out
        logic [ACC_ADDR_W-1:0] acc_addr;        // Accumulator RAM target row
        logic [CHAN_W-1:0]     out_chan_base;   // Output channel lookup tracking
        logic [N-1:0]          lane_valid;      // Mask for dimensions not divisible by 8
        logic [TENSOR_ID_W-1:0] dst_tensor_id;  // Destination registration ID
    } pipe_meta_t;

    // LAYER CONFIGURATION DESCRIPTOR STRUCT
    // The blueprint packet programmed by the host software via CSR window
    typedef struct packed {
        op_type_e              op_type;         // Current engine instruction
        act_mode_e             act_mode;        // Selected activation loop
        logic                  residual_en;     // Toggle for skip-connection ADD
        logic                  partial_tile_en; // Toggle for lane masking logic
        logic                  tensor_table_en; // Toggle for automatic graph scheduling
        
        logic [63:0]           a_base;          // Activation tensor base address
        logic [63:0]           w_base;          // Weight tensor base address
        logic [63:0]           o_base;          // Output writeback address
        logic [63:0]           bq_base;         // Bias/Quant storage address
        logic [63:0]           input1_base;     // Residual tensor secondary address
        
        logic [15:0]           m;               // Tile matrix rows
        logic [15:0]           n;               // Tile matrix columns
        logic [15:0]           k;               // Sub-tile accumulation depth
        
        logic [TENSOR_ID_W-1:0] src0_tensor_id;  // Input reference ID
        logic [TENSOR_ID_W-1:0] dst_tensor_id;   // Output destination allocation ID
    } descriptor_t;

endpackage