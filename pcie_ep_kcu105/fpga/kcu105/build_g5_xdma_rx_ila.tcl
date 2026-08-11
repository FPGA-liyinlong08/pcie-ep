set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir xdma_x1_demo build example xdma_x1_ex \
  xdma_x1_ex.runs impl_1 xilinx_dma_pcie_ep_opt.dcp]
set build_dir [file join $script_dir build_g5_xdma_rx_ila]
set bit_path [file join $build_dir xdma_x1_rx_ila.bit]
set ltx_path [file join $build_dir xdma_x1_rx_ila.ltx]
file mkdir $build_dir

if {![file exists $source_dcp]} { error "G5 XDMA opt DCP不存在：$source_dcp" }
open_checkpoint $source_dcp

set channels [get_cells -hierarchical -quiet -filter {REF_NAME == GTHE3_CHANNEL}]
if {[llength $channels] != 1} {
  error "G5期望唯一GTHE3_CHANNEL，实际[llength $channels]"
}
set channel [lindex $channels 0]
if {[get_property LOC $channel] ne "GTHE3_CHANNEL_X0Y7"} {
  error "G5 XDMA GT位置错误：[get_property LOC $channel]"
}

proc gt_pin_nets {channel pin_pattern expected_width} {
  set pins [get_pins -quiet -of_objects $channel \
    -filter "REF_PIN_NAME =~ $pin_pattern"]
  set nets [lsort -dictionary -unique [get_nets -quiet -of_objects $pins]]
  if {[llength $nets] != $expected_width} {
    error "G5 GT探针宽度错误：$pin_pattern，实际[llength $nets]，期望$expected_width"
  }
  set_property MARK_DEBUG TRUE $nets
  return $nets
}

proc add_ila_probe {core_name probe_index nets} {
  if {$probe_index != 0} { create_debug_port $core_name probe }
  set port [get_debug_ports ${core_name}/probe${probe_index}]
  set_property port_width [llength $nets] $port
  connect_debug_port $port $nets
}

set user_clk_net [get_nets -quiet user_clk]
if {[llength $user_clk_net] != 1} {
  error "G5 XDMA user_clk不存在或不唯一：[llength $user_clk_net]"
}
set_property MARK_DEBUG TRUE $user_clk_net

set rx_status [concat \
  [gt_pin_nets $channel RXRESETDONE 1] \
  [gt_pin_nets $channel RXELECIDLE 1] \
  [gt_pin_nets $channel RXVALID 1] \
  [gt_pin_nets $channel RXSTATUS* 3]]
set rx_control [concat \
  [gt_pin_nets $channel RXCDRHOLD 1] \
  [gt_pin_nets $channel RXRATE* 3] \
  [gt_pin_nets $channel RXPD* 2] \
  [gt_pin_nets $channel RXPOLARITY 1] \
  [gt_pin_nets $channel RX8B10BEN 1] \
  [gt_pin_nets $channel GTRXRESET 1] \
  [gt_pin_nets $channel RXUSERRDY 1]]
set tx_control [concat \
  [gt_pin_nets $channel TXRESETDONE 1] \
  [gt_pin_nets $channel TXELECIDLE 1] \
  [gt_pin_nets $channel TXDETECTRX 1]]

create_debug_core u_ila_xdma_rx ila
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_xdma_rx]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_xdma_rx]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_xdma_rx]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_xdma_rx]
connect_debug_port u_ila_xdma_rx/clk $user_clk_net
add_ila_probe u_ila_xdma_rx 0 [lrange $rx_status 0 0]
add_ila_probe u_ila_xdma_rx 1 $rx_status
add_ila_probe u_ila_xdma_rx 2 $rx_control
add_ila_probe u_ila_xdma_rx 3 $tx_control

puts "G5_XDMA_ILA_INSERT_PASS rx_status_width=[llength $rx_status] rx_control_width=[llength $rx_control] tx_control_width=[llength $tx_control]"

implement_debug_core
place_design
phys_opt_design
route_design
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $build_dir xdma_x1_rx_ila_routed.dcp]
report_timing_summary -delay_type min_max -file [file join $build_dir timing_summary.rpt]
report_drc -file [file join $build_dir drc.rpt]
write_debug_probes -force $ltx_path
write_bitstream -force $bit_path
puts "G5_XDMA_ILA_BUILD_PASS bitstream=$bit_path probes=$ltx_path"
close_design
