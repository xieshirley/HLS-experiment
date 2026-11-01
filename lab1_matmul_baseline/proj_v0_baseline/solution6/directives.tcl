############################################################
## This file is generated automatically by Vivado HLS.
## Please DO NOT edit it.
## Copyright (C) 1986-2018 Xilinx, Inc. All Rights Reserved.
############################################################
set_directive_dataflow "matmul_top"
set_directive_unroll "matmul_core/matmul_core_label1"
set_directive_pipeline -II 1 "matmul_core/matmul_core_label2"
set_directive_array_partition -type complete -dim 2 "matmul_top" bufA
set_directive_array_partition -type complete -dim 1 "matmul_top" bufB
set_directive_array_partition -type complete -dim 2 "matmul_top" A
set_directive_array_partition -type complete -dim 1 "matmul_top" B
set_directive_pipeline -II 1 "load_A/k"
set_directive_pipeline -II 1 "load_B/j"
set_directive_pipeline -II 1 "store/store_label3"
