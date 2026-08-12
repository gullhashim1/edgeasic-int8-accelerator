// rtl/memory/dma_read_router.sv
module dma_read_router (
    input  logic        clk,
    input  logic        rst_n,

    // Bus Interface from AXI DMA Master
    input  logic        axi_rvalid,
    output logic        axi_rready,
    input  logic [511:0] axi_rdata,      // 512-bit (64-byte) beat from memory

    // Target Selection from Prefetch FSM
    input  logic [1:0]  target_sram_sel, // 00=Act, 01=Wgt, 10=Bias/Quant, 11=Res
    input  logic        target_bank_idx, // Ping-pong bank 0 or 1

    // Internal SRAM Write Ports
    output logic        sram_we,
    output logic [511:0] sram_wdata
);

    assign axi_rready = 1'b1; // Always ready to receive beat in baseline model
    assign sram_we    = axi_rvalid && axi_rready;

    // Direct byte-lane mapping from AXI beat to internal SRAM word
    assign sram_wdata = axi_rdata;

endmodule