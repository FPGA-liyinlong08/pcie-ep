set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k08]
set part_name   xcku040-ffva1156-2-e
file mkdir $build_dir

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/tl/pcie_cfg_space.sv]
read_verilog -sv [file join $project_dir rtl/tl/k08_cfg_space_ooc_top.sv]
read_xdc [file join $script_dir k08_cfg_space_ooc.xdc]

synth_design -mode out_of_context -top k08_cfg_space_ooc_top -part $part_name

write_checkpoint -force [file join $build_dir k08_cfg_space_ooc.dcp]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} { error "K08 OOC找不到最大延迟路径" }
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} { error "K08 OOC 250 MHz时序失败：WNS=$wns" }

set worst_hold_path [get_timing_paths -delay_type min -max_paths 1]
if {[llength $worst_hold_path] != 1} { error "K08 OOC找不到最小延迟路径" }
set whs [get_property SLACK $worst_hold_path]
if {$whs < 0.0} { error "K08 OOC Hold时序失败：WHS=$whs" }

# K09依赖的配置状态和K07响应必须保留真实寄存器扇入，不能被综合网表常量替代。
proc assert_dynamic_output {port_name} {
    set starts [all_fanin -flat -startpoints_only -to [get_ports $port_name]]
    set sequential_count 0
    foreach start $starts {
        if {[get_property -quiet CLASS $start] eq "pin"} {
            set owner [get_cells -quiet -of_objects $start]
            if {[llength $owner] == 1 &&
                [string match "FD*" [get_property REF_NAME $owner]]} {
                incr sequential_count
            }
        }
    }
    if {$sequential_count < 1} {
        error "K08输出${port_name}没有寄存器扇入：$starts"
    }
    return $sequential_count
}

set rsp_dynamic [assert_dynamic_output cfg_rsp_valid]
set bdf_dynamic [assert_dynamic_output captured_bdf]
set bar_dynamic [assert_dynamic_output bar0_base]
set mse_dynamic [assert_dynamic_output memory_space_enable]

set lut_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ FD*}]]
set bram_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ RAMB*}]]
set dsp_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP*}]]
set pcie_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ PCIE*}]]
if {$bram_count != 0 || $dsp_count != 0 || $pcie_count != 0} {
    error "K08出现禁止资源：BRAM=$bram_count DSP=$dsp_count PCIE=$pcie_count"
}

set summary_file [open [file join $build_dir summary.txt] w]
puts $summary_file "K08_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "WNS=$wns"
puts $summary_file "TNS=0.000"
puts $summary_file "WHS=$whs"
puts $summary_file "THS=0.000"
puts $summary_file "TIMING_FAIL_ENDPOINTS=0"
puts $summary_file "CFG_RSP_DYNAMIC=$rsp_dynamic"
puts $summary_file "BDF_DYNAMIC=$bdf_dynamic"
puts $summary_file "BAR0_DYNAMIC=$bar_dynamic"
puts $summary_file "MSE_DYNAMIC=$mse_dynamic"
puts $summary_file "LUT_PRIMITIVES=$lut_count"
puts $summary_file "FF=$ff_count"
puts $summary_file "BRAM=$bram_count"
puts $summary_file "DSP=$dsp_count"
puts $summary_file "PCIE_HARD_BLOCK=$pcie_count"
close $summary_file
puts "K08_VIVADO_PASS WNS=$wns WHS=$whs LUT=$lut_count FF=$ff_count"
