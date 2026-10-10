#/**************************************************/
#/* Compile Script for Synopsys                    */
#/*                                                */
#/* dc_shell-t -f compile_dc.tcl                   */
#/*                                                */
#/* OSU FreePDK 45nm                               */
#/**************************************************/

#/* All verilog files, separated by spaces         */
set dir "../pipeline"
set files [glob -nocomplain -tails -directory $dir -type f *.sv]
set my_verilog_files [lsearch -all -inline -not -exact $files testbench.sv]

#/* Top-level Module                               */
set my_toplevel top

#/* The name of the clock pin. If no clock-pin     */
#/* exists, pick anything                          */
set my_clock_pin *clk

#/* Target frequency in MHz for optimization       */
set my_clk_freq_MHz 1000

#/* Delay of input signals (Clock-to-Q, Package etc.)  */
set my_input_delay_ns 0.1

#/* Reserved time for output signals (Holdtime etc.)   */
set my_output_delay_ns 0.1


#/**************************************************/
#/* No modifications needed below                  */
#/**************************************************/
set OSU_FREEPDK [format "%s%s"  [getenv "PDK_DIR"] "/osu_soc/lib/files"]
set search_path [concat  $search_path $dir $OSU_FREEPDK]
set alib_library_analysis_path $OSU_FREEPDK

set link_library [set target_library [concat  [list gscl45nm.db] [list dw_foundation.sldb]]]
set target_library "gscl45nm.db"
define_design_lib WORK -path ./WORK
set verilogout_show_unconnected_pins "true"
set_ultra_optimization true
set_ultra_optimization -force

analyze -f sv $my_verilog_files

elaborate $my_toplevel

current_design $my_toplevel

link
uniquify

set my_period [expr 1000 / $my_clk_freq_MHz]

foreach_in_collection clk [get_ports $my_clock_pin] {
   set clk_name $clk
   create_clock -period $my_period $clk_name
}

set_driving_cell  -lib_cell INVX1  [all_inputs]
set_input_delay $my_input_delay_ns -clock $clk_name [remove_from_collection [all_inputs] $my_clock_pin]
set_output_delay $my_output_delay_ns -clock $clk_name [all_outputs]

compile -ungroup_all -map_effort medium

compile -incremental_mapping -map_effort medium

check_design
report_constraint -all_violators
change_names -hierarchy -rules verilog

set filename [format "%s%s"  ${my_toplevel}_pipe ".vh"]
write_file -format verilog -hierarchy -output $filename 


#set filename [format "%s%s"  $my_toplevel ".vh"]
#write -f verilog -output $filename

#set filename [format "%s%s"  $my_toplevel ".sdc"]
#write_sdc $filename

#set filename [format "%s%s"  $my_toplevel ".db"]
#write -f db -hier -output $filename -xg_force_db

redirect clocks_pipe.rep { report_clocks }
redirect timing_pipe.rep { report_timing }
redirect cell_pipe.rep { report_cell }
redirect power_pipe.rep { report_power }
redirect area_pipe.rep { report_area }

quit
