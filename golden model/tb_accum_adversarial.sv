`timescale 1ns/1ps
import config_pkg::*;
import types_pkg::*;

module tb_accum_adversarial;
    logic clk=0, rst_n, enable, in_valid, in_k_tile_first, in_k_tile_last;
    logic signed [ARRAY_N*ACC_W-1:0]  in_psum_bus;
    logic signed [ARRAY_N*BIAS_W-1:0] bias_in_bus;
    logic [ACC_ADDR_W-1:0] in_acc_addr;
    logic signed [ACC_BUFF*ARRAY_N-1:0] buf_read_data, buf_write_data;
    logic buf_read_en, buf_write_en;
    logic [ACC_ADDR_W-1:0] buf_read_addr, buf_write_addr;
    logic out_valid, out_k_tile_first, out_k_tile_last;
    logic [ACC_ADDR_W-1:0] out_acc_addr;
    logic signed [ARRAY_N*ACC_BUFF-1:0] out_acc_bus;
    int errors = 0;

    accum_engine dut(.*);
    accum_buffer ab(.clk(clk), .read_enable(buf_read_en), .read_address(buf_read_addr),
                    .read_data(buf_read_data), .write_enable(buf_write_en),
                    .write_address(buf_write_addr), .write_data(buf_write_data));
    always #5 clk = ~clk;

    task do_reset(); begin
        @(negedge clk); rst_n=0; enable=0; in_valid=0; in_psum_bus='0; bias_in_bus='0;
        in_k_tile_first=0; in_k_tile_last=0; in_acc_addr='0;
        repeat(2) @(posedge clk); @(negedge clk); rst_n=1; #1;
    end endtask

    // drive one beat with per-lane distinct values
    task beat(input logic v, f, l, input [ACC_ADDR_W-1:0] a,
              input int psum_base, input int bias_base, input logic en); begin
        @(negedge clk);
        enable=en; in_valid=v; in_k_tile_first=f; in_k_tile_last=l; in_acc_addr=a;
        for (int i=0;i<ARRAY_N;i++) begin
            in_psum_bus[i*ACC_W +: ACC_W]   = psum_base + i;   // distinct per lane
            bias_in_bus[i*BIAS_W +: BIAS_W] = bias_base + i*10;
        end
        #1;
    end endtask

    task check_lane(input int lane, input longint exp, input string tag); begin
        if ($signed(out_acc_bus[lane*ACC_BUFF +: ACC_BUFF]) !== exp) begin
            $error("%s lane %0d: expected %0d got %0d", tag, lane, exp,
                   $signed(out_acc_bus[lane*ACC_BUFF +: ACC_BUFF])); errors++;
        end
    end endtask

    initial begin
        // ============ A: STALL IN THE MIDDLE OF A RAW CHAIN ============
        $display("\n--- A: enable=0 stall between back-to-back same-address sub-tiles ---");
        do_reset();
        beat(1,1,0,8'h05, 100, 1000, 1);   // first: bias(1000+10i) + psum(100+i)
        beat(1,0,0,8'h05, 200, 0, 1);      // second, back-to-back same addr
        beat(0,0,0,8'h05, 0, 0, 1'b0);     // STALL: enable=0
        beat(0,0,0,8'h05, 0, 0, 1'b0);     // STALL again
        beat(1,0,1,8'h05, 300, 0, 1);      // resume, last
        @(posedge clk); #1;
        if (out_valid !== 1'b1) begin $error("A: no out_valid after stall+resume"); errors++; end
        else for (int i=0;i<ARRAY_N;i++)
            check_lane(i, (1000+i*10) + (100+i) + (200+i) + (300+i), "A");
        $display("   A done (errors so far=%0d)", errors);

        // ============ B: SINGLE-CYCLE STALL EXACTLY ON THE BYPASS CYCLE ============
        $display("\n--- B: 1-cycle stall placed exactly on bypass-consuming cycle ---");
        do_reset();
        beat(1,1,0,8'h09, 50, 500, 1);
        beat(0,0,0,8'h09, 0, 0, 1'b0);     // stall right after first
        beat(1,0,1,8'h09, 60, 0, 1);
        @(posedge clk); #1;
        if (out_valid !== 1'b1) begin $error("B: no out_valid"); errors++; end
        else for (int i=0;i<ARRAY_N;i++)
            check_lane(i, (500+i*10) + (50+i) + (60+i), "B");
        $display("   B done (errors so far=%0d)", errors);

        // ============ C: 33-BIT OVERFLOW WITH LARGE K ============
        $display("\n--- C: accumulate many sub-tiles, near-max psum (ACC_BUFF=%0d) ---", ACC_BUFF);
        do_reset();
        begin
            longint golden;
            // bias = 0, psum = large positive each beat, 300 sub-tiles
            beat(1,1,0,8'h20, 32'sh1000_0000, 0, 1);
            golden = 32'sh1000_0000;
            for (int k=0;k<300;k++) begin
                beat(1,0,0,8'h20, 32'sh1000_0000, 0, 1);
                golden += 32'sh1000_0000;
            end
            beat(1,0,1,8'h20, 32'sh1000_0000, 0, 1);
            golden += 32'sh1000_0000;
            @(posedge clk); #1;
            $display("   lane0 golden(untruncated) = %0d", golden);
            $display("   lane0 hardware            = %0d",
                     $signed(out_acc_bus[0*ACC_BUFF +: ACC_BUFF]));
            if ($signed(out_acc_bus[0*ACC_BUFF +: ACC_BUFF]) !== golden)
                $display("   >>> OVERFLOW CONFIRMED: silent wrap, no saturation, no flag");
        end

        $display("\n============================================");
        if (errors==0) $display("ADVERSARIAL A+B PASSED (%0d errors)", errors);
        else           $display("ADVERSARIAL FAILURES: %0d", errors);
        $display("============================================\n");
        $finish;
    end
endmodule
