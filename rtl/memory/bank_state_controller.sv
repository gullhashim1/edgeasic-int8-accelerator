// rtl/memory/bank_state_controller.sv
module bank_state_controller #(
    parameter int NUM_BANKS = 2 // Ping-Pong Double Buffering
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Prefetch Producer Handshakes (DMA Filling)
    input  logic                   pf_fill_done,   // Prefetch DMA finished filling a bank
    input  logic [$clog2(NUM_BANKS)-1:0] pf_bank_idx, // Bank index being filled

    // Compute Consumer Handshakes (Math Core Reading)
    input  logic                   cf_consume_done, // Compute core finished reading a bank
    input  logic [$clog2(NUM_BANKS)-1:0] cf_bank_idx,  // Bank index being consumed

    // Status Queries back to FSMs
    output logic [NUM_BANKS-1:0]   bank_valid,     // Bank contains valid data
    output logic [NUM_BANKS-1:0]   bank_consumed,  // Bank is empty/free to fill
    output logic                   bsc_error       // Illegal state or collision error
);

    // Collision Detection: Triggered if Producer and Consumer attempt to write 
    // ownership changes to the EXACT same bank on the same clock cycle
    logic same_bank_collision;
    assign same_bank_collision = pf_fill_done && cf_consume_done && (pf_bank_idx == cf_bank_idx);

    // --- STATE TRACKING LOGIC ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset State: All banks start EMPTY (VALID=0, CONSUMED=1)
            bank_valid    <= '0;
            bank_consumed <= '1; // All 1s: free for prefetch to fill
            bsc_error     <= 1'b0;
        end else if (same_bank_collision) begin
            // Lock out state and raise error flag if collision occurs
            bsc_error <= 1'b1;
        end else begin
            // Handle Producer Completion (DMA Fill)
            if (pf_fill_done) begin
                bank_valid[pf_bank_idx]    <= 1'b1;
                bank_consumed[pf_bank_idx] <= 1'b0;
            end

            // Handle Consumer Completion (Compute Core)
            if (cf_consume_done) begin
                bank_valid[cf_bank_idx]    <= 1'b0;
                bank_consumed[cf_bank_idx] <= 1'b1;
            end
        end
    end

endmodule