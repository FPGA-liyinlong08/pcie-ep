set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k10]
set part_name   xcku040-ffva1156-2-e
set top_name    k10_demo_axil_ooc_top
file mkdir $build_dir
file delete -force [file join $build_dir summary_candidate.txt]

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/tl/demo_axil_slave.sv]
read_verilog -sv [file join $project_dir rtl/tl/k10_demo_axil_ooc_top.sv]
read_xdc [file join $script_dir k10_demo_axil_ooc.xdc]
synth_design -mode out_of_context -top $top_name -part $part_name
read_xdc -mode out_of_context [file join $script_dir k10_demo_axil_ooc_impl.xdc]

set partpin_ports {}
foreach boundary_port [get_ports -quiet -filter {NAME != clk}] {
    set dynamic 0
    foreach boundary_net [get_nets -quiet -of_objects $boundary_port] {
        if {![string match "<const*>" $boundary_net]} { set dynamic 1 }
    }
    if {$dynamic} { lappend partpin_ports $boundary_port }
}
if {[llength $partpin_ports] == 0} { error "K10没有动态边界端口" }
set_property HD.PARTPIN_RANGE {SLICE_X76Y60:SLICE_X100Y119} $partpin_ports
set partpin_count [llength $partpin_ports]

# 与phy_coreclk BUFG_GT_X0Y26相同的X3Y1 Clock Region，包含本阶段所需BRAM列。
create_pblock pblock_k10_core_x3y1
resize_pblock [get_pblocks pblock_k10_core_x3y1] -add \
    {SLICE_X76Y60:SLICE_X100Y119 RAMB36_X8Y12:RAMB36_X9Y23}
add_cells_to_pblock [get_pblocks pblock_k10_core_x3y1] -top

write_checkpoint -force [file join $build_dir k10_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]
opt_design
place_design
write_checkpoint -force [file join $build_dir k10_placed.dcp]
route_design
write_checkpoint -force [file join $build_dir k10_routed.dcp]

report_route_status -file [file join $build_dir route_status.rpt]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "K10找不到setup/hold路径"
}
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
if {$wns < 0.0 || $whs < 0.0} {
    error "K10 Route时序失败 WNS=$wns WHS=$whs"
}

set all_regs [all_registers]
set input_ports [get_ports -filter {
    DIRECTION == IN && NAME != clk && NAME != rst_n
}]
set output_ports [get_ports -filter {DIRECTION == OUT}]
set input_setup [get_timing_paths -delay_type max -max_paths 1 \
    -from $input_ports -to $all_regs]
set output_setup [get_timing_paths -delay_type max -max_paths 1 \
    -from $all_regs -to $output_ports]
set input_hold [get_timing_paths -delay_type min -max_paths 1 \
    -from $input_ports -to $all_regs]
set output_hold [get_timing_paths -delay_type min -max_paths 1 \
    -from $all_regs -to $output_ports]
foreach timing_path [list $input_setup $output_setup $input_hold $output_hold] {
    if {[llength $timing_path] != 1} { error "K10接口时序路径缺失" }
    if {[get_property SLACK $timing_path] < 0.0} {
        error "K10接口时序失败：[get_property SLACK $timing_path]"
    }
}
set input_setup_slack [get_property SLACK $input_setup]
set output_setup_slack [get_property SLACK $output_setup]
set input_hold_slack [get_property SLACK $input_hold]
set output_hold_slack [get_property SLACK $output_hold]

report_timing -delay_type max -max_paths 20 -from $input_ports -to $all_regs \
    -file [file join $build_dir timing_interface_input.rpt]
report_timing -delay_type max -max_paths 20 -from $all_regs -to $output_ports \
    -file [file join $build_dir timing_interface_output.rpt]
report_timing -delay_type min -max_paths 20 -from $input_ports -to $all_regs \
    -file [file join $build_dir timing_interface_input_hold.rpt]
report_timing -delay_type min -max_paths 20 -from $all_regs -to $output_ports \
    -file [file join $build_dir timing_interface_output_hold.rpt]

set lut_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ FD*}]]
set bram_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ RAMB*}]]
set dsp_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP*}]]
set pcie_count [llength [get_cells -quiet -hierarchical -filter {
    REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$bram_count < 1} { error "K10测试RAM未推断BRAM" }
if {$dsp_count != 0 || $pcie_count != 0} {
    error "K10出现禁止资源 DSP=$dsp_count PCIE=$pcie_count"
}

set summary [open [file join $build_dir summary_candidate.txt] w]
puts $summary "K10_VIVADO_PASS"
puts $summary "part=$part_name"
puts $summary "top=$top_name"
puts $summary "IMPLEMENTATION=ROUTED"
puts $summary "WNS=$wns"
puts $summary "WHS=$whs"
puts $summary "TNS=0.000"
puts $summary "THS=0.000"
puts $summary "INTERFACE_INPUT_SETUP_SLACK=$input_setup_slack"
puts $summary "INTERFACE_OUTPUT_SETUP_SLACK=$output_setup_slack"
puts $summary "INTERFACE_INPUT_HOLD_SLACK=$input_hold_slack"
puts $summary "INTERFACE_OUTPUT_HOLD_SLACK=$output_hold_slack"
puts $summary "INTERFACE_INPUT_MIN_DELAY_NS=-1.000"
puts $summary "INTERFACE_OUTPUT_MIN_DELAY_NS=0.000"
puts $summary "LUT_PRIMITIVES=$lut_count"
puts $summary "FF=$ff_count"
puts $summary "BRAM=$bram_count"
puts $summary "DSP=$dsp_count"
puts $summary "PCIE_HARD_BLOCK=$pcie_count"
puts $summary "PARTPIN_DYNAMIC_PORTS=$partpin_count"
close $summary
puts "K10_VIVADO_PASS WNS=$wns WHS=$whs BRAM=$bram_count"
