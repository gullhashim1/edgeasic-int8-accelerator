// rtl/pkg/types_pkg.sv
package types_pkg;
    import config_pkg::*; // Bring in our parameters[cite: 8]

    // Signed arithmetic shorthand types for Person A's datapath
    typedef logic signed [DATA_W-1:0]  int8_s;
    typedef logic signed [15:0]        int16_s;  // Product width[cite: 8]
    typedef logic signed [ACC_W-1:0]   int32_s;  // Accumulator width[cite: 8]
    typedef logic signed [32:0]        int33_s;  // Accumulator + Bias[cite: 8]
    typedef logic signed [56:0]        int57_s;  // Scaled product[cite: 8]

    // DYNAMIC PIPELINE METADATA PACKET
    // This bundle travels along the compute units cycle-by-cycle[cite: 8]
    typedef struct packed {
        logic                  valid;           // Payload validity flag[cite: 8]
        logic                  k_tile_first;    // Signals accumulator to seed bias[cite: 8]
        logic                  k_tile_last;     // Signals accumulator to drain out[cite: 8]
        logic [ACC_ADDR_W-1:0] acc_addr;        // Accumulator RAM target row[cite: 8]
        logic [CHAN_W-1:0]     out_chan_base;   // Output channel lookup tracking[cite: 8]
        logic [N-1:0]          lane_valid;      // Mask for dimensions not divisible by 8[cite: 8]
        logic [TENSOR_ID_W-1:0] dst_tensor_id;  // Destination registration ID[cite: 8]
    } pipe_meta_t;

    // LAYER CONFIGURATION DESCRIPTOR STRUCT
    // The blueprint packet programmed by the host software via CSR window[cite: 7, 8]
    typedef struct packed {
        op_type_e              op_type;         // Current engine instruction[cite: 8]
        act_mode_e             act_mode;        // Selected activation loop[cite: 8]
        logic                  residual_en;     // Toggle for skip-connection ADD[cite: 8]
        logic                  partial_tile_en; // Toggle for lane masking logic[cite: 8]
        logic                  tensor_table_en; // Toggle for automatic graph scheduling[cite: 8]
        
        logic [63:0]           a_base;          // Activation tensor base address[cite: 8]
        logic [63:0]           w_base;          // Weight tensor base address[cite: 8]
        logic [63:0]           o_base;          // Output writeback address[cite: 8]
        logic [63:0]           bq_base;         // Bias/Quant storage address[cite: 8]
        logic [63:0]           input1_base;     // Residual tensor secondary address[cite: 8]
        
        logic [15:0]           m;               // Tile matrix rows[cite: 8]
        logic [15:0]           n;               // Tile matrix columns[cite: 8]
        logic [15:0]           k;               // Sub-tile accumulation depth[cite: 8]
        
        logic [TENSOR_ID_W-1:0] src0_tensor_id;  // Input reference ID[cite: 8]
        logic [TENSOR_ID_W-1:0] dst_tensor_id;   // Output destination allocation ID[cite: 8]
    } descriptor_t;

endpackage