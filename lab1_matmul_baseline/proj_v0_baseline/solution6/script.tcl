############################################################
## This file is generated automatically by Vivado HLS.
## Please DO NOT edit it.
## Copyright (C) 1986-2018 Xilinx, Inc. All Rights Reserved.
############################################################
open_project proj_v0_baseline
set_top matmul_top
add_files matmul.cpp
add_files -tb matmul_tb.cpp -cflags "-Wno-unknown-pragmas"
open_solution "solution6"
set_part {xc7a100tcsg324-1}
create_clock -period 10 -name default
set_clock_uncertainty 0.1
source "./proj_v0_baseline/solution6/directives.tcl"
csim_design -clean
csynth_design
cosim_design -trace_level all -tool xsim
export_design -format ip_catalog
