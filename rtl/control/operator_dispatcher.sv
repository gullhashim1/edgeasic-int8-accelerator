// rtl/control/operator_dispatcher.sv
module operator_dispatcher (
    input  logic                   clk,
    input  logic                   rst_n,

    // Interface from Control Plane
    input  logic                   start_pulse,          // Start signal from CSR
    input  types_pkg::descriptor_t active_desc,          // The locked configuration descriptor
    
    // Core engine control handshakes
    output logic                   start_conv_gemm,      // Fire up the baseline core
    output logic                   start_conv2d_engine,  // Fire up the window generator[cite: 8]
    
    // Sticky error feedback to CSR block
    output logic                   error_unsupported_op  // Flagged for illegal operations[cite: 8]
);

    // --- PACKET ROUTING DISPATCH LOGIC ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            start_conv_gemm      <= 1'b0;
            start_conv2d_engine  <= 1'b0;
            error_unsupported_op <= 1'b0;
        end else begin
            // Single-cycle trigger pulses by default
            start_conv_gemm      <= 1'b0;
            start_conv2d_engine  <= 1'b0;
            error_unsupported_op <= 1'b0;

            if (start_pulse) begin
                case (active_desc.op_type)
                    
                    // Route to baseline dense math engine[cite: 8]
                    config_pkg::OP_CONV_GEMM: begin
                        start_conv_gemm <= 1'b1;
                    end
                    
                    // Route to the spatial window generator extension[cite: 8]
                    config_pkg::OP_CONV2D: begin
                        start_conv2d_engine <= 1'b1;
                    end
                    
                    // Treat advanced primary ops as unsupported until their local engines are ready[cite: 7, 8]
                    default: begin
                        error_unsupported_op <= 1'b1; // Trigger sticky error state[cite: 7, 8]
                    end
                    
                endcase
            end
        end
    end

endmodule