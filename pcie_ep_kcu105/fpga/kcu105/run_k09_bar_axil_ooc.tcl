set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k09]
set part_name   xcku040-ffva1156-2-e
set top_name    k09_bar_axil_ooc_top
file mkdir $build_dir
# Tcl只生成候选摘要。外层Shell完成Warning、route/check_timing、CDC和DRC
# 全部门禁后才原子发布summary.txt，失败运行不能遗留假PASS。
file delete -force [file join $build_dir summary_candidate.txt]

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/tl/pcie_bar_axil_master.sv]
read_verilog -sv [file join $project_dir rtl/tl/k09_bar_axil_ooc_top.sv]
read_xdc [file join $script_dir k09_bar_axil_ooc.xdc]

synth_design -mode out_of_context -top $top_name -part $part_name

# 这些约束仅对已综合网表生效，避免Vivado把implementation-only命令拆进
# 临时propImpl XDC并丢失局部Tcl变量。
read_xdc -mode out_of_context \
    [file join $script_dir k09_bar_axil_ooc_impl.xdc]

# 只给连接真实动态net的边界端口设置partition pin。常量输出连接<const0/1>，
# 已优化输入没有net；两类端口若被强制设置PARTPIN会令GLOBAL_LOGIC0/1出现
# unplaced-pin routing error。
set partpin_ports {}
foreach boundary_port [get_ports -quiet -filter {NAME != clk}] {
    set boundary_nets [get_nets -quiet -of_objects $boundary_port]
    set has_dynamic_net 0
    foreach boundary_net $boundary_nets {
        if {![string match "<const*>" $boundary_net]} {
            set has_dynamic_net 1
        }
    }
    if {$has_dynamic_net} {
        lappend partpin_ports $boundary_port
    }
}
if {[llength $partpin_ports] == 0} {
    error "K09 OOC没有找到可路由的动态边界端口"
}
set_property HD.PARTPIN_RANGE {SLICE_X76Y60:SLICE_X100Y119} $partpin_ports
set partpin_port_count [llength $partpin_ports]

# K09最终与PHY core clock同域集成。把生产逻辑和OOC复位链约束在K03实际
# BUFG_GT_X0Y26所在Clock Region X3Y1，保证布局上下文和partition-pin范围一致。
create_pblock pblock_k09_core_x3y1
resize_pblock [get_pblocks pblock_k09_core_x3y1] -add \
    {SLICE_X76Y60:SLICE_X100Y119}
add_cells_to_pblock [get_pblocks pblock_k09_core_x3y1] -top

write_checkpoint -force [file join $build_dir k09_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
write_checkpoint -force [file join $build_dir k09_placed.dcp]
route_design
write_checkpoint -force [file join $build_dir k09_routed.dcp]

report_route_status -file [file join $build_dir route_status.rpt]
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]
report_drc -file [file join $build_dir drc.rpt]

set worst_setup_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_setup_path] != 1} {
    error "K09 OOC找不到最大延迟路径"
}
set wns [get_property SLACK $worst_setup_path]
if {$wns < 0.0} {
    error "K09 OOC Route后250 MHz Setup失败：WNS=$wns"
}

set worst_hold_path [get_timing_paths -delay_type min -max_paths 1]
if {[llength $worst_hold_path] != 1} {
    error "K09 OOC找不到最小延迟路径"
}
set whs [get_property SLACK $worst_hold_path]
if {$whs < 0.0} {
    error "K09 OOC Route后Hold失败：WHS=$whs"
}

# 单独证明生产逻辑内部FF-to-FF的setup/hold均通过；输入侧用
# max-delay 4 ns减去1 ns input/output delay，两向都留出3 ns净数据预算。
set all_regs [all_registers]
set internal_setup_path [get_timing_paths -delay_type max -max_paths 1 \
    -from $all_regs -to $all_regs]
if {[llength $internal_setup_path] != 1} {
    error "K09 OOC找不到内部FF-to-FF setup路径"
}
set internal_wns [get_property SLACK $internal_setup_path]

set internal_hold_path [get_timing_paths -delay_type min -max_paths 1 \
    -from $all_regs -to $all_regs]
if {[llength $internal_hold_path] != 1} {
    error "K09 OOC找不到内部FF-to-FF hold路径"
}
set internal_whs [get_property SLACK $internal_hold_path]
if {$internal_wns < 0.0 || $internal_whs < 0.0} {
    error "K09 OOC内部时序失败：WNS=$internal_wns WHS=$internal_whs"
}

set sync_input_ports [get_ports -filter {
    DIRECTION == IN && NAME != clk && NAME != rst_n
}]
set sync_output_ports [get_ports -filter {
    DIRECTION == OUT
}]
set input_setup_path [get_timing_paths -delay_type max -max_paths 1 \
    -from $sync_input_ports -to $all_regs]
if {[llength $input_setup_path] != 1} {
    error "K09 OOC找不到接口input setup路径"
}
set input_max_slack [get_property SLACK $input_setup_path]
set input_data_delay [get_property DATAPATH_DELAY $input_setup_path]

set output_setup_path [get_timing_paths -delay_type max -max_paths 1 \
    -from $all_regs -to $sync_output_ports]
if {[llength $output_setup_path] != 1} {
    error "K09 OOC找不到接口output setup路径"
}
set output_max_slack [get_property SLACK $output_setup_path]
set output_data_delay [get_property DATAPATH_DELAY $output_setup_path]

set input_hold_path [get_timing_paths -delay_type min -max_paths 1 \
    -from $sync_input_ports -to $all_regs]
if {[llength $input_hold_path] != 1} {
    error "K09 OOC找不到接口input hold路径"
}
set input_hold_slack [get_property SLACK $input_hold_path]
set input_min_data_delay [get_property DATAPATH_DELAY $input_hold_path]

set output_hold_path [get_timing_paths -delay_type min -max_paths 1 \
    -from $all_regs -to $sync_output_ports]
if {[llength $output_hold_path] != 1} {
    error "K09 OOC找不到接口output hold路径"
}
set output_hold_slack [get_property SLACK $output_hold_path]
set output_min_data_delay [get_property DATAPATH_DELAY $output_hold_path]
if {$input_max_slack < 0.0 || $output_max_slack < 0.0} {
    error "K09 OOC接口max-delay预算失败：input=$input_max_slack output=$output_max_slack"
}
if {$input_hold_slack < 0.0 || $output_hold_slack < 0.0} {
    error "K09 OOC接口min-delay失败：input=$input_hold_slack output=$output_hold_slack"
}

report_timing -delay_type max -max_paths 20 -from $sync_input_ports \
    -to $all_regs -file [file join $build_dir timing_interface_input.rpt]
report_timing -delay_type max -max_paths 20 -from $all_regs \
    -to $sync_output_ports \
    -file [file join $build_dir timing_interface_output.rpt]
report_timing -delay_type min -max_paths 20 -from $sync_input_ports \
    -to $all_regs -file [file join $build_dir timing_interface_input_hold.rpt]
report_timing -delay_type min -max_paths 20 -from $all_regs \
    -to $sync_output_ports \
    -file [file join $build_dir timing_interface_output_hold.rpt]
report_timing -delay_type max -max_paths 20 -from $all_regs -to $all_regs \
    -file [file join $build_dir timing_internal_setup.rpt]
report_timing -delay_type min -max_paths 20 -from $all_regs -to $all_regs \
    -file [file join $build_dir timing_internal_hold.rpt]

# 防止OOC边界或后续改动把关键状态机输出裁成常量。
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
        error "K09输出${port_name}没有寄存器扇入：$starts"
    }
    return $sequential_count
}

set busy_dynamic [assert_dynamic_output busy]
set aw_dynamic   [assert_dynamic_output m_axil_awvalid]
set ar_dynamic   [assert_dynamic_output m_axil_arvalid]
set cpl_dynamic  [assert_dynamic_output cpl_req_valid]
set data_dynamic [assert_dynamic_output cpl_data_valid]

set lut_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ FD*}]]
set bram_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ RAMB*}]]
set dsp_count [llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP*}]]
set pcie_count [llength [get_cells -quiet -hierarchical -filter {
    REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$dsp_count != 0 || $pcie_count != 0} {
    error "K09出现禁止资源：DSP=$dsp_count PCIE=$pcie_count"
}

set summary_file [open [file join $build_dir summary_candidate.txt] w]
puts $summary_file "K09_VIVADO_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "top=$top_name"
puts $summary_file "IMPLEMENTATION=ROUTED"
puts $summary_file "WNS=$wns"
puts $summary_file "TNS=0.000"
puts $summary_file "WHS=$whs"
puts $summary_file "THS=0.000"
puts $summary_file "TIMING_FAIL_SETUP=0"
puts $summary_file "TIMING_FAIL_HOLD=0"
puts $summary_file "IO_DELAY_MAX_NS=1.000"
puts $summary_file "INPUT_TOTAL_MAX_NS=4.000"
puts $summary_file "INPUT_EFFECTIVE_DATA_BUDGET_NS=3.000"
puts $summary_file "OUTPUT_TOTAL_MAX_NS=4.000"
puts $summary_file "OUTPUT_EFFECTIVE_DATA_BUDGET_NS=3.000"
puts $summary_file "INTERFACE_INPUT_MIN_DELAY_NS=-1.000"
puts $summary_file "INTERFACE_OUTPUT_MIN_DELAY_NS=0.000"
puts $summary_file "INTERFACE_INPUT_SETUP_SLACK=$input_max_slack"
puts $summary_file "INTERFACE_OUTPUT_SETUP_SLACK=$output_max_slack"
puts $summary_file "INTERFACE_INPUT_DATA_PATH_NS=$input_data_delay"
puts $summary_file "INTERFACE_OUTPUT_DATA_PATH_NS=$output_data_delay"
puts $summary_file "INTERFACE_INPUT_HOLD_SLACK=$input_hold_slack"
puts $summary_file "INTERFACE_OUTPUT_HOLD_SLACK=$output_hold_slack"
puts $summary_file "INTERFACE_INPUT_MIN_DATA_PATH_NS=$input_min_data_delay"
puts $summary_file "INTERFACE_OUTPUT_MIN_DATA_PATH_NS=$output_min_data_delay"
puts $summary_file "INTERNAL_WNS=$internal_wns"
puts $summary_file "INTERNAL_WHS=$internal_whs"
puts $summary_file "BUSY_DYNAMIC=$busy_dynamic"
puts $summary_file "AXI_AWVALID_DYNAMIC=$aw_dynamic"
puts $summary_file "AXI_ARVALID_DYNAMIC=$ar_dynamic"
puts $summary_file "CPL_REQ_VALID_DYNAMIC=$cpl_dynamic"
puts $summary_file "CPL_DATA_VALID_DYNAMIC=$data_dynamic"
puts $summary_file "LUT_PRIMITIVES=$lut_count"
puts $summary_file "FF=$ff_count"
puts $summary_file "BRAM=$bram_count"
puts $summary_file "DSP=$dsp_count"
puts $summary_file "PCIE_HARD_BLOCK=$pcie_count"
puts $summary_file "PARTPIN_DYNAMIC_PORTS=$partpin_port_count"
close $summary_file

puts "K09_VIVADO_PASS WNS=$wns WHS=$whs LUT=$lut_count FF=$ff_count BRAM=$bram_count"
