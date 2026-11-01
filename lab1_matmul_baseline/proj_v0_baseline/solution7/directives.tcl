############################################################
## This file is generated automatically by Vivado HLS.
## Please DO NOT edit it.
## Copyright (C) 1986-2018 Xilinx, Inc. All Rights Reserved.
############################################################
set_directive_unroll "matmul_top/K"
set_directive_pipeline -II 1 "matmul_top/J"
set_directive_array_partition -type complete -dim 2 "matmul_top" A
set_directive_array_partition -type complete -dim 1 "matmul_top" B
