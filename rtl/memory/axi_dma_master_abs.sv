// rtl/memory/axi_dma_master_abs.sv
module axi_dma_master_abs (
    input  logic        clk,
    input  logic        rst_n,

    // Internal Request Interface from Prefetch/Compute FSMs
    input  logic        dma_req_valid,   // FSM requests a DMA transfer
    output logic        dma_req_ready,   // DMA master ready to accept request
    input  logic [63:0] dma_req_addr,    // Target base memory address
    input  logic [15:0] dma_req_bytes,   // Total bytes requested in transfer
    input  logic        dma_req_write,   // 1 = Write to memory, 0 = Read from memory

    // Internal Completion Interface
    output logic        dma_done,        // Pulsed high when transfer finishes (or errors out)
    output logic        dma_error,       // Pulsed high alongside done if an error occurred

    // Sticky Error Feedback to CSR Block
    output logic        error_axi_boundary, // Toggled high on 4KB boundary violation

    // Simplified External Bus Model Interface
    output logic [63:0] axi_addr,
    output logic        axi_valid,
    input  logic        axi_ready
);

    // --- 4 KB PAGE BOUNDARY CHECKER ---
    // Evaluates lower 12 bits of address + byte payload against 4096-byte limit
    logic crosses_4kb;
    assign crosses_4kb = ({20'h0, dma_req_addr[11:0]} + {16'h0, dma_req_bytes}) > 32'd4096;

    // FSM States for DMA abstraction
    typedef enum logic [1:0] {
        DMA_IDLE      = 2'b00,
        DMA_TRANSFER  = 2'b01,
        DMA_ERROR_ACK = 2'b10
    } dma_state_e;

    dma_state_e state;

    // Ready to accept new request only when completely IDLE
    assign dma_req_ready = (state == DMA_IDLE);

    // --- STATE MACHINE & GUARD LOGIC ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= DMA_IDLE;
            dma_done           <= 1'b0;
            dma_error          <= 1'b0;
            error_axi_boundary <= 1'b0;
            axi_addr           <= 64'h0;
            axi_valid          <= 1'b0;
        end else begin
            // Single-cycle default pulses
            dma_done           <= 1'b0;
            dma_error          <= 1'b0;
            error_axi_boundary <= 1'b0;

            case (state)
                DMA_IDLE: begin
                    if (dma_req_valid && dma_req_ready) begin
                        if (crosses_4kb) begin
                            // LOCAL REJECTION: Do NOT issue to external bus!
                            dma_done           <= 1'b1;
                            dma_error          <= 1'b1;
                            error_axi_boundary <= 1'b1; // Trigger sticky CSR error
                            state              <= DMA_IDLE; // Complete locally immediately
                        end else begin
                            // LEGAL REQUEST: Issue to bus model
                            axi_addr  <= dma_req_addr;
                            axi_valid <= 1'b1;
                            state     <= DMA_TRANSFER;
                        end
                    end
                end

                DMA_TRANSFER: begin
                    if (axi_valid && axi_ready) begin
                        axi_valid <= 1'b0;
                        dma_done  <= 1'b1;
                        dma_error <= 1'b0;
                        state     <= DMA_IDLE;
                    end
                end

                default: state <= DMA_IDLE;
            endcase
        end
    end

endmodule