// rtl/memory/activation_sram.sv
module activation_sram #(
    parameter int ADDR_W = 10,
    parameter int DATA_W = 512
)(
    input  logic              clk,

    // Port A: DMA Read Router Write Interface (Producer)
    input  logic              we_a,
    input  logic [ADDR_W-1:0] addr_a,
    input  logic [DATA_W-1:0] wdata_a,

    // Port B: Systolic Array Read Interface (Consumer)
    input  logic [ADDR_W-1:0] addr_b,
    output logic [DATA_W-1:0] rdata_b
);

    // Dual-Port Synchronous SRAM block
    logic [DATA_W-1:0] ram [0:(2**ADDR_W)-1];

    // Port A - Write
    always_ff @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= wdata_a;
        end
    end

    // Port B - Read
    always_ff @(posedge clk) begin
        rdata_b <= ram[addr_b];
    end

endmodule