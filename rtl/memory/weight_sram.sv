// rtl/memory/weight_sram.sv
module weight_sram #(
    parameter int ADDR_W = 10,
    parameter int DATA_W = 512
)(
    input  logic              clk,

    // Port A: DMA Write Interface
    input  logic              we_a,
    input  logic [ADDR_W-1:0] addr_a,
    input  logic [DATA_W-1:0] wdata_a,

    // Port B: Weight-Stationary Array Loader Interface
    input  logic [ADDR_W-1:0] addr_b,
    output logic [DATA_W-1:0] rdata_b
);

    logic [DATA_W-1:0] ram [0:(2**ADDR_W)-1];

    always_ff @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= wdata_a;
        end
    end

    always_ff @(posedge clk) begin
        rdata_b <= ram[addr_b];
    end

endmodule