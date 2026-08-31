set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build]
set project_path [file join $build_dir example xdma_x1_ex xdma_x1_ex.xpr]
set output_bit [file join $build_dir xdma_x1_demo.bit]
set summary_path [file join $build_dir summary.txt]

if {![file exists $project_path]} {
    error "XDMA x1 example工程不存在，请先执行create_xdma_x1_demo.tcl"
}
open_project $project_path

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
if {![string match {*Complete*} $run_status]} {
    error "XDMA x1实现失败：$run_status"
}

open_run impl_1
set width [get_property CONFIG.pl_link_cap_max_link_width [get_ips xdma_x1]]
set speed [get_property CONFIG.pl_link_cap_max_link_speed [get_ips xdma_x1]]
set quad [get_property CONFIG.select_quad [get_ips xdma_x1]]
if {$width ne "X1" || $speed ne "8.0_GT/s" || $quad ne "GTH_Quad_225"} {
    error "XDMA配置错误：width=$width speed=$speed quad=$quad"
}

set channels [get_cells -hierarchical -filter {REF_NAME == GTHE3_CHANNEL}]
set commons [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $channels] != 1 || [llength $commons] != 1} {
    error "XDMA x1 GT数量错误：channel=[llength $channels] common=[llength $commons]"
}
set channel_loc [get_property LOC $channels]
set common_loc [get_property LOC $commons]

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {[llength $setup_paths] != 0 || [llength $hold_paths] != 0} {
    error "XDMA x1存在负时序"
}
set worst_path [get_timing_paths -delay_type max -max_paths 1]
set wns [get_property SLACK $worst_path]

report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $build_dir timing_summary.rpt]
report_drc -file [file join $build_dir drc.rpt]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
    error "XDMA x1 DRC存在Error或Critical Warning"
}

set run_bit [file join $build_dir example xdma_x1_ex xdma_x1_ex.runs impl_1 xilinx_dma_pcie_ep.bit]
if {![file exists $run_bit]} {
    error "XDMA x1 bitstream未生成：$run_bit"
}
file copy -force $run_bit $output_bit

set fp [open $summary_path w]
puts $fp "XDMA_X1_IMPL_PASS"
puts $fp "part=[get_property PART [current_project]]"
puts $fp "width=$width"
puts $fp "speed=$speed"
puts $fp "quad=$quad"
puts $fp "channel_loc=$channel_loc"
puts $fp "common_loc=$common_loc"
puts $fp "wns=$wns"
puts $fp "bitstream=$output_bit"
close $fp

puts "XDMA_X1_IMPL_PASS width=$width speed=$speed channel=$channel_loc common=$common_loc WNS=$wns"
close_project
