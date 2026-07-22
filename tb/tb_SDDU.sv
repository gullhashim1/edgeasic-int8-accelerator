`timescale 1ns/1ps

import config_pkg::*;
import types_pkg::*;

module tb_SDDU;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic enable;
    logic signed [ARRAY_N*ACC_W-1:0] in_psum_bus;
    logic in_k_tile_first;
    logic in_k_tile_last;
    int mark;

    logic out_valid;
    logic signed [ARRAY_N*ACC_W-1:0] out_psum_bus;
    logic out_k_tile_first;
    logic out_k_tile_last;

    logic [ACC_ADDR_W-1:0] in_acc_addr;
    logic [ACC_ADDR_W-1:0] out_acc_addr;

    int errors;
    int errors4;
    int errors5;
    int errors6;
    int errors7;

    logic signed out_k_tile_first_held;
    logic signed out_k_tile_last_held;
    logic signed out_valid_held;
    logic signed [ARRAY_N*ACC_W-1:0] out_psum_bus_held;

    sddu dut(
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .enable(enable),
        .in_psum_bus(in_psum_bus),
        .in_k_tile_first(in_k_tile_first),
        .in_k_tile_last(in_k_tile_last),
        .in_acc_addr(in_acc_addr),
        .out_valid(out_valid),
        .out_psum_bus(out_psum_bus),
        .out_k_tile_first(out_k_tile_first),
        .out_k_tile_last(out_k_tile_last),
        .out_acc_addr(out_acc_addr)
    );
    
    always #5 clk = ~clk;

    task reset_dut();
    begin 
        @(negedge clk);
        rst_n = 1'b0;
        enable = 1'b0;
        in_valid = 1'b0;
        in_psum_bus = '0;
        in_k_tile_first = 1'b0;
        in_k_tile_last = 1'b0;
        in_acc_addr = '0;


        repeat(2) @(posedge clk);

        @(negedge clk);
        rst_n=1'b1;

        @(posedge clk);
        #1;

        $display("RESET COMPLETE");
    end    
    endtask

    task deskew_pipeline(input int lane_idx,input logic signed [ACC_W-1:0] marker_value);

    @(negedge clk);
    in_psum_bus = '0;
    in_psum_bus[lane_idx*ACC_W+:ACC_W] = marker_value;
    in_valid = 1'b1;
    enable = 1'b1;
    in_k_tile_first = (lane_idx == 0);
    in_k_tile_last = (lane_idx == 0);

    @(posedge clk);
    #1;


    endtask


    initial begin
        errors4 = 0;
        errors = 0;
        $dumpfile("sim/SDDU.vcd");
        $dumpvars(0,tb_SDDU);

        clk = 1'b0;
        rst_n = 1'b0;
        enable = 1'b0;
        in_valid = 1'b0;
        in_psum_bus = '0;
        in_k_tile_first = 1'b0;
        in_k_tile_last = 1'b0;

        #10;
        rst_n = 1'b1;
        #10;
        reset_dut();
        
        // ==========================================
        // TEST 1: CHECKING RESET
        // ==========================================
        $display("\n--- TEST 1: CHECKING RESET ---");
        @(negedge clk);
        in_valid = 1'b1;
        enable = 1'b1;
        in_psum_bus = 'd1;
        in_k_tile_first = 1'b1;
        in_k_tile_last = 1'b1;

        @(posedge clk);
        #1;

        reset_dut();
        @(negedge clk);
        #1;
        if (out_valid !== 1'b0) begin
            $error("RESET FAIL: out_valid = %b, expected 0", out_valid);
            errors++;
        end
        if (out_psum_bus !== '0) begin
            $error("RESET FAIL: out_psum_bus = %b, expected 0", out_psum_bus);
            errors++;
        end
        if (out_k_tile_first !== 1'b0) begin
            $error("RESET FAIL: out_k_tile_first = %b, expected 0", out_k_tile_first);
            errors++;
        end
        if (out_k_tile_last !== 1'b0) begin
            $error("RESET FAIL: out_k_tile_last = %b, expected 0", out_k_tile_last);
            errors++;
        end
        if (errors == 0)
            $display("RESET COMPLETE AND VERIFIED");
        else
            $display("RESET COMPLETE WITH %0d ERROR(S)", errors);
    
        
     // ==========================================
     // TEST 2: TESTING FOR DELAY
    // ==========================================
    $display("\n--- TEST 2: TESTING FOR DELAY ---"); 
    reset_dut();

    
    for(int i=0;i<ARRAY_N-1;i=i+1) begin

        mark =(i+1)*100;
        deskew_pipeline(i,mark);
    end

    @(negedge clk);

in_psum_bus = '0;
in_psum_bus[7*ACC_W +: ACC_W] = 800;

in_valid = 1'b1;
enable   = 1'b1;

#1;
    
    if(out_psum_bus[0*ACC_W +: ACC_W] !== 100)
        errors++;
    if(out_valid !== 1'b1 ) begin
        $display("out_valid = %b", out_valid);
        errors++; 
    end
    if(out_k_tile_first !== 1'b1 ) begin
        $display("out_k_tile_first = %b", out_k_tile_first);
        errors++;
    end
    if(out_k_tile_last !== 1'b1 ) begin
        $display("out_k_tile_last = %b", out_k_tile_last);
        errors++;
    end

    if(out_psum_bus[1*ACC_W +: ACC_W] !== 200)
        errors++;
    if(out_psum_bus[2*ACC_W +: ACC_W] !== 300)
        errors++;
   if(out_psum_bus[3*ACC_W +: ACC_W] !== 400)
        errors++;
   if(out_psum_bus[4*ACC_W +: ACC_W] !== 500)
        errors++;
   if(out_psum_bus[5*ACC_W +: ACC_W] !== 600)
        errors++;
   if(out_psum_bus[6*ACC_W +: ACC_W] !== 700)
        errors++;
   if(out_psum_bus[7*ACC_W +: ACC_W] !== 800)
        errors++;

    if(errors == 0)
        $display("TEST 2 PASSED");
    else
        $display("TEST 2 FAILED WITH %0d ERRORS", errors);


        

    // ==========================================
    // TEST 3: TESTING FOR OUT VALID
    // ==========================================
    $display("\n--- TEST 3: TESTING FOR OUT VALID ---"); 
    reset_dut();
        for(int i=0;i<ARRAY_N-1;i=i+1) begin
        mark =(i+1)*100;
        deskew_pipeline(i,mark);
        if(i < 6 && out_valid !== 1'b0) begin
            $display("TEST 3 FAIL: out_valid high too early at i=%0d", i);
            errors++;
        end
    end


    @(negedge clk);

in_psum_bus = '0;
in_psum_bus[7*ACC_W +: ACC_W] = 800;

in_valid = 1'b1;
enable   = 1'b1;
in_k_tile_first=1'b0;
in_k_tile_last =1'b0;

if(out_valid === 1'b1) begin
    $display("OUT VALID IS One");
    end
    else begin
    $display("OUT VALID IS ZERO");
    errors++;
    end

if(errors==0)
    $display("TEST 3 PASSED");
else
    $display("TEST 3 FAILED WITH %0d ERRORS", errors);

// ==========================================
// TEST 4: CONTINUOUS 8x8 WAVEFRONT
// ==========================================
$display("\n--- TEST 4: CONTINUOUS 8x8 WAVEFRONT ---");

reset_dut();
errors4 = 0;

// Outer loop represents raw systolic-array output clocks.
// For ARRAY_N=8, it runs for 15 clocks.
for (int t = 0; t < (2*ARRAY_N-1); t = t + 1) begin

    @(negedge clk);

    // Clear every lane before constructing this clock's wavefront.
    in_psum_bus = '0;
    enable = 1'b1;

    // A new output row begins on lane 0 for clocks 0 through 7.
    in_valid = (t < ARRAY_N);

    // This test represents one K tile that is both first and last.
    in_k_tile_first = (t < ARRAY_N);
    in_k_tile_last  = (t < ARRAY_N);

    // Examine every output row.
    for (int row = 0; row < ARRAY_N; row = row + 1) begin

        // Examine every output lane/column.
        for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin

            // Result [row][lane] appears at raw clock row+lane.
            if (t == (row+lane)) begin
                in_psum_bus[lane*ACC_W +: ACC_W] =
                    100 + (10*row) + (lane+1);
            end

        end
    end

    // Lane 7 has zero SDDU delay, so let it settle.
    #1;

    // No complete output row should exist before clock 7.
    if (t < (ARRAY_N-1)) begin

        if (out_valid !== 1'b0) begin
            $error(
                "TEST 4: out_valid asserted early at raw clock %0d",
                t
            );
            errors4++;
        end

    end else begin

        // From t=7 through t=14, one complete row is expected.
        if (out_valid !== 1'b1) begin
            $error(
                "TEST 4: out_valid=0 at raw clock %0d",
                t
            );
            errors4++;
        end

        // Check all eight lanes of the aligned output row.
        for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin

            if ($signed(out_psum_bus[lane*ACC_W +: ACC_W])
                !==
                (100
                 + (10*(t-(ARRAY_N-1)))
                 + (lane+1))) begin

                $error(
                    "TEST 4: output row %0d lane %0d: actual=%0d expected=%0d",
                    t-(ARRAY_N-1),
                    lane,
                    $signed(out_psum_bus[lane*ACC_W +: ACC_W]),
                    100
                    + (10*(t-(ARRAY_N-1)))
                    + (lane+1)
                );
                errors4++;
            end

        end

        // FIRST/LAST must accompany every valid output row.
        if (out_k_tile_first !== 1'b1) begin
            $error(
                "TEST 4: FIRST incorrect for output row %0d",
                t-(ARRAY_N-1)
            );
            errors4++;
        end

        if (out_k_tile_last !== 1'b1) begin
            $error(
                "TEST 4: LAST incorrect for output row %0d",
                t-(ARRAY_N-1)
            );
            errors4++;
        end

    end
end

// Advance the SDDU once more after the final output row.
@(posedge clk);
#1;

if (out_valid !== 1'b0) begin
    $error("TEST 4: out_valid remained high after the final row");
    errors4++;
end

if (out_k_tile_first !== 1'b0) begin
    $error("TEST 4: FIRST remained high after the final row");
    errors4++;
end

if (out_k_tile_last !== 1'b0) begin
    $error("TEST 4: LAST remained high after the final row");
    errors4++;
end

if (errors4 == 0)
    $display("TEST 4 PASSED");
else
    $display("TEST 4 FAILED WITH %0d ERROR(S)", errors4);

// ==========================================
// TEST 5: enable check
// ==========================================
$display("\n--- TEST 5: ENABLE CHECK ---");

reset_dut();
errors5 = 0;

for (int t=0;t<ARRAY_N;t=t+1) begin
    @(negedge clk);
    
    in_psum_bus = '0;
    enable = 1'b1;

    in_valid = 1'b1;
    in_k_tile_first = 1'b1;
    in_k_tile_last = 1'b1;

    for (int row = 0; row < ARRAY_N; row = row + 1) begin
        for (int lane =0; lane < ARRAY_N; lane = lane+1) begin

            if (t== row + lane) begin
                in_psum_bus[lane*ACC_W+: ACC_W] = 1000 + 10*row + (lane+1);
            end
        end
    end

#1;
    if(t<(ARRAY_N-1))begin
        if (out_valid !== 1'b0) begin
            $error("TEST 5: out_valid asserted early at t=%0d",t);
            errors5++;
        end
    end
end
if (out_valid !== 1'b1) begin
    $error("TEST 5: No valid output row before stall");
    errors5++;
end
    out_psum_bus_held = out_psum_bus;
    out_k_tile_first_held = out_k_tile_first;
    out_k_tile_last_held = out_k_tile_last;
    out_valid_held = out_valid;

    enable = 1'b0;

    repeat(3) begin
    @(posedge clk);
    #1;

    if(out_psum_bus!==out_psum_bus_held)begin
        errors5++;
        $display("out_psum_bus_held = %h",out_psum_bus_held);
        $display("out_psum_bus = %h",out_psum_bus);
    end

    if(out_k_tile_first!==out_k_tile_first_held)begin
        errors5++;
        $display("out_k_tile_first_held = %b",out_k_tile_first_held);
        $display("out_k_tile_first = %b",out_k_tile_first);
    end

    if(out_k_tile_last!==out_k_tile_last_held)begin
        errors5++;
        $display("out_k_tile_last_held = %b",out_k_tile_last_held);
        $display("out_k_tile_last = %b",out_k_tile_last);
    end
    
    if(out_valid!==out_valid_held)begin
        errors5++;
        $display("out_valid_held = %b",out_valid_held);
        $display("out_valid = %b",out_valid);
    end
    end  

    @(negedge clk);
    enable=1'b1;

    @(posedge clk);
    #1;
    
for (int t=ARRAY_N;t<2*ARRAY_N-1;t=t+1) begin
    @(negedge clk);

    in_psum_bus = '0;
    in_valid = 1'b0;
    in_k_tile_first = 1'b0;
    in_k_tile_last = 1'b0;
    enable = 1'b1;

    for (int row = 0; row < ARRAY_N; row = row + 1) begin
        for (int lane =0; lane < ARRAY_N; lane = lane+1) begin

            if (t== row + lane) begin
                in_psum_bus[lane*ACC_W+: ACC_W] = 1000 + 10*row + (lane+1);
            end
        end
    end

#1;

    if (out_valid !== 1'b1) begin
    $error("TEST 5: No valid output row after resume");
    errors5++;
end   

    for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
        if ($signed(out_psum_bus[lane*ACC_W +: ACC_W]) !== (1000 + 10*(t-(ARRAY_N-1)) + (lane+1))) begin

            $error("TEST 5: Resume row %0d lane %0d actual=%0d expected=%0d",
                t-(ARRAY_N-1),lane,$signed(out_psum_bus[lane*ACC_W +: ACC_W]),1000 + 10*(t-(ARRAY_N-1)) + (lane+1));
            errors5++;
        end
    end

    if (out_k_tile_first !== 1'b1) begin
        $error(
            "TEST 5: FIRST incorrect after resume on row %0d",
            t-(ARRAY_N-1)
        );
        errors5++;
    end

    if (out_k_tile_last !== 1'b1) begin
        $error(
            "TEST 5: LAST incorrect after resume on row %0d",
            t-(ARRAY_N-1)
        );
        errors5++;
    end
end

// Flush the final valid token.
@(posedge clk);
#1;

if (out_valid !== 1'b0) begin
    $error("TEST 5: out_valid remained high after final row");
    errors5++;
end

if (errors5 == 0)
    $display("TEST 5 PASSED");
else
    $display("TEST 5 FAILED WITH %0d ERROR(S)", errors5);

// ==========================================
// TEST 6: VALID BUBBLE MASKING & RECOVERY
// ==========================================
$display("\n--- TEST 6: VALID BUBBLE MASKING & RECOVERY ---");
reset_dut();
errors6 = 0;
begin
    int bubble_t;
    int out_row;
    int expected_val;

    // Run continuous 15-cycle stream (t = 0 to 14)
    for (int t = 0; t < (2*ARRAY_N-1); t = t + 1) begin
        @(negedge clk);

        in_psum_bus = '0;
        enable = 1'b1;

        // Inject valid data for cycles 0 to 7, BUT inject a bubble at cycle t = 3
        if (t < ARRAY_N && t != 3) begin
            in_valid = 1'b1;
        end else begin
            in_valid = 1'b0; // Bubble at t = 3!
        end

        in_k_tile_first = in_valid;
        in_k_tile_last  = in_valid;

        // Generate input data for the lanes
        for (int row = 0; row < ARRAY_N; row = row + 1) begin
            for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                if (t == (row + lane)) begin
                    in_psum_bus[lane*ACC_W +: ACC_W] = 100 + (10*row) + (lane+1);
                end
            end
        end

        #1; // Allow combinational outputs to settle

        // --- CHECKER ---
        if (t < (ARRAY_N-1)) begin
            // 1. Early out_valid check (t = 0 to 6)
            if (out_valid !== 1'b0) begin
                $error("TEST 6 FAIL: Early out_valid assertion at t=%0d", t);
                errors6++;
            end
        end else begin
            // Output wavefronts emerge from t = 7 to 14
            bubble_t = 3 + (ARRAY_N - 1); // Bubble injected at t=3 emerges at t=10

            if (t == bubble_t) begin
                // 2. Bubble Cycle check (t = 10): valid and metadata must be 0
                if (out_valid !== 1'b0) begin
                    $error("TEST 6 FAIL: Expected bubble (out_valid=0) at t=%0d", t);
                    errors6++;
                end
                if (out_k_tile_first !== 1'b0 || out_k_tile_last !== 1'b0) begin
                    $error("TEST 6 FAIL: Metadata not zero during bubble at t=%0d", t);
                    errors6++;
                end
            end else begin
                // 3. Valid Output Cycles: check valid, metadata, and data recovery
                if (out_valid !== 1'b1) begin
                    $error("TEST 6 FAIL: Expected out_valid=1 at t=%0d", t);
                    errors6++;
                end
                if (out_k_tile_first !== 1'b1 || out_k_tile_last !== 1'b1) begin
                    $error("TEST 6 FAIL: Metadata missing on valid row at t=%0d", t);
                    errors6++;
                end

                // Check data on all 8 lanes for row r = t - 7
                out_row = t - (ARRAY_N - 1);
                for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                    expected_val = 100 + (10*out_row) + (lane + 1);
                    if ($signed(out_psum_bus[lane*ACC_W +: ACC_W]) !== expected_val) begin
                        $error("TEST 6 FAIL: Data mismatch at t=%0d lane %0d. Expected %0d, Got %0d",
                            t, lane, expected_val, $signed(out_psum_bus[lane*ACC_W +: ACC_W]));
                        errors6++;
                    end
                end
            end
        end
    end
end

// 4. Final de-assertion drain check
@(posedge clk);
#1;

if (out_valid !== 1'b0) begin
    $error("TEST 6 FAIL: out_valid remained high after final row");
    errors6++;
end

if (errors6 == 0)
    $display("TEST 6 PASSED: Valid Bubble Masked & Data/Metadata Recovered Successfully!");
else
    $display("TEST 6 FAILED WITH %0d ERROR(S)", errors6);

// ==========================================
// TEST 7: INDEPENDENT FIRST/LAST METADATA ALIGNMENT
// ==========================================
$display("\n--- TEST 7: INDEPENDENT FIRST/LAST METADATA ALIGNMENT ---");
reset_dut();
errors7 = 0;

begin
    int out_row;
    logic expected_first;
    logic expected_last;
    int expected_val;

    // Run continuous 15-cycle stream (t = 0 to 14)
    for (int t = 0; t < (2*ARRAY_N-1); t = t + 1) begin
        @(negedge clk);

        in_psum_bus = '0;
        enable = 1'b1;

        if (t < ARRAY_N) begin
            in_valid = 1'b1;
            // Drive asymmetric FIRST and LAST signals for every row
            case (t)
                0: begin in_k_tile_first = 1'b1; in_k_tile_last = 1'b0; end // FIRST=1, LAST=0
                1: begin in_k_tile_first = 1'b0; in_k_tile_last = 1'b0; end // FIRST=0, LAST=0
                2: begin in_k_tile_first = 1'b0; in_k_tile_last = 1'b1; end // FIRST=0, LAST=1
                3: begin in_k_tile_first = 1'b1; in_k_tile_last = 1'b1; end // FIRST=1, LAST=1
                4: begin in_k_tile_first = 1'b1; in_k_tile_last = 1'b0; end // FIRST=1, LAST=0
                5: begin in_k_tile_first = 1'b0; in_k_tile_last = 1'b0; end // FIRST=0, LAST=0
                6: begin in_k_tile_first = 1'b0; in_k_tile_last = 1'b1; end // FIRST=0, LAST=1
                7: begin in_k_tile_first = 1'b1; in_k_tile_last = 1'b1; end // FIRST=1, LAST=1
                default: begin in_k_tile_first = 1'b0; in_k_tile_last = 1'b0; end
            endcase
        end else begin
            in_valid        = 1'b0;
            in_k_tile_first = 1'b0;
            in_k_tile_last  = 1'b0;
        end

        // Generate input data for the lanes
        for (int row = 0; row < ARRAY_N; row = row + 1) begin
            for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                if (t == (row + lane)) begin
                    in_psum_bus[lane*ACC_W +: ACC_W] = 100 + (10*row) + (lane+1);
                end
            end
        end

        #1; // Allow combinational outputs to settle

        // --- CHECKER ---
        if (t < (ARRAY_N-1)) begin
            // Early out_valid check (t = 0 to 6)
            if (out_valid !== 1'b0) begin
                $error("TEST 7 FAIL: Early out_valid assertion at t=%0d", t);
                errors7++;
            end
        end else begin
            // Check valid output rows (t = 7 to 14)
            if (out_valid !== 1'b1) begin
                $error("TEST 7 FAIL: Expected out_valid=1 at t=%0d", t);
                errors7++;
            end

            out_row = t - (ARRAY_N - 1);

            // Calculate expected asymmetric FIRST / LAST for row `out_row`
            case (out_row)
                0: begin expected_first = 1'b1; expected_last = 1'b0; end
                1: begin expected_first = 1'b0; expected_last = 1'b0; end
                2: begin expected_first = 1'b0; expected_last = 1'b1; end
                3: begin expected_first = 1'b1; expected_last = 1'b1; end
                4: begin expected_first = 1'b1; expected_last = 1'b0; end
                5: begin expected_first = 1'b0; expected_last = 1'b0; end
                6: begin expected_first = 1'b0; expected_last = 1'b1; end
                7: begin expected_first = 1'b1; expected_last = 1'b1; end
                default: begin expected_first = 1'b0; expected_last = 1'b0; end
            endcase

            if (out_k_tile_first !== expected_first) begin
                $error("TEST 7 FAIL: FIRST metadata mismatch at t=%0d (row %0d). Expected %b, Got %b",
                    t, out_row, expected_first, out_k_tile_first);
                errors7++;
            end

            if (out_k_tile_last !== expected_last) begin
                $error("TEST 7 FAIL: LAST metadata mismatch at t=%0d (row %0d). Expected %b, Got %b",
                    t, out_row, expected_last, out_k_tile_last);
                errors7++;
            end

            // Check data on all 8 lanes for row `out_row`
            for (int lane = 0; lane < ARRAY_N; lane = lane + 1) begin
                expected_val = 100 + (10*out_row) + (lane + 1);
                if ($signed(out_psum_bus[lane*ACC_W +: ACC_W]) !== expected_val) begin
                    $error("TEST 7 FAIL: Data mismatch at t=%0d lane %0d. Expected %0d, Got %0d",
                        t, lane, expected_val, $signed(out_psum_bus[lane*ACC_W +: ACC_W]));
                    errors7++;
                end
            end
        end
    end
end

// Final de-assertion drain check
@(posedge clk);
#1;

if (out_valid !== 1'b0) begin
    $error("TEST 7 FAIL: out_valid remained high after final row");
    errors7++;
end

if (errors7 == 0)
    $display("TEST 7 PASSED: Independent FIRST/LAST Metadata Alignment Verified!");
else
    $display("TEST 7 FAILED WITH %0d ERROR(S)", errors7);

$finish;
end
endmodule
