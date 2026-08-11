set script_dir [file dirname [file normalize [info script]]]
set dcp_path [file join $script_dir xdma_x1_demo build example xdma_x1_ex \
  xdma_x1_ex.runs impl_1 xilinx_dma_pcie_ep_opt.dcp]
if {![file exists $dcp_path]} { error "G5 XDMA opt DCP不存在：$dcp_path" }

open_checkpoint $dcp_path
set channels [get_cells -hierarchical -quiet -filter {REF_NAME == GTHE3_CHANNEL}]
if {[llength $channels] != 1} {
  error "G5期望唯一GTHE3_CHANNEL，实际[llength $channels]"
}
set channel [lindex $channels 0]
puts "G5_XDMA_GT cell=$channel loc=[get_property LOC $channel]"

foreach pin_name {
  RXRESETDONE RXELECIDLE RXVALID RXSTATUS RXDATA RXCTRL0
  RXCDRHOLD RXRATE RXPD RXPOLARITY RX8B10BEN GTRXRESET RXUSERRDY
  TXRESETDONE TXELECIDLE TXDETECTRX TXPD TXRATE
} {
  set pin [get_pins -quiet ${channel}/${pin_name}]
  if {[llength $pin] != 1} {
    puts "G5_XDMA_PIN pin=$pin_name state=MISSING"
    continue
  }
  set nets [lsort -dictionary [get_nets -quiet -of_objects $pin]]
  puts "G5_XDMA_PIN pin=$pin_name nets={$nets}"
}

foreach pattern {
  .*phy_pclk.*
  .*user_clk.*
  .*rxresetdone_out.*
  .*rxelecidle_out.*
  .*rxvalid_out.*
  .*rxstatus_out.*
  .*rxcdrhold_in.*
  .*rxrate_in.*
  .*rxpd_in.*
  .*rxpolarity_in.*
  .*rx8b10ben_in.*
} {
  set matches [lsort -dictionary [get_nets -hierarchical -quiet -regexp $pattern]]
  puts "G5_XDMA_NET pattern={$pattern} count=[llength $matches]"
  foreach net [lrange $matches 0 11] { puts "  $net" }
}
close_design
puts "G5_XDMA_RX_NET_REPORT_PASS"
