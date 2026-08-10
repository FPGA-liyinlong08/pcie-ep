set script_dir [file dirname [file normalize [info script]]]
set build_dir [file join $script_dir build_k11a]
set dcp [file join $build_dir routed.dcp]
if {![file exists $dcp]} { error "缺少K11-A routed checkpoint: $dcp" }

open_checkpoint $dcp
set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
  {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
puts "K11A_AFIFO_GRAY_SYNC_CELLS=[llength $afifo_gray_sync_cells]"
if {[llength $afifo_gray_sync_cells] == 0} { error "未找到afifo Gray同步寄存器" }
set_property ASYNC_REG TRUE $afifo_gray_sync_cells
set_property SHREG_EXTRACT NO $afifo_gray_sync_cells
report_timing_summary -delay_type min_max -check_timing_verbose \
  -file [file join $build_dir timing_summary.rpt]
report_cdc -details -from [get_clocks pipe_clk] -to [get_clocks core_clk] \
  -file [file join $build_dir cdc_pipe_to_core.rpt]
report_cdc -details -from [get_clocks core_clk] -to [get_clocks pipe_clk] \
  -file [file join $build_dir cdc_core_to_pipe.rpt]
report_drc -file [file join $build_dir drc.rpt]
report_utilization -file [file join $build_dir utilization_routed.rpt]

if {[llength [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]] != 0} {
  error "K11-A存在setup负时序"
}
if {[llength [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]] != 0} {
  error "K11-A存在hold负时序"
}

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

puts "K11A_VIVADO_REPORT_PASS"
close_design
