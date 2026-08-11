set script_dir [file dirname [file normalize [info script]]]
set standalone_dcp [file join $script_dir build_k11b2_ila impl k11b2_routed.dcp]
set xdma_dcp [file join $script_dir xdma_x1_demo build example xdma_x1_ex \
  xdma_x1_ex.runs impl_1 xilinx_dma_pcie_ep_routed.dcp]

proc collect_gt_properties {dcp label} {
  if {![file exists $dcp]} { error "$label DCP不存在：$dcp" }
  open_checkpoint $dcp
  set channels [get_cells -hier -quiet -filter {REF_NAME == GTHE3_CHANNEL}]
  if {[llength $channels] != 1} {
    error "$label期望一个GTHE3_CHANNEL，实际[llength $channels]"
  }
  set channel [lindex $channels 0]
  puts "G4_GT_CELL label=$label cell=$channel loc=[get_property LOC $channel]"
  set result [dict create]
  foreach property [list_property $channel] {
    if {![catch {set value [get_property $property $channel]}] && $value ne ""} {
      dict set result $property $value
    }
  }
  foreach pin_name {
    GTRXRESET RXUSERRDY RXPMARESET RXPCSRESET RXBUFRESET
    RXCDRFREQRESET RXCDRHOLD RXCDROVRDEN RXCDRRESET
    RXDFELPMRESET RXDLYSRESET RXPHALIGN RXPHALIGNEN
    RX8B10BEN RXCOMMADETEN RXMCOMMAALIGNEN RXPCOMMAALIGNEN
    RXLPMEN RXDFEAGCCTRL RXRATE RXPD RXPOLARITY RXELECIDLEMODE
    RXPRBSCNTRESET RXPRBSSEL LOOPBACK
    GTTXRESET TXUSERRDY TXPMARESET TXPCSRESET TXPROGDIVRESET
    TX8B10BEN TXRATE TXPD TXPOLARITY TXELECIDLE TXDETECTRX
    TXDEEMPH TXDIFFCTRL TXMAINCURSOR TXPOSTCURSOR TXPRECURSOR
    TXDATA TXCTRL0 TXCTRL1 TXCTRL2
  } {
    set pin [get_pins -quiet ${channel}/${pin_name}]
    if {[llength $pin] != 1} {
      puts "G4_GT_PIN label=$label pin=$pin_name state=MISSING"
      continue
    }
    set net [get_nets -quiet -of_objects $pin]
    set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
    set ports [get_ports -quiet -of_objects $net]
    puts "G4_GT_PIN label=$label pin=$pin_name net={$net} drivers={$drivers} ports={$ports}"
  }
  close_design
  return $result
}

set standalone [collect_gt_properties $standalone_dcp STANDALONE]
set xdma [collect_gt_properties $xdma_dcp XDMA]
set all_properties [lsort -unique [concat [dict keys $standalone] [dict keys $xdma]]]
set difference_count 0
foreach property $all_properties {
  set standalone_value "<missing>"
  set xdma_value "<missing>"
  if {[dict exists $standalone $property]} {
    set standalone_value [dict get $standalone $property]
  }
  if {[dict exists $xdma $property]} {
    set xdma_value [dict get $xdma $property]
  }
  if {$standalone_value ne "<missing>" && $xdma_value ne "<missing>" &&
      $standalone_value ne $xdma_value} {
    incr difference_count
    puts "G4_GT_DIFF property=$property standalone={$standalone_value} xdma={$xdma_value}"
  }
}
puts "G4_GT_COMPARE_PASS differences=$difference_count"
