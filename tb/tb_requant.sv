`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_requant;

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

    int errors;
    int expected_val;
    int actual_val;
    int p_val;

    always #2.5 clk = ~clk;

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

    task drive_lane(
        input int lane,
        input int33_s acc,
        input logic [SCALE_W-1:0] scale,
        input logic [SHIFT_W-1:0] shift,
        input act_mode_e mode,
        input logic [ACC_ADDR_W-1:0] addr
    );
        in_acc_bus = '0;
        scale_bus  = '0;
        shift_bus  = '0;
        act_mode   = mode;
        in_acc_addr = addr;
        in_valid   = 1'b1;
        enable     = 1'b1;

        in_acc_bus[lane*ACC_BUFF +: ACC_BUFF] = acc;
        scale_bus[lane*SCALE_W +: SCALE_W]    = scale;
        shift_bus[lane*SHIFT_W +: SHIFT_W]    = shift;
        #1;
    endtask

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
        errors = 0;

        #10 rst_n = 1;
        #10;

        $display("=================================================");
        $display("STARTING DIRECTED REQUANT & ACTIVATION TESTS");
        $display("=================================================");

        // TEST 1: Idle & Gating
        $display("\n[TEST 1] Idle and Enable Gating");
        enable = 0; in_valid = 0;
        in_acc_bus[0*ACC_BUFF +: ACC_BUFF] = 33'sd100;
        scale_bus[0*SCALE_W +: SCALE_W] = 24'd1;
        #1;
        if (out_valid !== 1'b0 || out_data_bus !== '0) begin
            $display("  FAIL: outputs not zeroed when enable=0!");
            errors++;
        end else begin
            $display("  PASS: Idle outputs zeroed correctly.");
        end

        // TEST 2: Basic Scaling and HALF_UP Rounding (5 * 2 >> 2 = 2.5 -> 3)
        $display("\n[TEST 2] Basic HALF_UP Rounding (2.5 -> 3)");
        drive_lane(0, 33'sd5, 24'd2, 8'd2, ACT_NONE, 8'h10);
        if ($signed(out_data_bus[0*OUT_W +: OUT_W]) !== 8'sd3) begin
            $display("  FAIL: expected 3, got %0d", $signed(out_data_bus[0*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: 5 * 2 >> 2 = 3 (HALF_UP verified)");
        end

        // TEST 3: Negative HALF_UP Rounding (-5 * 2 >> 2 = -2.5 -> -2)
        $display("\n[TEST 3] Negative HALF_UP Rounding (-2.5 -> -2)");
        drive_lane(0, -33'sd5, 24'd2, 8'd2, ACT_NONE, 8'h11);
        if ($signed(out_data_bus[0*OUT_W +: OUT_W]) !== -8'sd2) begin
            $display("  FAIL: expected -2, got %0d", $signed(out_data_bus[0*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: -5 * 2 >> 2 = -2 (HALF_UP negative verified)");
        end

        // TEST 4: Saturation High (+127) and Low (-128)
        $display("\n[TEST 4] INT8 Clamping / Saturation");
        drive_lane(1, 33'sd5000, 24'd1, 8'd0, ACT_NONE, 8'h12);
        if ($signed(out_data_bus[1*OUT_W +: OUT_W]) !== 8'sd127) begin
            $display("  FAIL: positive clamp expected +127, got %0d", $signed(out_data_bus[1*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: clamped +5000 to +127");
        end

        drive_lane(2, -33'sd5000, 24'd1, 8'd0, ACT_NONE, 8'h13);
        if ($signed(out_data_bus[2*OUT_W +: OUT_W]) !== -8'sd128) begin
            $display("  FAIL: negative clamp expected -128, got %0d", $signed(out_data_bus[2*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: clamped -5000 to -128");
        end

        // TEST 5: Activation (ReLU vs Passthrough)
        $display("\n[TEST 5] Activation Modes");
        drive_lane(3, -33'sd42, 24'd1, 8'd0, ACT_NONE, 8'h14);
        if ($signed(out_data_bus[3*OUT_W +: OUT_W]) !== -8'sd42) begin
            $display("  FAIL: ACT_NONE expected -42, got %0d", $signed(out_data_bus[3*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: ACT_NONE passed negative value -42");
        end

        drive_lane(3, -33'sd42, 24'd1, 8'd0, ACT_RELU, 8'h15);
        if ($signed(out_data_bus[3*OUT_W +: OUT_W]) !== 8'sd0) begin
            $display("  FAIL: ACT_RELU expected 0, got %0d", $signed(out_data_bus[3*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: ACT_RELU clipped negative value to 0");
        end

        // TEST 6: Shift = 0 (Direct scaling without shift)
        $display("\n[TEST 6] Shift = 0 (Direct scaling without shift)");
        drive_lane(4, 33'sd25, 24'd3, 8'd0, ACT_NONE, 8'h16);
        if ($signed(out_data_bus[4*OUT_W +: OUT_W]) !== 8'sd75) begin
            $display("  FAIL: expected 75, got %0d", $signed(out_data_bus[4*OUT_W +: OUT_W]));
            errors++;
        end else begin
            $display("  PASS: 25 * 3 = 75 (shift=0 verified)");
        end

        // TEST 7: Extreme Shifts (56, 57, 58, 60)
        $display("\n[TEST 7] Extreme Shifts Boundary Conditions");
        for (int sh = 56; sh <= 60; sh++) begin
            drive_lane(0, -33'sd1000000, 24'd1, sh[7:0], ACT_NONE, 8'h20);
            if ($signed(out_data_bus[0*OUT_W +: OUT_W]) !== 8'sd0) begin
                $display("  FAIL: shift %0d negative expected 0, got %0d", sh, $signed(out_data_bus[0*OUT_W +: OUT_W]));
                errors++;
            end

            drive_lane(0, 33'sd1000000, 24'd1, sh[7:0], ACT_NONE, 8'h21);
            if ($signed(out_data_bus[0*OUT_W +: OUT_W]) !== 8'sd0) begin
                $display("  FAIL: shift %0d positive expected 0, got %0d", sh, $signed(out_data_bus[0*OUT_W +: OUT_W]));
                errors++;
            end
        end
        $display("  PASS: Extreme shifts 56..60 all gracefully round to 0.");

        // TEST 8: Full 8-Lane Parallel Operation with Independent Configurations & Clamping
        $display("\n[TEST 8] 8-Lane Heterogeneous Parallel Operation");
        enable = 1;
        in_valid = 1;
        in_acc_addr = 8'hFE;
        act_mode = ACT_NONE;
        in_acc_bus = '0;
        scale_bus  = '0;
        shift_bus  = '0;

        for (int l = 0; l < ARRAY_N; l++) begin
            in_acc_bus[l*ACC_BUFF +: ACC_BUFF] = (l + 1) * 10;
            scale_bus[l*SCALE_W +: SCALE_W]    = (l + 1);
            shift_bus[l*SHIFT_W +: SHIFT_W]    = 8'd1;
        end
        #1;
        for (int l = 0; l < ARRAY_N; l++) begin
            p_val = (l + 1) * 10 * (l + 1);
            expected_val = (p_val + 1) >> 1;
            // Clamp to INT8 range
            if (expected_val > 127) expected_val = 127;
            if (expected_val < -128) expected_val = -128;

            actual_val = $signed(out_data_bus[l*OUT_W +: OUT_W]);
            if (actual_val !== expected_val) begin
                $display("  FAIL Lane %0d: expected %0d, got %0d", l, expected_val, actual_val);
                errors++;
            end
        end
        if (out_valid !== 1'b1 || out_acc_addr !== 8'hFE) begin
            $display("  FAIL: Control metadata propagation mismatch!");
            errors++;
        end else begin
            $display("  PASS: All 8 independent lanes computed and drained simultaneously!");
        end

        // Final Summary
        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL DIRECTED REQUANT TESTS PASSED! (0 ERRORS)");
        end else begin
            $display("TEST FAILED WITH %0d ERROR(S)", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
