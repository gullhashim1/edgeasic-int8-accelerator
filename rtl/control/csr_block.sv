// rtl/control/csr_block.sv
`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module csr_block (
    input  logic        clk,
    input  logic        rst_n,

    // Host AXI-Lite / CSR Bus Interface
    input  logic        cs,
    input  logic        we,
    input  logic [7:0]  addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    // Control Outputs
    output logic        ctrl_start,
    output logic        ctrl_soft_reset,
    output logic        ctrl_perf_clear,
    output logic        ctrl_irq_enable,

    // Engine Status Inputs
    input  logic        engine_busy,
    input  logic        engine_done,

    // Sticky Error Inputs (Write-1-to-Clear)
    input  logic        err_unsupported_op,
    input  logic        err_axi_boundary,
    input  logic        err_shape,
    input  logic        err_bsc,

    // Performance Counter Inputs (from perf_counters.sv)
    input  logic [31:0] perf_total_cycles,
    input  logic [31:0] perf_compute_cycles,
    input  logic [31:0] perf_dma_wait_cycles,
    input  logic [31:0] perf_stall_cycles,
    input  logic [31:0] perf_writeback_cycles,
    input  logic [31:0] perf_mac_active_cycles
);

    // Register Offsets matching v5.0 Specification
    localparam logic [7:0] REG_CONTROL      = 8'h00;
    localparam logic [7:0] REG_STATUS       = 8'h04;
    localparam logic [7:0] REG_PERF_TOTAL   = 8'h60;
    localparam logic [7:0] REG_PERF_COMPUTE = 8'h64;
    localparam logic [7:0] REG_PERF_DMA     = 8'h68;
    localparam logic [7:0] REG_PERF_STALL   = 8'h6C;
    localparam logic [7:0] REG_PERF_WB      = 8'h70;
    localparam logic [7:0] REG_PERF_MAC_ACT = 8'h74;

    logic reg_irq_enable;
    logic sticky_unsupported_op;
    logic sticky_axi_boundary;
    logic sticky_shape_error;
    logic sticky_bsc_error;

    // Control Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_start      <= 1'b0;
            ctrl_soft_reset <= 1'b0;
            ctrl_perf_clear <= 1'b0;
            reg_irq_enable  <= 1'b0;
        end else begin
            ctrl_start      <= 1'b0;
            ctrl_soft_reset <= 1'b0;
            ctrl_perf_clear <= 1'b0;

            if (cs && we && (addr == REG_CONTROL)) begin
                ctrl_start      <= wdata[0];
                ctrl_soft_reset <= wdata[1];
                ctrl_perf_clear <= wdata[2];
                reg_irq_enable  <= wdata[3];
            end
        end
    end

    assign ctrl_irq_enable = reg_irq_enable;

    // Sticky Errors with W1C Semantics
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sticky_unsupported_op <= 1'b0;
            sticky_axi_boundary   <= 1'b0;
            sticky_shape_error    <= 1'b0;
            sticky_bsc_error      <= 1'b0;
        end else begin
            if (err_unsupported_op) sticky_unsupported_op <= 1'b1;
            if (err_axi_boundary)   sticky_axi_boundary   <= 1'b1;
            if (err_shape)          sticky_shape_error    <= 1'b1;
            if (err_bsc)            sticky_bsc_error      <= 1'b1;

            if (cs && we && (addr == REG_STATUS)) begin
                if (wdata[2]) sticky_unsupported_op <= 1'b0;
                if (wdata[4]) sticky_axi_boundary   <= 1'b0;
                if (wdata[6]) sticky_shape_error    <= 1'b0;
                if (wdata[8]) sticky_bsc_error      <= 1'b0;
            end
        end
    end

    // CSR Read MUX
    always_comb begin
        rdata = '0;
        if (cs && !we) begin
            case (addr)
                REG_CONTROL: begin
                    rdata[3] = reg_irq_enable;
                end
                REG_STATUS: begin
                    rdata[0] = engine_busy;
                    rdata[1] = engine_done;
                    rdata[2] = sticky_unsupported_op;
                    rdata[4] = sticky_axi_boundary;
                    rdata[6] = sticky_shape_error;
                    rdata[8] = sticky_bsc_error;
                end
                REG_PERF_TOTAL:   rdata = perf_total_cycles;
                REG_PERF_COMPUTE: rdata = perf_compute_cycles;
                REG_PERF_DMA:     rdata = perf_dma_wait_cycles;
                REG_PERF_STALL:   rdata = perf_stall_cycles;
                REG_PERF_WB:      rdata = perf_writeback_cycles;
                REG_PERF_MAC_ACT: rdata = perf_mac_active_cycles;
                default:          rdata = '0;
            endcase
        end
    end

endmodule