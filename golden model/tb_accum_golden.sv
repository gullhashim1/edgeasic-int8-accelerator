// tb_accum_golden.sv -- Vector-driven regression against the Python golden model.
//
// Replaces hand-computed expected values with thousands of model-generated beats.
// Generate vectors first:
//     cd model && python3 gen_vectors.py --beats 2000
//
// The DUT has 1 cycle of pipeline latency (S1 register), so a beat driven at
// cycle t produces its output at cycle t+1. Expected values are therefore
// compared one beat behind the stimulus.

`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_accum_golden;

    // Keep in sync with gen_vectors.py
    localparam int MAX_BEATS = 20000;
    localparam int CTRL_W    = 16;
    localparam string VECDIR = "tb/vectors/";

    logic clk = 0, rst_n, enable;
    logic in_valid, in_k_tile_first, in_k_tile_last;
    logic signed [ARRAY_N*ACC_W-1:0]  in_psum_bus;
    logic signed [ARRAY_N*BIAS_W-1:0] bias_in_bus;
    logic [ACC_ADDR_W-1:0] in_acc_addr;

    logic signed [ACC_BUFF*ARRAY_N-1:0] buf_read_data, buf_write_data;
    logic buf_read_en, buf_write_en;
    logic [ACC_ADDR_W-1:0] buf_read_addr, buf_write_addr;

    logic out_valid, out_k_tile_first, out_k_tile_last;
    logic [ACC_ADDR_W-1:0] out_acc_addr;
    logic signed [ARRAY_N*ACC_BUFF-1:0] out_acc_bus;

    // Vector storage
    logic [ARRAY_N*ACC_W-1:0]    v_psum  [0:MAX_BEATS-1];
    logic [ARRAY_N*BIAS_W-1:0]   v_bias  [0:MAX_BEATS-1];
    logic [CTRL_W-1:0]           v_ctrl  [0:MAX_BEATS-1];
    logic [3:0]                  v_evld  [0:MAX_BEATS-1];
    logic [ARRAY_N*ACC_BUFF-1:0] v_eacc  [0:MAX_BEATS-1];

    int n_beats = 0, errors = 0, checked = 0, emitted = 0;

    accum_engine dut(.*);

    accum_buffer ab(
        .clk(clk),
        .read_enable(buf_read_en),   .read_address(buf_read_addr),
        .read_data(buf_read_data),
        .write_enable(buf_write_en), .write_address(buf_write_addr),
        .write_data(buf_write_data)
    );

    always #5 clk = ~clk;

    // Control word field accessors
    function automatic logic ctrl_valid (input logic [CTRL_W-1:0] c); return c[15]; endfunction
    function automatic logic ctrl_first (input logic [CTRL_W-1:0] c); return c[14]; endfunction
    function automatic logic ctrl_last  (input logic [CTRL_W-1:0] c); return c[13]; endfunction
    function automatic logic [ACC_ADDR_W-1:0] ctrl_addr(input logic [CTRL_W-1:0] c);
        return c[ACC_ADDR_W-1:0];
    endfunction

    task automatic do_reset();
    begin
        @(negedge clk);
        rst_n = 0; enable = 0; in_valid = 0;
        in_psum_bus = '0; bias_in_bus = '0;
        in_k_tile_first = 0; in_k_tile_last = 0; in_acc_addr = '0;
        repeat(2) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        #1;
    end
    endtask

    // Count how many beats were actually loaded (unloaded entries read as X)
    // Icarus 12 does not support `break`, so use an explicit done flag.
    function automatic int count_beats();
        int n = 0;
        logic done = 1'b0;
        for (int i = 0; i < MAX_BEATS; i++) begin
            if (!done) begin
                if (^v_ctrl[i] === 1'bx) done = 1'b1;
                else n++;
            end
        end
        return n;
    endfunction

    task automatic check_beat(input int idx);
        logic signed [ACC_BUFF-1:0] act, exp;
    begin
        checked++;
        if (out_valid !== v_evld[idx][0]) begin
            $error("beat %0d: out_valid expected %b got %b",
                   idx, v_evld[idx][0], out_valid);
            errors++;
        end
        else if (v_evld[idx][0]) begin
            emitted++;
            if (out_acc_addr !== ctrl_addr(v_ctrl[idx])) begin
                $error("beat %0d: out_acc_addr expected 0x%02h got 0x%02h",
                       idx, ctrl_addr(v_ctrl[idx]), out_acc_addr);
                errors++;
            end
            for (int l = 0; l < ARRAY_N; l++) begin
                act = $signed(out_acc_bus[l*ACC_BUFF +: ACC_BUFF]);
                exp = $signed(v_eacc[idx][l*ACC_BUFF +: ACC_BUFF]);
                if (act !== exp) begin
                    $error("beat %0d lane %0d: expected %0d got %0d",
                           idx, l, exp, act);
                    errors++;
                end
            end
        end
    end
    endtask

    initial begin
        for (int j = 0; j < MAX_BEATS; j++) begin
            v_ctrl[j] = 'x;
            v_psum[j] = 'x;
            v_bias[j] = 'x;
            v_evld[j] = 'x;
            v_eacc[j] = 'x;
        end
        $readmemh({VECDIR, "stim_psum.hex"}, v_psum);
        $readmemh({VECDIR, "stim_bias.hex"}, v_bias);
        $readmemh({VECDIR, "stim_ctrl.hex"}, v_ctrl);
        $readmemh({VECDIR, "exp_valid.hex"}, v_evld);
        $readmemh({VECDIR, "exp_acc.hex"},   v_eacc);

        n_beats = count_beats();
        if (n_beats == 0) begin
            $display("ERROR: no vectors loaded from %s", VECDIR);
            $display("       run: cd model && python3 gen_vectors.py");
            $finish;
        end

        $display("\n=== GOLDEN MODEL REGRESSION: %0d beats ===", n_beats);
        do_reset();

        for (int i = 0; i < n_beats; i++) begin
            @(negedge clk);
            enable          = 1'b1;
            in_valid        = ctrl_valid(v_ctrl[i]);
            in_k_tile_first = ctrl_first(v_ctrl[i]);
            in_k_tile_last  = ctrl_last (v_ctrl[i]);
            in_acc_addr     = ctrl_addr (v_ctrl[i]);
            in_psum_bus     = v_psum[i];
            bias_in_bus     = v_bias[i];

            @(posedge clk);
            #1;
            check_beat(i);   // 1-cycle pipeline: beat i lands after edge i
        end

        // Drain
        @(negedge clk);
        in_valid = 0; in_k_tile_first = 0; in_k_tile_last = 0;
        @(posedge clk); #1;
        if (out_valid !== 1'b0) begin
            $error("out_valid stuck high after final beat");
            errors++;
        end

        $display("\n============================================");
        $display("  beats driven  : %0d", n_beats);
        $display("  beats checked : %0d", checked);
        $display("  outputs seen  : %0d", emitted);
        if (errors == 0)
            $display("  RESULT        : PASS -- RTL matches golden model");
        else
            $display("  RESULT        : FAIL -- %0d mismatch(es)", errors);
        $display("============================================\n");

        $finish;
    end

endmodule
