set script_dir [file dirname [file normalize [info script]]]
set dcp_path [file join $script_dir build_k11b2_ila impl k11b2_routed.dcp]
if {![file exists $dcp_path]} { error "G3 DCP不存在：$dcp_path" }

open_checkpoint $dcp_path
foreach suffix {
  gt_rxresetdone
  rxresetdone_out
  gt_rxpmaresetdone
  rxpmaresetdone_out
  gt_rxcdrlock
  rxcdrlock
  rxcdrlock_out
  rxbyteisaligned
  rxbyteisaligned_out
  rxbyterealign
  rxbyterealign_out
  rxcommadet
  rxcommadet_out
  rxelecidle
  rxelecidle_out
  rxvalid
  rxvalid_out
  rxstatus_out
  rxdata_out
  rxctrl0_out
  rxctrl1_out
  rxctrl2_out
  rxctrl3_out
  gtrxreset_in
  rxuserrdy_in
  rxcdrhold_in
  rxlpmen_in
  rxrate_in
  rxpd_in
  rxpolarity_in
  rx8b10ben_in
} {
  set matches [lsort -dictionary [get_nets -hierarchical -quiet -regexp ".*${suffix}.*"]]
  puts "G3_NET suffix=$suffix count=[llength $matches]"
  foreach net [lrange $matches 0 4] { puts "  $net" }
}
close_design
