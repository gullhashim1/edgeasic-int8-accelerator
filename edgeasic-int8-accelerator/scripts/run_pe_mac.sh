#!/bin/bash
set -e

# Create sim directory if it does not exist
mkdir -p sim

echo "Compiling PE MAC..."
iverilog -g2012 -o sim/pe_mac_tb.vvp \
    rtl/pkg/edgeasic_config_pkg.sv \
    rtl/pkg/edgeasic_types_pkg.sv \
    rtl/core/pe_mac.sv \
    tb/tb_pe_mac.sv

echo "Running PE MAC simulation..."
vvp sim/pe_mac_tb.vvp
