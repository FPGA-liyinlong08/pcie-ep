set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $script_dir build_k11a]
file mkdir $build_dir

set part xcku040-ffva1156-2-e
set afifo /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
if {![file exists $afifo]} { error "缺少冻结afifo依赖: $afifo" }

read_verilog $afifo
set sv_files [list \
  rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
  rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
  rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
  rtl/common/pcie_cdc_pulse.sv \
  rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv \
  rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv \
  rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv \
  rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv \
  rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv \
  rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv \
  rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv \
  sim/verilator/k09_integration/k09_tlp_test_top.sv \
  sim/verilator/k11a/k11a_offline_top.sv]
foreach f $sv_files { read_verilog -sv [file join $root_dir $f] }
read_xdc [file join $script_dir k11a_offline_ooc.xdc]

synth_design -top k11a_offline_top -part $part -mode out_of_context
set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
  {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
if {[llength $afifo_gray_sync_cells] == 0} { error "未找到afifo Gray同步寄存器" }
set_property ASYNC_REG TRUE $afifo_gray_sync_cells
set_property SHREG_EXTRACT NO $afifo_gray_sync_cells
write_checkpoint -force [file join $build_dir post_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $build_dir routed.dcp]
report_timing_summary -delay_type min_max -check_timing_verbose \
  -file [file join $build_dir timing_summary.rpt]
report_cdc -details -from [get_clocks pipe_clk] -to [get_clocks core_clk] \
  -file [file join $build_dir cdc_pipe_to_core.rpt]
report_cdc -details -from [get_clocks core_clk] -to [get_clocks pipe_clk] \
  -file [file join $build_dir cdc_core_to_pipe.rpt]
report_drc -file [file join $build_dir drc.rpt]
report_utilization -file [file join $build_dir utilization_routed.rpt]

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {[llength $setup_paths] != 0} { error "K11-A存在setup负时序" }
if {[llength $hold_paths] != 0} { error "K11-A存在hold负时序" }

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
  error "K11-A DRC存在Error或Critical Warning"
}
foreach cdc_report [list cdc_pipe_to_core.rpt cdc_core_to_pipe.rpt] {
  set fp [open [file join $build_dir $cdc_report] r]
  set cdc_text [read $fp]
  close $fp
  if {[regexp -line {^CDC-[0-9]+[ \t]+Critical[ \t]+[1-9][0-9]*} $cdc_text]} {
    error "K11-A CDC存在Critical路径: $cdc_report"
  }
}
puts "K11A_VIVADO_PASS part=$part"
