set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $script_dir build_k01]
set part_name xcku040-ffva1156-2-e

file mkdir $build_dir

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_reset_ctrl.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_refclk_reset.sv]
read_xdc [file join $script_dir k01_refclk_reset.xdc]

synth_design -top kcu105_refclk_reset -part $part_name -mode out_of_context

write_checkpoint -force [file join $build_dir k01_synth.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_property {port_name property_name expected_value} {
    set port_object [get_ports $port_name]
    if {[llength $port_object] != 1} {
        error "K01 端口不存在：$port_name"
    }
    set actual_value [get_property $property_name $port_object]
    if {![string equal -nocase $actual_value $expected_value]} {
        error "K01 端口属性错误：$port_name $property_name=$actual_value，期望 $expected_value"
    }
}

require_port_property pcie_refclk_p PACKAGE_PIN AB6
require_port_property pcie_refclk_n PACKAGE_PIN AB5
require_port_property pcie_perst_n  PACKAGE_PIN K22
require_port_property pcie_perst_n  IOSTANDARD LVCMOS18
require_port_property pcie_perst_n  PULLUP 1

if {![string equal -nocase [get_property CONFIG_VOLTAGE [current_design]] 1.8]} {
    error "K01 CONFIG_VOLTAGE 不是 1.8 V"
}
if {![string equal -nocase [get_property CFGBVS [current_design]] GND]} {
    error "K01 CFGBVS 不是 GND"
}

set ibufds_gte3_count [llength [get_cells -hierarchical -filter {REF_NAME == IBUFDS_GTE3}]]
set bufg_gt_count [llength [get_cells -hierarchical -filter {REF_NAME == BUFG_GT}]]
set async_reg_count [llength [get_cells -hierarchical -filter {ASYNC_REG == TRUE}]]
set forbidden_clocking_count [llength [get_cells -quiet -hierarchical -filter {
    REF_NAME =~ MMCME* || REF_NAME =~ PLLE* || REF_NAME =~ MMCM* || REF_NAME =~ PLL*
}]]

if {$ibufds_gte3_count != 1} {
    error "K01 IBUFDS_GTE3 数量为 $ibufds_gte3_count，期望 1"
}
if {$bufg_gt_count != 1} {
    error "K01 BUFG_GT 数量为 $bufg_gt_count，期望 1"
}
if {$async_reg_count != 8} {
    error "K01 ASYNC_REG 数量为 $async_reg_count，期望 8"
}
if {$forbidden_clocking_count != 0} {
    error "K01 出现未冻结的 MMCM/PLL 原语，数量 $forbidden_clocking_count"
}

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} {
    error "K01 找不到可分析的最大延迟路径"
}
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} {
    error "K01 OOC 最大延迟时序失败：WNS=$wns"
}

set summary_path [file join $build_dir summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "K01_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "IBUFDS_GTE3=$ibufds_gte3_count"
puts $summary_file "BUFG_GT=$bufg_gt_count"
puts $summary_file "ASYNC_REG=$async_reg_count"
puts $summary_file "MMCM_PLL=$forbidden_clocking_count"
puts $summary_file "WNS=$wns"
close $summary_file

puts "K01_VIVADO_PASS part=$part_name IBUFDS_GTE3=$ibufds_gte3_count BUFG_GT=$bufg_gt_count ASYNC_REG=$async_reg_count WNS=$wns"
