set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $script_dir build_k11_gen1_release impl]
set phy_module pcie_phy_x1_gen3
set xci_path [file join $script_dir ip $phy_module ${phy_module}.xci]
set afifo_path /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
set part_name xcku040-ffva1156-2-e
set top_name kcu105_pcie_ep_gen1_board_top
set g9_cycles 6250000
if {[info exists ::env(G9_WAIT_REMOTE_DETECT_CYCLES)]} {
  set g9_cycles $::env(G9_WAIT_REMOTE_DETECT_CYCLES)
}
if {$g9_cycles < 1} { error "G9_WAIT_REMOTE_DETECT_CYCLES must be positive" }
if {![file exists $xci_path]} { error "K02 PHY XCI missing: $xci_path" }
if {![file exists $afifo_path]} { error "Frozen afifo dependency missing: $afifo_path" }
file mkdir $build_dir
cd $project_dir

set_part $part_name
read_ip $xci_path
generate_target all [get_ips $phy_module]
set ip_dcp [file join $script_dir ip $phy_module ${phy_module}.dcp]
if {[file exists $ip_dcp]} { file delete -force $ip_dcp }
synth_ip -force [get_ips $phy_module]

read_verilog $afifo_path
set sv_files [list \
  rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
  rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
  rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
  rtl/common/pcie_cdc_pulse.sv rtl/common/pcie_link_loss_trigger.sv \
  rtl/phy/kcu105_reset_ctrl.sv rtl/phy/kcu105_refclk_reset.sv \
  rtl/phy/kcu105_pcie_phy_wrapper.sv rtl/phy/pcie_gen12_scrambler.sv \
  rtl/phy/pcie_gen1_rx_symbol_aligner.sv rtl/phy/pcie_gen1_os_rx.sv \
  rtl/phy/pcie_gen1_os_tx.sv rtl/phy/pcie_gen3_scrambler32.sv \
  rtl/phy/pcie_gen3_os_rx.sv rtl/phy/pcie_gen3_os_tx.sv \
  rtl/phy/pcie_gen1_framer.sv rtl/phy/pcie_phy_command_ctrl.sv \
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

synth_design -top $top_name -part $part_name \
  -generic G9_WAIT_REMOTE_DETECT=1 \
  -generic G9_WAIT_REMOTE_DETECT_CYCLES=$g9_cycles

set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
  {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
if {[llength $afifo_gray_sync_cells] == 0} { error "afifo Gray synchronizers not found" }
set_property ASYNC_REG TRUE $afifo_gray_sync_cells
set_property SHREG_EXTRACT NO $afifo_gray_sync_cells

write_checkpoint -force [file join $build_dir k11_gen1_synth.dcp]
opt_design
place_design
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $build_dir k11_gen1_routed.dcp]
report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 50 -sort_by group \
  -file [file join $build_dir timing_paths_50.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc_routed.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_pin {port_name expected_pin} {
  set port_object [get_ports $port_name]
  if {[llength $port_object] != 1} { error "Missing top port: $port_name" }
  set actual_pin [get_property PACKAGE_PIN $port_object]
  if {![string equal -nocase $actual_pin $expected_pin]} {
    error "Pin mismatch $port_name=$actual_pin expected=$expected_pin"
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
set gth_commons [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1 ||
    ![string equal -nocase [get_property LOC $gth_channels] GTHE3_CHANNEL_X0Y7]} {
  error "GTHE3 channel placement mismatch"
}
if {[llength $gth_commons] != 1 ||
    ![string equal -nocase [get_property LOC $gth_commons] GTHE3_COMMON_X0Y1]} {
  error "GTHE3 common placement mismatch"
}
set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
  REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} { error "Unexpected PCIe hard block count=$hard_pcie_count" }

proc require_hierarchy_count {module_name expected} {
  set cells [get_cells -quiet -hierarchical -filter "ORIG_REF_NAME == $module_name"]
  if {[llength $cells] == 0} {
    set cells [get_cells -quiet -hierarchical -filter "REF_NAME == $module_name"]
  }
  if {[llength $cells] != $expected} {
    error "$module_name hierarchy count=[llength $cells] expected=$expected"
  }
}
require_hierarchy_count pcie_phy_command_ctrl 1
require_hierarchy_count pcie_ltssm_mac_gen1 1
require_hierarchy_count pcie_dll 1
require_hierarchy_count pcie_cfg_space 1
require_hierarchy_count pcie_bar_axil_master 1
require_hierarchy_count demo_axil_slave 1

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {[llength $setup_paths] != 0} { error "Gen1 release has negative setup timing" }
if {[llength $hold_paths] != 0} { error "Gen1 release has negative hold timing" }
set max_path [get_timing_paths -delay_type max -max_paths 1]
set min_path [get_timing_paths -delay_type min -max_paths 1]
set wns [get_property SLACK $max_path]
set whs [get_property SLACK $min_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
  error "DRC contains Error or Critical Warning"
}
if {[llength [get_debug_cores -quiet]] != 0} { error "Debug core found in release" }

set bit_path [file join $build_dir k11b2_gen1_endpoint.bit]
write_bitstream -force $bit_path
set summary [open [file join $build_dir summary.txt] w]
puts $summary "K11_GEN1_COMMAND_BOUNDARY_IMPL_PASS"
puts $summary "part=$part_name"
puts $summary "top=$top_name"
puts $summary "G9_WAIT_REMOTE_DETECT=1"
puts $summary "G9_WAIT_REMOTE_DETECT_CYCLES=$g9_cycles"
puts $summary "PHY_COMMAND_CTRL_COUNT=1"
puts $summary "WNS=$wns"
puts $summary "WHS=$whs"
puts $summary "DRC_ERROR_COUNT=[llength $drc_errors]"
puts $summary "DEBUG_CORE_COUNT=[llength [get_debug_cores -quiet]]"
puts $summary "bitstream=$bit_path"
close $summary
puts "K11_GEN1_COMMAND_BOUNDARY_IMPL_PASS WNS=$wns WHS=$whs"
