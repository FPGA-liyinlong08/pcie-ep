set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $script_dir build_m01]
set part_name xcku060-ffva1156-2-i

file mkdir $build_dir

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/common/pcie_bit_sync.sv]
read_verilog -sv [file join $project_dir rtl/common/pcie_clk_reset_ctrl.sv]
read_verilog -sv [file join $project_dir rtl/phy/pcie_clk_reset.sv]
read_xdc [file join $script_dir m01_clock_reset.xdc]

# M01 尚未连接 M03 GT Channel，因此按 OOC 方式综合，避免给临时边界插入 I/O Buffer。
synth_design -top pcie_clk_reset -part $part_name -mode out_of_context

write_checkpoint -force [file join $build_dir m01_synth.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc count_ref_name {pattern} {
    return [llength [get_cells -hierarchical -filter "REF_NAME =~ $pattern"]]
}

set ibufds_gte3_count [count_ref_name IBUFDS_GTE3]
set mmcm_count [count_ref_name MMCME3*]
set bufg_gt_count [count_ref_name BUFG_GT]
# 综合后的逻辑网表会把 BUFG 规范化为 BUFGCE；综合统计仍显示为 BUFG。
set bufg_count [count_ref_name BUFGCE]
set async_reg_count [llength [get_cells -hierarchical -filter {ASYNC_REG == TRUE}]]

if {$ibufds_gte3_count != 1} {
    error "M01 原语检查失败：IBUFDS_GTE3 数量为 $ibufds_gte3_count，期望 1"
}
if {$mmcm_count != 1} {
    error "M01 原语检查失败：MMCME3 数量为 $mmcm_count，期望 1"
}
if {$bufg_gt_count < 2} {
    error "M01 原语检查失败：BUFG_GT 数量为 $bufg_gt_count，期望至少 2"
}
if {$bufg_count < 2} {
    error "M01 原语检查失败：BUFG/BUFGCE 数量为 $bufg_count，期望至少 2"
}
if {$async_reg_count < 12} {
    error "M01 CDC 属性检查失败：ASYNC_REG 寄存器数量为 $async_reg_count，期望至少 12"
}

set summary_path [file join $build_dir summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "M01_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "IBUFDS_GTE3=$ibufds_gte3_count"
puts $summary_file "MMCME3=$mmcm_count"
puts $summary_file "BUFG_GT=$bufg_gt_count"
puts $summary_file "BUFG_EQUIVALENT=$bufg_count"
puts $summary_file "ASYNC_REG=$async_reg_count"
close $summary_file

puts "M01_VIVADO_PASS part=$part_name IBUFDS_GTE3=$ibufds_gte3_count MMCME3=$mmcm_count BUFG_GT=$bufg_gt_count BUFG_EQUIVALENT=$bufg_count ASYNC_REG=$async_reg_count"
