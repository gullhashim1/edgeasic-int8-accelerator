// rtl/control/csr_block.sv
module csr_block (
    input  logic        clk,
    input  logic        rst_n,          // Active-low synchronous reset

    // Host Bus Interface (Simplified Processor Bus)
    input  logic [7:0]  host_addr,      // Standard 8-bit register offset selection
    input  logic        host_write,     // Write enable strobe
    input  logic        host_read,      // Read enable strobe
    input  logic [31:0] host_wdata,     // Write data from host
    output logic [31:0] host_rdata,     // Read data back to host

    // Internal Control Signals to Core
    output logic        start_pulse,    // Triggers dispatcher engine
    output logic        soft_reset,     // Safe internal reset override
    output logic        perf_clear,     // Resets all performance logging metrics

    // Status / Error Inputs from Hardware Subsystems
    input  logic        engine_busy,    // Core is actively calculating
    input  logic        error_axi_boundary, // 4KB guard violation from DMA block
    input  logic        error_unsupported_op // Dispatcher flagged bad opcode
);

    // Internal Register Representations
    logic [31:0] reg_control;
    logic [31:0] reg_status;

    // Sticky error register flags
    logic sticky_err_axi;
    logic sticky_err_op;

    // --- WRITE LOGIC ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            start_pulse    <= 1'b0;
            soft_reset     <= 1'b0;
            perf_clear     <= 1'b0;
            sticky_err_axi <= 1'b0;
            sticky_err_op  <= 1'b0;
        end else begin
            // Clear single-cycle strobe lines by default so they only pulse once
            start_pulse <= 1'b0;
            perf_clear  <= 1'b0;

            if (host_write) begin
                case (host_addr)
                    8'h00: begin // CONTROL REGISTER
                        start_pulse <= host_wdata[0]; // Bit 0: START execution
                        soft_reset  <= host_wdata[1]; // Bit 1: SOFT_RESET latch
                        perf_clear  <= host_wdata[2]; // Bit 2: PERF_CLEAR strobe
                    end
                    8'h04: begin // STATUS REGISTER (W1C Error Clearing Logic)
                        if (host_wdata[4]) sticky_err_axi <= 1'b0; // Write 1 clears AXI error
                        if (host_wdata[2]) sticky_err_op  <= 1'b0; // Write 1 clears Op error
                    end
                    default: begin /* Ignore writes to undefined spaces */ end
                endcase
            end

            // --- STICKY ERROR SET LOGIC ---
            // Errors capture instantly and stay high until host clears them
            if (error_axi_boundary)   sticky_err_axi <= 1'b1;
            if (error_unsupported_op) sticky_err_op  <= 1'b1;
        end
    end

    // --- DYNAMIC STATUS REGISTER MAP ---
    always_comb begin
        reg_status = 32'h0;
        reg_status[0] = engine_busy;          // Bit 0: Engine Running status
        reg_status[2] = sticky_err_op;        // Bit 2: Sticky Unsupported Op Error
        reg_status[4] = sticky_err_axi;       // Bit 4: Sticky AXI 4KB Boundary Violation
    end

    // --- READ INTERFACE LOGIC ---
    always_comb begin
        host_rdata = 32'h0;
        if (host_read) begin
            case (host_addr)
                8'h00: host_rdata = {29'h0, perf_clear, soft_reset, start_pulse};
                8'h04: host_rdata = reg_status; // Read dynamic snapshot back to host
                default: host_rdata = 32'hDEADBEEF; // Unmapped zone diagnostic code
            endcase
        end
    end

endmodule