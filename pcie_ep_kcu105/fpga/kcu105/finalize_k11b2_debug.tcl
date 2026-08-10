set script_dir [file dirname [file normalize [info script]]]
set impl_dir  [file join $script_dir build_k11b2 impl]
set dcp_path  [file join $impl_dir k11b2_routed.dcp]
set bit_path  [file join $impl_dir k11b2_gen1_endpoint_debug.bit]

if {![file exists $dcp_path]} {
    error "K11-B2诊断构建缺少已布线DCP：$dcp_path"
}

open_checkpoint $dcp_path
set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths  [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} {
    error "K11-B2诊断构建找不到可分析的最大延迟路径"
}
set wns [get_property SLACK $worst_path]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
    error "K11-B2诊断构建DRC存在Error或Critical Warning"
}

# 此入口只用于硬件根因验证。允许Setup负裕量，但文件名和摘要均与正式镜像隔离。
write_bitstream -force $bit_path
set summary_path [file join $impl_dir debug_summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "K11B2_DEBUG_BITSTREAM_PASS"
puts $summary_file "TIMING_POLICY=DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED"
puts $summary_file "WNS=$wns"
puts $summary_file "SETUP_NEGATIVE=[llength $setup_paths]"
puts $summary_file "HOLD_NEGATIVE=[llength $hold_paths]"
puts $summary_file "bitstream=$bit_path"
close $summary_file
puts "K11B2_DEBUG_BITSTREAM_PASS WNS=$wns bitstream=$bit_path"
close_design
