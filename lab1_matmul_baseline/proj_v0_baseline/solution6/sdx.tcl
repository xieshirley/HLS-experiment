# ==============================================================
# File generated on Sun Nov 01 17:50:44 +0800 2026
# Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC v2018.3 (64-bit)
# SW Build 2405991 on Thu Dec  6 23:38:27 MST 2018
# IP Build 2404404 on Fri Dec  7 01:43:56 MST 2018
# Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
# ==============================================================
add_files -tb ../../matmul_tb.cpp -cflags { -Wno-unknown-pragmas}
add_files dataflow_mul.cpp
set_part xc7a100tcsg324-1
create_clock -name default -period 10
set_clock_uncertainty 0.1 default
set_directive_dataflow matmul_top 
set_directive_unroll matmul_core/matmul_core_label1 
set_directive_pipeline matmul_core/matmul_core_label2 -II 1
set_directive_array_partition matmul_top 
set_directive_array_partition matmul_top 
set_directive_array_partition matmul_top 
set_directive_array_partition matmul_top 
set_directive_pipeline load_A/k -II 1
set_directive_pipeline load_B/j -II 1
set_directive_pipeline store/store_label3 -II 1
