// rtl/memory/packing_fifo.sv
module packing_fifo (
    input  logic        clk,
    input  logic        rst_n,

    // Input vector from Person A's datapath (8 bytes per cycle)
    input  logic        vec_valid,
    output logic        vec_ready,
    input  logic [63:0] vec_data,        // 8-byte output chunk

    // Output beat to AXI DMA Master (64 bytes per beat)
    output logic        axi_wvalid,
    input  logic        axi_wready,
    output logic [511:0] axi_wdata,      // 512-bit packed write beat

    // Backpressure Indicator
    output logic        fifo_full
);

    logic [63:0] fifo_mem [0:7];         // Holds 8 chunks of 8 bytes (64 bytes total)
    logic [2:0]  chunk_count;

    assign fifo_full  = (chunk_count == 3'd7) && vec_valid && !axi_wready;
    assign vec_ready  = !fifo_full;
    assign axi_wvalid = (chunk_count == 3'd7) && vec_valid;

    // Pack 8-byte chunks into a 512-bit word
    assign axi_wdata  = {vec_data, fifo_mem[6], fifo_mem[5], fifo_mem[4],
                         fifo_mem[3], fifo_mem[2], fifo_mem[1], fifo_mem[0]};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chunk_count <= 3'd0;
            for (int i = 0; i < 8; i++) fifo_mem[i] <= 64'h0;
        end else if (vec_valid && vec_ready) begin
            if (chunk_count == 3'd7) begin
                if (axi_wready) begin
                    chunk_count <= 3'd0; // Beat sent, clear buffer
                end
            end else begin
                fifo_mem[chunk_count] <= vec_data;
                chunk_count <= chunk_count + 1'b1;
            end
        end
    end

endmodule