`timescale 1ns/1ps



module tb_pe_mac;

    import edgeasic_config_pkg::*;
    
    logic clk;
    logic rst_n;
    
    logic enable;
    logic clear_acc;
    logic wgt_load;

    logic signed [ACT_W-1:0] act_in;
    logic signed [WGT_W-1:0] wgt_in;
    logic signed [ACC_W-1:0] psum_in;

    logic signed [ACT_W-1:0] act_out;
    logic signed [ACC_W-1:0] psum_out;
    
    int errors;
    pe_mac dut(

        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .clear_acc(clear_acc),
        .wgt_load(wgt_load),
        .act_in(act_in),
        .wgt_in(wgt_in),
        .psum_in(psum_in),
        .act_out(act_out),
        .psum_out(psum_out)

    );

    always #5 clk = ~clk;
    task automatic load_weight;
    input logic signed [WGT_W-1:0] weight_value;
    begin
        @(negedge clk)
        wgt_in = weight_value;
        wgt_load = 1'b1;
        enable = 1'b0;
        clear_acc = 1'b0;

        @(posedge clk)
        #1;

        @(negedge clk)
        wgt_load = 1'b0;
    end
    endtask 

    task automatic run_mac_check;
    input logic signed [ACT_W-1:0] act_value;
    input logic signed [ACC_W-1:0] psum_value;
    input logic clear_value;
    input logic signed [ACC_W-1:0] expected_value;
    input string test_name;
    begin
        @(negedge clk);
        act_in = act_value;
        psum_in = psum_value;
        clear_acc = clear_value;
        enable = 1'b1;
        wgt_load = 1'b0;
        
        @(posedge clk);
        #1;

        if (psum_out !== expected_value) begin
            $display("FAIL : %s expected=%0d got=%0d", test_name, expected_value, psum_out);
            errors++;
        end else begin
            $display("PASS : %s result=%0d", test_name, psum_out);
        end

        if (act_out!== act_value) begin
            $display("FAIL: %s act_out expected=%0d got=%0d", test_name, act_value, act_out);
                errors++;
            end else begin
                $display("PASS: %s act_out registered correctly", test_name);
            end

            @(negedge clk);
            enable    = 1'b0;
            clear_acc = 1'b0;
        end
    endtask
      initial begin
        $dumpfile("sim/pe_mac.vcd");
        $dumpvars(0, tb_pe_mac);

        clk       = 1'b0;
        rst_n     = 1'b0;
        enable    = 1'b0;
        clear_acc = 1'b0;
        wgt_load  = 1'b0;
        act_in    = '0;
        wgt_in    = '0;
        psum_in   = '0;
        errors    = 0;

        #20;
        rst_n = 1'b1;

        #10;

        if (act_out !== '0 || psum_out !== '0) begin
            $display("FAIL: reset outputs not zero");
            errors++;
        end else begin
            $display("PASS: reset outputs zero");
        end

        load_weight(8'sd4);
        run_mac_check(8'sd3, 32'sd0, 1'b1, 32'sd12, "3 * 4");

        load_weight(8'sd4);
        run_mac_check(-8'sd3, 32'sd0, 1'b1, -32'sd12, "-3 * 4");

        load_weight(-8'sd4);
        run_mac_check(-8'sd3, 32'sd0, 1'b1, 32'sd12, "-3 * -4");

        load_weight(8'sd127);
        run_mac_check(8'sd127, 32'sd0, 1'b1, 32'sd16129, "127 * 127");

        load_weight(8'sd127);
        run_mac_check(-8'sd128, 32'sd0, 1'b1, -32'sd16256, "-128 * 127");

        load_weight(8'sd6);
        run_mac_check(8'sd5, 32'sd100, 1'b0, 32'sd130, "100 + 5 * 6");

        load_weight(8'sd7);

        @(negedge clk);
        wgt_in    = 8'sd99;
        act_in    = 8'sd2;
        psum_in   = 32'sd0;
        clear_acc = 1'b1;
        enable    = 1'b1;
        wgt_load  = 1'b0;

        @(posedge clk);
        #1;

        if (psum_out !== 32'sd14) begin
            $display("FAIL: weight-stationary test expected=14 got=%0d", psum_out);
            errors++;
        end else begin
            $display("PASS: weight-stationary test used stored weight, not new wgt_in");
        end

        @(negedge clk);
        enable = 1'b0;

        if (errors == 0) begin
            $display("====================================");
            $display("ALL PE MAC TESTS PASSED");
            $display("====================================");
        end else begin
            $display("====================================");
            $display("PE MAC TESTS FAILED: %0d errors", errors);
            $display("====================================");
        end

        $finish;
    end

endmodule