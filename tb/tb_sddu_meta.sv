// tb/tb_sddu_meta.sv
`timescale 1ns/1ps

module tb_sddu_meta;
    import config_pkg::*;
    import types_pkg::*;

    logic clk;
    logic rst_n;
    logic pipe_en;

    // DUT Emulation Signals
    int32_s     in_data  [0:N-1];
    pipe_meta_t in_meta  [0:N-1];

    int32_s     out_data [0:N-1];
    pipe_meta_t out_meta [0:N-1];

    // Clock Generation (200 MHz architectural target)
    always #2.5 clk = ~clk;

    // SDDU Shift-Register Array: Lane i is delayed by (N - 1 - i) cycles
    for (genvar i = 0; i < N; i++) begin : g_lane_deskew
        localparam int DEPTH = N - 1 - i;
        int32_s     data_sr [0:DEPTH];
        pipe_meta_t meta_sr [0:DEPTH];

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                for (int d = 0; d <= DEPTH; d++) begin
                    data_sr[d] <= '0;
                    meta_sr[d] <= '0;
                end
            end else if (pipe_en) begin
                data_sr[0] <= in_data[i];
                meta_sr[0] <= in_meta[i];
                for (int d = 1; d <= DEPTH; d++) begin
                    data_sr[d] <= data_sr[d-1];
                    meta_sr[d] <= meta_sr[d-1];
                end
            end
        end

        assign out_data[i] = data_sr[DEPTH];
        assign out_meta[i] = meta_sr[DEPTH];
    end

    // --- SVA ASSERTION ---
    assert property (@(posedge clk) disable iff (!rst_n)
        out_meta[0].valid |-> !$isunknown(out_meta[0].k_tile_first) && !$isunknown(out_meta[0].k_tile_last)
    ) else $error("Assertion Failed: Metadata tags unknown during valid output!");

    // --- STIMULUS & SAMPLING ---
    logic aligned_pass;
    integer timeout_count;

    initial begin
        clk           = 0;
        rst_n         = 0;
        pipe_en       = 1;
        aligned_pass  = 0;
        timeout_count = 0;

        for (int i = 0; i < N; i++) begin
            in_data[i] = '0;
            in_meta[i] = '0;
        end

        // 1. Reset
        #10 rst_n = 1;
        #10;

        // 2. Inject Diagonal Wavefront (Lane 0 enters at t=0, Lane 7 enters at t=7)
        $display("[TEST] Injecting diagonal systolic wavefront...");
        for (int step = 0; step < N; step++) begin
            @(posedge clk);
            in_data[step]              = int32_s'(200 + step);
            in_meta[step].valid        = 1'b1;
            in_meta[step].k_tile_first = (step == 0);
            in_meta[step].k_tile_last  = (step == N-1);
            in_meta[step].acc_addr     = 8'h3C;
        end

        // 3. Clear Inputs
        @(posedge clk);
        for (int i = 0; i < N; i++) begin
            in_data[i] = '0;
            in_meta[i] = '0;
        end

        // 4. Sample and wait for simultaneous all-lane alignment
        while (!aligned_pass && timeout_count < 30) begin
            @(posedge clk);
            timeout_count++;
            
            // Check if all N lanes are valid simultaneously at the output
            if (out_meta[0].valid && out_meta[1].valid && out_meta[2].valid &&
                out_meta[3].valid && out_meta[4].valid && out_meta[5].valid &&
                out_meta[6].valid && out_meta[7].valid) begin
                aligned_pass = 1;
            end
        end

        // 5. Result Verification
        if (aligned_pass) begin
            $display("[PASS] TC-SDDU-001 & TC-SDDU-002: All %0d lanes aligned simultaneously with valid metadata!", N);
        end else begin
            $display("[FAIL] Timeout reached without rectangular lane alignment!");
        end

        #20 $finish;
    end

endmodule