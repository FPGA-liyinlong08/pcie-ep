set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k02]
set xci_path    [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.xci]
set part_name   xcku040-ffva1156-2-e
set top_name    kcu105_pcie_phy_bringup_top

file mkdir $build_dir

if {![file exists $xci_path]} {
    error "K02 XCI 不存在，请先执行 make k02-ip：$xci_path"
}

set_part $part_name
read_ip $xci_path
generate_target all [get_ips pcie_phy_x1_gen3]
# `synth_ip -force` 在 Vivado 2021.2 仍不会覆盖已有的同名 OOC DCP。
# 仅删除本 IP 的确定目标，保证脚本可重复执行且真实执行一次 OOC 综合。
set ip_dcp [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.dcp]
if {[file exists $ip_dcp]} {
    file delete -force $ip_dcp
}
synth_ip -force [get_ips pcie_phy_x1_gen3]

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_reset_ctrl.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_refclk_reset.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_pcie_phy_wrapper.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_pcie_phy_bringup_top.sv]
read_xdc [file join $script_dir k02_pcie_phy_bringup.xdc]

synth_design -top $top_name -part $part_name
write_checkpoint -force [file join $build_dir k02_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
write_checkpoint -force [file join $build_dir k02_placed.dcp]
route_design
write_checkpoint -force [file join $build_dir k02_routed.dcp]

report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc_routed.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_pin {port_name expected_pin} {
    set port_object [get_ports $port_name]
    if {[llength $port_object] != 1} {
        error "K02 顶层端口不存在：$port_name"
    }
    set actual_pin [get_property PACKAGE_PIN $port_object]
    if {![string equal -nocase $actual_pin $expected_pin]} {
        error "K02 管脚错误：$port_name=$actual_pin，期望 $expected_pin"
    }
}

require_port_pin pcie_refclk_p AB6
require_port_pin pcie_refclk_n AB5
require_port_pin pcie_perst_n  K22
require_port_pin pcie_rxp      AB2
require_port_pin pcie_rxn      AB1
require_port_pin pcie_txp      AC4
require_port_pin pcie_txn      AC3

set gth_channels [get_cells -hierarchical -filter {REF_NAME == GTHE3_CHANNEL}]
set gth_commons  [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1} {
    error "K02 GTHE3_CHANNEL 数量为 [llength $gth_channels]，期望 1"
}
if {[llength $gth_commons] != 1} {
    error "K02 GTHE3_COMMON 数量为 [llength $gth_commons]，期望 1"
}

set channel_loc [get_property LOC $gth_channels]
set common_loc  [get_property LOC $gth_commons]
if {![string equal -nocase $channel_loc GTHE3_CHANNEL_X0Y7]} {
    error "K02 GT Channel LOC=$channel_loc，期望 GTHE3_CHANNEL_X0Y7"
}
if {![string equal -nocase $common_loc GTHE3_COMMON_X0Y1]} {
    error "K02 GT Common LOC=$common_loc，期望 GTHE3_COMMON_X0Y1"
}

set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
    REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} {
    error "K02 错误实例化 PCIe Hard Block，数量 $hard_pcie_count"
}

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} {
    error "K02 找不到可分析的最大延迟路径"
}
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} {
    error "K02 Route 后时序失败：WNS=$wns"
}

write_bitstream -force [file join $build_dir k02_pcie_phy_bringup.bit]

set summary_path [file join $build_dir impl_summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "K02_IMPL_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "top=$top_name"
puts $summary_file "GTHE3_CHANNEL_COUNT=[llength $gth_channels]"
puts $summary_file "GTHE3_CHANNEL_LOC=$channel_loc"
puts $summary_file "GTHE3_COMMON_COUNT=[llength $gth_commons]"
puts $summary_file "GTHE3_COMMON_LOC=$common_loc"
puts $summary_file "PCIE_HARD_BLOCK_COUNT=$hard_pcie_count"
puts $summary_file "WNS=$wns"
puts $summary_file "bitstream=[file join $build_dir k02_pcie_phy_bringup.bit]"
close $summary_file

puts "K02_IMPL_PASS channel=$channel_loc common=$common_loc WNS=$wns"
