set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $script_dir build_m02]
set part_name xcku060-ffva1156-2-i
set afifo_rtl /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v

file mkdir $build_dir

read_verilog $afifo_rtl
read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/common/pcie_gray_sync.sv]
read_verilog -sv [file join $project_dir rtl/common/pcie_async_pkt_fifo.sv]
read_xdc [file join $script_dir m02_async_pkt_fifo.xdc]

synth_design -top pcie_async_pkt_fifo -part $part_name -mode out_of_context \
    -generic LGFIFO=9

# afifo.v 把跨域移位部分标记为 ASYNC_REG，但最终接收级 wr_rgray/rd_wgray
# 未包含在源码属性中。保持第三方源码不变，在约束层补齐最终同步级属性。
set afifo_final_sync_cells [get_cells -hierarchical -filter {
    NAME =~ *u_data_afifo/wr_rgray_reg* ||
    NAME =~ *u_data_afifo/rd_wgray_reg* ||
    NAME =~ *u_descriptor_afifo/wr_rgray_reg* ||
    NAME =~ *u_descriptor_afifo/rd_wgray_reg*
}]
if {[llength $afifo_final_sync_cells] != 40} {
    error "M02 afifo 最终同步级数量异常：[llength $afifo_final_sync_cells]，期望 40"
}
set_property ASYNC_REG TRUE $afifo_final_sync_cells
set_property SHREG_EXTRACT NO $afifo_final_sync_cells

write_checkpoint -force [file join $build_dir m02_synth.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set ramb36_count [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36*}]]
set ramb18_count [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB18*}]]
set async_reg_count [llength [get_cells -hierarchical -filter {ASYNC_REG == TRUE}]]
set total_bram_equivalent [expr {$ramb36_count * 2 + $ramb18_count}]

if {$total_bram_equivalent < 2} {
    error "M02 BRAM 推断失败：RAMB36=$ramb36_count RAMB18=$ramb18_count"
}
if {$async_reg_count < 40} {
    error "M02 CDC 属性检查失败：ASYNC_REG=$async_reg_count，期望至少 40"
}

set summary_path [file join $build_dir summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "M02_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "RAMB36=$ramb36_count"
puts $summary_file "RAMB18=$ramb18_count"
puts $summary_file "ASYNC_REG=$async_reg_count"
close $summary_file

puts "M02_VIVADO_PASS part=$part_name RAMB36=$ramb36_count RAMB18=$ramb18_count ASYNC_REG=$async_reg_count"
