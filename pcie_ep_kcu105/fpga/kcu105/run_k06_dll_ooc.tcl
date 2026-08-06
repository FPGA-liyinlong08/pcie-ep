set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k06]
set part_name   xcku040-ffva1156-2-e
file mkdir $build_dir

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_crc_stream.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_crc16_dllp.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_crc32_lcrc.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_dllp_codec.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_fc_local_credit_pool.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_dllp_fc_manager.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_dll_replay.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_dllp_tx_arbiter.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_dll_mac_tx_arbiter.sv]
read_verilog -sv [file join $project_dir rtl/dll/pcie_dll.sv]
read_verilog -sv [file join $project_dir rtl/dll/k06_dll_ooc_top.sv]
read_xdc [file join $script_dir k06_dll_ooc.xdc]

synth_design -mode out_of_context -top k06_dll_ooc_top -part $part_name

write_checkpoint -force [file join $build_dir k06_dll_ooc.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} { error "K06 OOC找不到最大延迟路径" }
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} { error "K06 OOC 250 MHz时序失败：WNS=$wns" }

set lut_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ FD*}]]
set bram_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ RAMB*}]]
set dsp_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP*}]]
set pcie_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ PCIE*}]]
if {$dsp_count != 0 || $pcie_count != 0} {
    error "K06出现禁止资源：DSP=$dsp_count PCIE=$pcie_count"
}

set summary_file [open [file join $build_dir summary.txt] w]
puts $summary_file "K06_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "WNS=$wns"
puts $summary_file "LUT_PRIMITIVES=$lut_count"
puts $summary_file "FF=$ff_count"
puts $summary_file "BRAM=$bram_count"
puts $summary_file "DSP=$dsp_count"
puts $summary_file "PCIE_HARD_BLOCK=$pcie_count"
close $summary_file
puts "K06_VIVADO_PASS WNS=$wns LUT=$lut_count FF=$ff_count BRAM=$bram_count"
