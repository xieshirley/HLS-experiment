open_project -reset unsharp_prj
set_top unsharp3x3
add_files unsharp3x3.cpp
open_solution -reset solution1
set_part {xc7a35tfgg484-2}
create_clock -period 6.734 -name default
csynth_design
exit