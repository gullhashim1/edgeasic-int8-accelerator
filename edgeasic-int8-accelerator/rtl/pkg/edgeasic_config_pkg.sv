`timescale 1ns/1ps

package edgeasic_config_pkg;


  parameter int N = 8;      // 8×8 systolic array
  parameter int ACT_W = 8;  // INT8 activations
  parameter int WGT_W = 8;  // INT8 weights
  parameter int ACC_W = 32; // INT32 accumulation
  parameter int OUT_W = 8;  // INT8 final output
  parameter int ARRAY_N = 8;

endpackage