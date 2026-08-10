set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k11b2 impl]
set xci_path    [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.xci]
set afifo_path  /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
set part_name   xcku040-ffva1156-2-e
set top_name    kcu105_pcie_ep_gen1_board_top
file mkdir $build_dir

if {![file exists $xci_path]} { error "K11-B2 XCI不存在，请先执行make k02-ip：$xci_path" }
if {![file exists $afifo_path]} { error "缺少冻结afifo依赖：$afifo_path" }

set_part $part_name
read_ip $xci_path
generate_target all [get_ips pcie_phy_x1_gen3]
set ip_dcp [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.dcp]
if {[file exists $ip_dcp]} { file delete -force $ip_dcp }
synth_ip -force [get_ips pcie_phy_x1_gen3]

read_verilog $afifo_path
set sv_files [list \
  rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
  rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
  rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
  rtl/common/pcie_cdc_pulse.sv \
  rtl/phy/kcu105_reset_ctrl.sv rtl/phy/kcu105_refclk_reset.sv \
  rtl/phy/kcu105_pcie_phy_wrapper.sv rtl/phy/pcie_gen12_scrambler.sv \
  rtl/phy/pcie_gen1_rx_symbol_aligner.sv rtl/phy/pcie_gen1_os_rx.sv \
  rtl/phy/pcie_gen1_os_tx.sv rtl/phy/pcie_gen1_framer.sv \
  rtl/phy/pcie_ltssm_mac_gen1.sv \
  rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv \
  rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv \
  rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv \
  rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv \
  rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv \
  rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv \
  rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv \
  sim/verilator/k09_integration/k09_tlp_test_top.sv \
  rtl/ep/k11a_offline_top.sv rtl/ep/kcu105_pcie_ep_gen1_top.sv \
  rtl/ep/kcu105_pcie_ep_gen1_board_top.sv]
foreach f $sv_files { read_verilog -sv [file join $project_dir $f] }
read_xdc [file join $script_dir k03_gen1_ltssm_mac.xdc]

synth_design -top $top_name -part $part_name
set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
  {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
if {[llength $afifo_gray_sync_cells] == 0} { error "K11-B2未找到afifo Gray同步寄存器" }
set_property ASYNC_REG TRUE $afifo_gray_sync_cells
set_property SHREG_EXTRACT NO $afifo_gray_sync_cells
write_checkpoint -force [file join $build_dir k11b2_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $build_dir k11b2_routed.dcp]
report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc_routed.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_pin {port_name expected_pin} {
  set port_object [get_ports $port_name]
  if {[llength $port_object] != 1} { error "K11-B2顶层端口不存在：$port_name" }
  set actual_pin [get_property PACKAGE_PIN $port_object]
  if {![string equal -nocase $actual_pin $expected_pin]} {
    error "K11-B2管脚错误：$port_name=$actual_pin，期望$expected_pin"
  }
}
require_port_pin pcie_refclk_p AB6
require_port_pin pcie_refclk_n AB5
require_port_pin pcie_perst_n K22
require_port_pin pcie_rxp AB2
require_port_pin pcie_rxn AB1
require_port_pin pcie_txp AC4
require_port_pin pcie_txn AC3

set gth_channels [get_cells -hierarchical -filter {REF_NAME == GTHE3_CHANNEL}]
set gth_commons  [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1} { error "K11-B2 GTHE3_CHANNEL数量错误：[llength $gth_channels]" }
if {[llength $gth_commons] != 1} { error "K11-B2 GTHE3_COMMON数量错误：[llength $gth_commons]" }
set channel_loc [get_property LOC $gth_channels]
set common_loc [get_property LOC $gth_commons]
if {![string equal -nocase $channel_loc GTHE3_CHANNEL_X0Y7]} { error "K11-B2 GT Channel LOC错误：$channel_loc" }
if {![string equal -nocase $common_loc GTHE3_COMMON_X0Y1]} { error "K11-B2 GT Common LOC错误：$common_loc" }

set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
  REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} { error "K11-B2错误实例化PCIe Hard Block：$hard_pcie_count" }

proc require_hierarchy {module_name} {
  set cells [get_cells -quiet -hierarchical -filter "ORIG_REF_NAME == $module_name"]
  if {[llength $cells] == 0} { set cells [get_cells -quiet -hierarchical -filter "REF_NAME == $module_name"] }
  if {[llength $cells] == 0} { error "K11-B2找不到层次：$module_name" }
  return [llength $cells]
}
set mac_count  [require_hierarchy pcie_ltssm_mac_gen1]
set dll_count  [require_hierarchy pcie_dll]
set cfg_count  [require_hierarchy pcie_cfg_space]
set bar_count  [require_hierarchy pcie_bar_axil_master]
set demo_count [require_hierarchy demo_axil_slave]

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {[llength $setup_paths] != 0} { error "K11-B2存在setup负时序" }
if {[llength $hold_paths] != 0} { error "K11-B2存在hold负时序" }
set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} { error "K11-B2找不到可分析的最大延迟路径" }
set wns [get_property SLACK $worst_path]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
  error "K11-B2 DRC存在Error或Critical Warning"
}
set cdc_fp [open [file join $build_dir cdc_routed.rpt] r]
set cdc_text [read $cdc_fp]
close $cdc_fp
if {[regexp -line {^CDC-[0-9]+[ \t]+Critical[ \t]+[1-9][0-9]*} $cdc_text]} {
  error "K11-B2 CDC存在Critical路径"
}

write_bitstream -force [file join $build_dir k11b2_gen1_endpoint.bit]
set summary_file [open [file join $build_dir summary.txt] w]
puts $summary_file "K11B2_IMPL_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "top=$top_name"
puts $summary_file "GTHE3_CHANNEL_LOC=$channel_loc"
puts $summary_file "GTHE3_COMMON_LOC=$common_loc"
puts $summary_file "PCIE_HARD_BLOCK_COUNT=$hard_pcie_count"
puts $summary_file "MAC_HIERARCHY_COUNT=$mac_count"
puts $summary_file "DLL_HIERARCHY_COUNT=$dll_count"
puts $summary_file "CFG_HIERARCHY_COUNT=$cfg_count"
puts $summary_file "BAR_HIERARCHY_COUNT=$bar_count"
puts $summary_file "DEMO_HIERARCHY_COUNT=$demo_count"
puts $summary_file "WNS=$wns"
puts $summary_file "bitstream=[file join $build_dir k11b2_gen1_endpoint.bit]"
close $summary_file
puts "K11B2_IMPL_PASS channel=$channel_loc common=$common_loc WNS=$wns"
