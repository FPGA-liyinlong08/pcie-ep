set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k03 ooc]
set part_name   xcku040-ffva1156-2-e
file mkdir $build_dir

set_part $part_name
read_verilog -sv [file join $project_dir rtl/phy/pcie_gen1_rx_symbol_aligner.sv]
read_verilog -sv [file join $project_dir rtl/phy/pcie_gen1_os_rx.sv]
read_verilog -sv [file join $project_dir rtl/phy/pcie_gen1_os_tx.sv]
read_verilog -sv [file join $project_dir rtl/phy/pcie_gen1_framer.sv]
read_verilog -sv [file join $project_dir rtl/phy/pcie_ltssm_mac_gen1.sv]
synth_design -mode out_of_context -top pcie_ltssm_mac_gen1 -part $part_name
create_clock -name phy_pclk_gen1 -period 8.000 [get_ports phy_pclk]
set_false_path -from [get_ports pipe_rst_n]

write_checkpoint -force [file join $build_dir k03_ltssm_mac_ooc.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} {
    error "K03 OOC 找不到可分析的最大延迟路径"
}
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} {
    error "K03 OOC 时序失败：WNS=$wns"
}

set summary_file [open [file join $build_dir summary.txt] w]
puts $summary_file "K03_OOC_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "WNS=$wns"
close $summary_file
puts "K03_OOC_PASS WNS=$wns"
