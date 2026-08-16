`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_requant_golden;

    localparam int MAX_BEATS = 20000;

    logic clk;
    logic rst_n;
    logic enable;

    logic in_valid;
    logic [ACC_ADDR_W-1:0] in_acc_addr;
    logic signed [ARRAY_N*ACC_BUFF-1:0] in_acc_bus;

    logic [ARRAY_N*SCALE_W-1:0] scale_bus;
    logic [ARRAY_N*SHIFT_W-1:0] shift_bus;
    act_mode_e act_mode;

    logic out_valid;
    logic [ACC_ADDR_W-1:0] out_acc_addr;
    logic signed [ARRAY_N*OUT_W-1:0] out_data_bus;

    // Stimulus & Expected Memory Arrays
    logic [ARRAY_N*ACC_BUFF-1:0] stim_acc   [0:MAX_BEATS-1];
    logic [ARRAY_N*SCALE_W-1:0]  stim_scale [0:MAX_BEATS-1];
    logic [ARRAY_N*SHIFT_W-1:0]  stim_shift [0:MAX_BEATS-1];
    logic [15:0]                 stim_ctrl  [0:MAX_BEATS-1];
    logic [3:0]                  exp_valid  [0:MAX_BEATS-1];
    logic [ARRAY_N*OUT_W-1:0]    exp_out    [0:MAX_BEATS-1];

    requant dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .in_valid(in_valid),
        .in_acc_addr(in_acc_addr),
        .in_acc_bus(in_acc_bus),
        .scale_bus(scale_bus),
        .shift_bus(shift_bus),
        .act_mode(act_mode),
        .out_valid(out_valid),
        .out_acc_addr(out_acc_addr),
        .out_data_bus(out_data_bus)
    );

    int total_beats = 0;
    int valid_beats = 0;
    int checked_beats = 0;
    int mismatches = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        enable = 0;
        in_valid = 0;
        in_acc_addr = '0;
        in_acc_bus = '0;
        scale_bus = '0;
        shift_bus = '0;
        act_mode = ACT_NONE;

        $readmemh("tb/vectors/stim_req_acc.hex",   stim_acc);
        $readmemh("tb/vectors/stim_req_scale.hex", stim_scale);
        $readmemh("tb/vectors/stim_req_shift.hex", stim_shift);
        $readmemh("tb/vectors/stim_req_ctrl.hex",  stim_ctrl);
        $readmemh("tb/vectors/exp_req_valid.hex",  exp_valid);
        $readmemh("tb/vectors/exp_req_out.hex",    exp_out);

        #10 rst_n = 1;
        #10;

        $display("\n============================================================");
        $display("STARTING REQUANT & ACTIVATION GOLDEN REGRESSION");
        $display("============================================================");

        for (int i = 0; i < 5000; i++) begin
            logic [15:0] ctrl;
            ctrl = stim_ctrl[i];

            enable      = ctrl[15];
            in_valid    = ctrl[14];
            act_mode    = act_mode_e'(ctrl[13:12]);
            in_acc_addr = ctrl[7:0];
            in_acc_bus  = stim_acc[i];
            scale_bus   = stim_scale[i];
            shift_bus   = stim_shift[i];

            #1; // Combinational evaluation delay

            total_beats++;
            if (exp_valid[i][0]) begin
                valid_beats++;
            end

            // Check out_valid
            if (out_valid !== exp_valid[i][0]) begin
                $display("[ERROR Beat %0d] out_valid mismatch! Expected %0b, Got %0b",
                         i, exp_valid[i][0], out_valid);
                mismatches++;
            end

            // Check out_data_bus
            if (exp_valid[i][0]) begin
                if (out_data_bus !== exp_out[i]) begin
                    $display("[ERROR Beat %0d] out_data_bus mismatch!", i);
                    for (int l = 0; l < ARRAY_N; l++) begin
                        int8_s got_lane, exp_lane;
                        got_lane = out_data_bus[l*OUT_W +: OUT_W];
                        exp_lane = exp_out[i][l*OUT_W +: OUT_W];
                        if (got_lane !== exp_lane) begin
                            $display("  Lane %0d mismatch: Expected %0d (0x%02X), Got %0d (0x%02X) [acc=%0d, scale=%0d, shift=%0d, act=%0d]",
                                     l, exp_lane, exp_lane, got_lane, got_lane,
                                     $signed(stim_acc[i][l*ACC_BUFF +: ACC_BUFF]),
                                     stim_scale[i][l*SCALE_W +: SCALE_W],
                                     stim_shift[i][l*SHIFT_W +: SHIFT_W],
                                     act_mode);
                        end
                    end
                    mismatches++;
                end
                checked_beats++;
            end
        end

        $display("\n============================================================");
        $display("  Total beats driven    : %0d", total_beats);
        $display("  Valid beats checked   : %0d", checked_beats);
        $display("  Total mismatches      : %0d", mismatches);
        if (mismatches == 0) begin
            $display("  RESULT                : PASS -- RTL matches golden model bit-for-bit!");
        end else begin
            $display("  RESULT                : FAIL with %0d mismatches!", mismatches);
        end
        $display("============================================================\n");

        $finish;
    end

endmodule
