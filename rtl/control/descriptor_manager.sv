// rtl/control/descriptor_manager.sv
module descriptor_manager (
    input  logic        clk,
    input  logic        rst_n,

    // Interface to CSR Block
    input  logic        desc_commit_pulse,   // Host requested a configuration commit
    input  config_pkg::op_type_e  csr_op_type, // Incoming fields from the CSR windows
    input  config_pkg::act_mode_e csr_act_mode,
    input  logic [63:0] csr_a_base,
    input  logic [63:0] csr_w_base,
    input  logic [63:0] csr_o_base,
    input  logic [15:0] csr_m,
    input  logic [15:0] csr_n,
    input  logic [15:0] csr_k,

    // Feedback status from other modules
    input  logic        engine_busy,         // Core is actively calculating
    output logic        commit_accept,       // Pulsed high if the host commit succeeded

    // Stable active descriptor outputs sent to the Dispatcher / Compute Core
    output types_pkg::descriptor_t active_desc
);

    // Create the "Inactive Buffer" to hold what the host is currently typing
    types_pkg::descriptor_t inactive_desc;
    
    // Internal signal to check if it's completely safe to accept new instructions
    logic safe_to_commit;
    assign safe_to_commit = !engine_busy;

    // Output status back to the CSR block
    assign commit_accept = desc_commit_pulse && safe_to_commit;

    // --- REGISTRATION LOGIC ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Clear out the active running descriptor on reset
            active_desc.op_type         <= config_pkg::OP_CONV_GEMM;
            active_desc.act_mode        <= config_pkg::ACT_NONE;
            active_desc.residual_en     <= 1'b0;
            active_desc.partial_tile_en <= 1'b0;
            active_desc.tensor_table_en <= 1'b0;
            active_desc.a_base          <= 64'h0;
            active_desc.w_base          <= 64'h0;
            active_desc.o_base          <= 64'h0;
            active_desc.bq_base         <= 64'h0;
            active_desc.input1_base     <= 64'h0;
            active_desc.m               <= 16'h0;
            active_desc.n               <= 16'h0;
            active_desc.k               <= 16'h0;
            active_desc.src0_tensor_id  <= 4'h0;
            active_desc.dst_tensor_id   <= 4'h0;
        end else if (commit_accept) begin
            // SWAP/COMMIT: Capture the entire inactive buffer into active state safely
            active_desc <= inactive_desc;
        end
    end

    // --- CONTINUOUS INACTIVE TRACKING ---
    // The inactive shadow layout mirrors whatever the host alters in real-time
    always_comb begin
        inactive_desc.op_type         = csr_op_type;
        inactive_desc.act_mode        = csr_act_mode;
        inactive_desc.residual_en     = 1'b0; // Hardwired defaults until future weeks
        inactive_desc.partial_tile_en = 1'b0;
        inactive_desc.tensor_table_en = 1'b0;
        inactive_desc.a_base          = csr_a_base;
        inactive_desc.w_base          = csr_w_base;
        inactive_desc.o_base          = csr_o_base;
        inactive_desc.bq_base         = 64'h0;
        inactive_desc.input1_base     = 64'h0;
        inactive_desc.m               = csr_m;
        inactive_desc.n               = csr_n;
        inactive_desc.k               = csr_k;
        inactive_desc.src0_tensor_id  = 4'h0;
        inactive_desc.dst_tensor_id   = 4'h0;
    end

endmodule