# K11-B2 GUI project generator.
#
# This is intentionally a separate Vivado project-mode flow.  It mirrors the
# K11-B2 source/XCI/XDC manifest for browsing and hierarchy inspection only;
# it does not source run_k11b2_impl.tcl and does not write build_k11b2.
#
# Batch usage:
#   vivado -mode batch \
#     -source fpga/kcu105/create_k11b2_gui_project.tcl
#
# GUI usage (the project remains open):
#   vivado -mode gui \
#     -source fpga/kcu105/create_k11b2_gui_project.tcl
#
# Optional first Tcl argument selects the output directory.  The default is
# fpga/kcu105/build_k11b2_gui, which is isolated from all existing K11 builds.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set gui_dir     [file join $script_dir build_k11b2_gui]
if {[llength $argv] >= 1} {
  set gui_dir [file normalize [lindex $argv 0]]
}

set project_name k11b2_gui
set project_path [file join $gui_dir $project_name.xpr]
set part_name xcku040-ffva1156-2-e
set top_name kcu105_pcie_ep_gen1_board_top
set afifo_path /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
set xci_path [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.xci]
set xdc_path [file join $script_dir k03_gen1_ltssm_mac.xdc]

if {![file exists $afifo_path]} {
  error "K11-B2 GUI工程缺少afifo依赖：$afifo_path"
}
if {![file exists $xci_path]} {
  error "K11-B2 GUI工程缺少PHY XCI：$xci_path"
}
if {![file exists $xdc_path]} {
  error "K11-B2 GUI工程缺少约束：$xdc_path"
}

file mkdir $gui_dir
create_project -force $project_name $gui_dir -part $part_name
# Vivado's project property uses Verilog for a mixed Verilog/SystemVerilog
# design; individual .sv files retain their SystemVerilog file type.
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Keep this list aligned with the production K11-B2 manifest in
# run_k11b2_impl.tcl.  add_files links the original files into this browsing
# project; it does not copy or modify the production source tree.
set rtl_files [list \
  $afifo_path \
  [file join $project_dir rtl/common/pcie_reset_sync.sv] \
  [file join $project_dir rtl/common/pcie_gray_sync.sv] \
  [file join $project_dir rtl/common/pcie_async_pkt_fifo.sv] \
  [file join $project_dir rtl/common/pcie_async_event_fifo.sv] \
  [file join $project_dir rtl/common/pcie_tlp_async_bridge.sv] \
  [file join $project_dir rtl/common/pcie_cdc_snapshot.sv] \
  [file join $project_dir rtl/common/pcie_cdc_pulse.sv] \
  [file join $project_dir rtl/phy/kcu105_reset_ctrl.sv] \
  [file join $project_dir rtl/phy/kcu105_refclk_reset.sv] \
  [file join $project_dir rtl/phy/kcu105_pcie_phy_wrapper.sv] \
  [file join $project_dir rtl/phy/pcie_gen12_scrambler.sv] \
  [file join $project_dir rtl/phy/pcie_gen1_rx_symbol_aligner.sv] \
  [file join $project_dir rtl/phy/pcie_gen1_os_rx.sv] \
  [file join $project_dir rtl/phy/pcie_gen1_os_tx.sv] \
  [file join $project_dir rtl/phy/pcie_gen1_framer.sv] \
  [file join $project_dir rtl/common/pcie_link_loss_trigger.sv] \
  [file join $project_dir rtl/phy/pcie_ltssm_mac_gen1.sv] \
  [file join $project_dir rtl/dll/pcie_crc_stream.sv] \
  [file join $project_dir rtl/dll/pcie_crc16_dllp.sv] \
  [file join $project_dir rtl/dll/pcie_crc32_lcrc.sv] \
  [file join $project_dir rtl/dll/pcie_fc_local_credit_pool.sv] \
  [file join $project_dir rtl/dll/pcie_dllp_codec.sv] \
  [file join $project_dir rtl/dll/pcie_dllp_fc_manager.sv] \
  [file join $project_dir rtl/dll/pcie_dllp_tx_arbiter.sv] \
  [file join $project_dir rtl/dll/pcie_dll_mac_tx_arbiter.sv] \
  [file join $project_dir rtl/dll/pcie_dll_replay.sv] \
  [file join $project_dir rtl/dll/pcie_dll.sv] \
  [file join $project_dir rtl/tl/pcie_tlp_codec.sv] \
  [file join $project_dir rtl/tl/pcie_cfg_space.sv] \
  [file join $project_dir rtl/tl/pcie_bar_axil_master.sv] \
  [file join $project_dir rtl/tl/demo_axil_slave.sv] \
  [file join $project_dir sim/verilator/k09_integration/k09_tlp_test_top.sv] \
  [file join $project_dir rtl/ep/k11a_offline_top.sv] \
  [file join $project_dir rtl/ep/kcu105_pcie_ep_gen1_top.sv] \
  [file join $project_dir rtl/ep/kcu105_pcie_ep_gen1_board_top.sv]]

foreach file_path $rtl_files {
  if {![file exists $file_path]} {
    error "K11-B2 GUI工程源文件不存在：$file_path"
  }
}
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_path
add_files -norecurse $xci_path

set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Do not call generate_target/synth_design here.  This project is for source
# browsing; keeping IP generation and implementation out of this script makes
# it side-effect-free with respect to the production K11-B2 flow.
puts "K11B2_GUI_PROJECT_PASS project=$project_path"
puts "K11B2_GUI_TOP=$top_name part=$part_name"
puts "K11B2_GUI_NOTE=source browsing only; production build remains run_k11b2_impl.tcl"
