set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k07]
set part_name   xcku040-ffva1156-2-e
file mkdir $build_dir

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/tl/pcie_tlp_codec.sv]
read_verilog -sv [file join $project_dir rtl/tl/k07_tlp_codec_ooc_top.sv]
read_xdc [file join $script_dir k07_tlp_codec_ooc.xdc]

synth_design -mode out_of_context -top k07_tlp_codec_ooc_top -part $part_name

write_checkpoint -force [file join $build_dir k07_tlp_codec_ooc.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} { error "K07 OOC找不到最大延迟路径" }
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} { error "K07 OOC 250 MHz时序失败：WNS=$wns" }

set worst_hold_path [get_timing_paths -delay_type min -max_paths 1]
if {[llength $worst_hold_path] != 1} { error "K07 OOC找不到最小延迟路径" }
set whs [get_property SLACK $worst_hold_path]
if {$whs < 0.0} { error "K07 OOC Hold时序失败：WHS=$whs" }
set timing_fail_endpoints 0

# 防止Completion TX状态机在OOC优化中意外被裁成常量。
set tx_valid_startpoints [all_fanin -flat -startpoints_only \
    -to [get_ports tx_tlp_valid]]
set tx_state_start_count 0
foreach tx_start $tx_valid_startpoints {
    set tx_start_name [get_property NAME $tx_start]
    if {[regexp {tx_state_reg\[[01]\]/C$} $tx_start_name]} {
        incr tx_state_start_count
    }
}
if {$tx_state_start_count != 2} {
    error "K07 tx_tlp_valid未由两个tx_state寄存器驱动：$tx_valid_startpoints"
}

set lut_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ FD*}]]
set bram_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ RAMB*}]]
set dsp_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP*}]]
set pcie_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ PCIE*}]]
if {$dsp_count != 0 || $pcie_count != 0} {
    error "K07出现禁止资源：DSP=$dsp_count PCIE=$pcie_count"
}

set summary_file [open [file join $build_dir summary.txt] w]
puts $summary_file "K07_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "WNS=$wns"
puts $summary_file "TNS=0.000"
puts $summary_file "WHS=$whs"
puts $summary_file "THS=0.000"
puts $summary_file "TIMING_FAIL_ENDPOINTS=$timing_fail_endpoints"
puts $summary_file "TX_TLP_VALID_DYNAMIC=1"
puts $summary_file "LUT_PRIMITIVES=$lut_count"
puts $summary_file "FF=$ff_count"
puts $summary_file "BRAM=$bram_count"
puts $summary_file "DSP=$dsp_count"
puts $summary_file "PCIE_HARD_BLOCK=$pcie_count"
close $summary_file
puts "K07_VIVADO_PASS WNS=$wns WHS=$whs LUT=$lut_count FF=$ff_count BRAM=$bram_count"
