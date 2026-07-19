`timescale 1ns/1ps

import edgeasic_config_pkg::*;

module tb_systolic_array_8x8;

    logic clk;
    logic rst_n;
    logic enable;
    logic [ARRAY_N-1:0] wgt_load;
    logic signed [ARRAY_N*ACT_W-1:0] act_in_bus;
    logic signed [ARRAY_N*WGT_W-1:0] wgt_in_bus;
    logic signed [ARRAY_N*ACC_W-1:0] psum_in_bus;
    logic signed [ARRAY_N*ACC_W-1:0] psum_out_bus;
    logic signed [ARRAY_N*ACT_W-1:0] act_out_bus;

    int errors;

    systolic_array_8x8 dut(

    .clk(clk),
    .rst_n(rst_n),
    .enable(enable),
    .wgt_load(wgt_load),
    .act_in_bus(act_in_bus),
    .wgt_in_bus(wgt_in_bus),
    .psum_in_bus(psum_in_bus),
    .psum_out_bus(psum_out_bus),
    .act_out_bus(act_out_bus)

    );

always #5 clk = ~clk;

   task reset_dut;
   begin
    @(negedge clk);

    rst_n = 1'b0;
    enable = 1'b0;
    wgt_load = '0;
    act_in_bus ='0;
    wgt_in_bus = '0;
    psum_in_bus = '0;

    repeat(2) @(posedge clk);


    @(negedge clk);
     rst_n = 1'b1;

     @(posedge clk);
     #1;

    $display("Reset complete");

   end
   endtask

   task automatic load_weight_row;
   input int row_idx;
   input logic signed [ARRAY_N*WGT_W-1:0] row_weights;

   begin
    @(negedge clk);

    wgt_in_bus = row_weights;
    wgt_load = '0;
    wgt_load[row_idx] = 1'b1;

    enable = 1'b0;

    @(posedge clk);
    #1;

    $display("Loaded weight row %0d", row_idx);

    @(negedge clk);
    wgt_load = '0;

    end
endtask

task automatic apply_activation_vector;

input int sign_val;
input int psum_seed;
    begin
        psum_in_bus = '0;
        act_in_bus = '0;

        for (int row=0;row<ARRAY_N;row=row+1)
        begin
            act_in_bus[row * ACT_W +: ACT_W] = sign_val*(row +1);
        end

        $display("APPLIED activation vector with sign = %0d", sign_val);

        for (int col=0;col<ARRAY_N;col=col+1)
        begin
            psum_in_bus[col*ACC_W+:ACC_W] = psum_seed;
        end

    end
endtask

task automatic run_compute_cycles;
input int num_cycles;
begin
    @(negedge clk);
    enable = 1'b1;

    repeat(num_cycles)
    begin
        @(posedge clk);

    end
    #1;

    @(negedge clk);
    enable = 1'b0;
    $display("Ran compute for %0d cycles",num_cycles);

end
endtask

task automatic check_all_outputs_equal;
input logic signed [ACC_W-1:0] expected_value;

begin
    for (int col=0; col<ARRAY_N;col=col+1) begin
        if ($signed(psum_out_bus[col*ACC_W +: ACC_W]) !== expected_value) begin
            $display("FAIL: col %0d expected %0d got %0d",
                         col,
                         expected_value,
                         $signed(psum_out_bus[col*ACC_W +: ACC_W]));
                errors++;
        end
     else begin
        $display("PASS :col %0d output = %0d",col,expected_value);
    end
    end


end
endtask

task automatic check_act_out_row;
input int row_idx;
input logic signed [ACT_W-1:0] expected_value;
begin
    if ($signed(act_out_bus[row_idx*ACT_W +: ACT_W]) !== expected_value) begin
        $display("FAIL: act_out row %0d expected %0d got %0d",
                 row_idx,
                 expected_value,
                 $signed(act_out_bus[row_idx*ACT_W +: ACT_W]));
        errors++;
    end else begin
        $display("PASS : act_out row %0d output = %0d", row_idx, expected_value);
    end
end
endtask




initial begin

    $dumpfile("sim/systolic_array_8x8.vcd");
    $dumpvars(0,tb_systolic_array_8x8);

    clk = 1'b0;
    rst_n = 1'b0;
    enable = 1'b0;
    wgt_load ='0;
    act_in_bus = '0;
    wgt_in_bus = '0;
    psum_in_bus = '0;
    errors = 0;

    #20;

    rst_n = 1'b1;

    #10;

    reset_dut();

    // ==========================================
    // TEST 1: Positive Weights (+2) & Positive Activations (+1..+8)
    // ==========================================
    $display("\n--- TEST 1: Positive Weights & Positive Activations ---");
    for (int row=0; row<ARRAY_N; row=row+1) begin
        load_weight_row(row, {ARRAY_N{8'sd2}});
    end
    apply_activation_vector(1,0); // feeds 1, 2, ..., 8
    run_compute_cycles(20);
    check_all_outputs_equal(32'sd72); // 36 * 2 = 72

    reset_dut();
    // ==========================================
    // TEST 2: Negative Weights (-2) & Positive Activations (+1..+8)
    // ==========================================
    $display("\n--- TEST 2: Negative Weights & Positive Activations ---");
    for (int row=0; row<ARRAY_N; row=row+1) begin
        load_weight_row(row, {ARRAY_N{-8'sd2}});
    end
    apply_activation_vector(1,0); // feeds -1, -2, ..., -8
    run_compute_cycles(20);
    check_all_outputs_equal(-32'sd72); // 36 * -2 = -72

    reset_dut();
    // ==========================================
    // TEST 3: Positive Weights (+2) & Negative Activations (-1..-8)
    // ==========================================
    $display("\n--- TEST 3: Positive Weights & Negative Activations ---");
    for (int row=0; row<ARRAY_N; row=row+1) begin
        load_weight_row(row, {ARRAY_N{8'sd2}});
    end
    apply_activation_vector(-1,0); // feeds -1, -2, ..., -8
    run_compute_cycles(20);
    check_all_outputs_equal(-32'sd72); // -36 * 2 = -72

    reset_dut();
    // ==========================================
    // TEST 4: Negative Weights (-2) & Negative Activations (-1..-8)
    // ==========================================
    $display("\n--- TEST 4: Negative Weights & Negative Activations ---");
    for (int row=0; row<ARRAY_N; row=row+1) begin
        load_weight_row(row, {ARRAY_N{-8'sd2}});
    end
    apply_activation_vector(-1,0); // feeds -1, -2, ..., -8
    run_compute_cycles(20);
    check_all_outputs_equal(32'sd72); // -36 * -2 = 72

    reset_dut();

    // ==========================================
    // TEST 5: DIFFERENT WEIGHT AND ACTIVATION
    // ==========================================
    $display("\n--- TEST 5: DIFFERENT WEIGHTS AND ACTIVATION");
    for(int row=0;row<ARRAY_N;row=row+1) begin
        logic signed  [WGT_W-1:0] row_we;
        row_we=row+1;
        load_weight_row(row, {ARRAY_N{row_we}});
    end
    apply_activation_vector(1,0);
    run_compute_cycles(20);
    check_all_outputs_equal(32'sd204);

    reset_dut();

    // ==========================================
    // TEST 6: psum added
    // ==========================================
    $display("\n--- TEST 6:PSUM ADDED ---");
    for(int row=0;row<ARRAY_N;row=row+1) begin
        logic signed  [WGT_W-1:0] row_we;
        row_we=row+1;
        load_weight_row(row, {ARRAY_N{row_we}});
    end
    apply_activation_vector(1,100);
    run_compute_cycles(20);
    check_all_outputs_equal(32'sd304);

    // ==========================================
    // TEST 7: Registered act_out Propagation
    // ==========================================
    $display("\n--- TEST 7: Registered act_out Propagation ---");
    reset_dut();

    // Clear inputs and set row 0 to 5
    act_in_bus = '0;
    psum_in_bus = '0;
    act_in_bus[0*ACT_W +: ACT_W] = 8'sd5;

    // Immediate check: Output should not be 5 yet (proving registered delay)
    $display("Immediate check (0 enabled cycles):");
    check_act_out_row(0, 8'sd0);

    // Propagate activation through the 8 stages
    run_compute_cycles(8);

    // Final checks
    $display("After 8 enabled cycles check:");
    check_act_out_row(0, 8'sd5); // Row 0 should be 5

    // Rows 1 to 7 should remain 0
    for (int r = 1; r < ARRAY_N; r = r + 1) begin
        check_act_out_row(r, 8'sd0);
    end

    reset_dut();

    // ==========================================
    // TEST 8: wgt_in_bus corruption check
    // ==========================================
    $display("\n--- TEST 8:  wgt_in_bus corruption check ---");


        for (int row=0; row<ARRAY_N; row=row+1) begin
        logic signed  [WGT_W-1:0] row_we;
        row_we=row+1;
        load_weight_row(row, {ARRAY_N{row_we}});
    end
    wgt_in_bus = {ARRAY_N{-8'sd7}};
    wgt_load = '0;

    apply_activation_vector(1,0);
    run_compute_cycles(20);
    check_all_outputs_equal(32'sd204);



    #50;


    if (errors == 0) begin
        $display("====================================");
        $display("ALL 8x8 SYSTOLIC ARRAY TESTS PASSED");
        $display("====================================");
    end else begin
        $display("====================================");
        $display("TESTS FAILED: %0d errors", errors);
        $display("====================================");
    end

    $finish;



end
endmodule
