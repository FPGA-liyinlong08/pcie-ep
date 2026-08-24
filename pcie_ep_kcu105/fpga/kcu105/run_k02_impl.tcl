set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set xci_path    [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.xci]
set part_name   xcku040-ffva1156-2-e
set top_name    kcu105_pcie_phy_bringup_top
set build_dir   [file join $script_dir build_k02]
set bit_stem    k02_pcie_phy_bringup_ila
set k02_wait_after_ready_ns [expr {[info exists ::env(K02_PHY_CTRL_WAIT_AFTER_READY_NS)] ?
                                   $::env(K02_PHY_CTRL_WAIT_AFTER_READY_NS) : 10000}]

# K02 顶层直接实例化 Golden `phy_ctrl.v` + `phy_bringup_seq`，独立完成
# Gen1->Gen3 切换。K02 顶层无参数化 K02_USE_PHY_CTRL 路径、无 DYNAMIC_*
# FSM、无 A/B Test 3 变量。K02_PHY_CTRL_*_NS 在 RTL param 已有默认值，
# 不通过 -generic 覆盖。
set k02_ila_debug [expr {![info exists ::env(K02_ILA_DEBUG)] ||
                          $::env(K02_ILA_DEBUG) eq "1"}]

file mkdir $build_dir

if {![file exists $xci_path]} {
    error "K02 XCI 不存在，请先执行 make k02-ip：$xci_path"
}

set_part $part_name
read_ip $xci_path
generate_target all [get_ips pcie_phy_x1_gen3]
# `synth_ip -force` 在 Vivado 2021.2 仍不会覆盖已有的同名 OOC DCP。
# 仅删除本 IP 的确定目标，保证脚本可重复执行且真实执行一次 OOC 综合。
set ip_dcp [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.dcp]
if {[file exists $ip_dcp]} {
    file delete -force $ip_dcp
}
synth_ip -force [get_ips pcie_phy_x1_gen3]

read_verilog -sv [file join $project_dir rtl/common/pcie_reset_sync.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_reset_ctrl.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_refclk_reset.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_pcie_phy_wrapper.sv]
# Golden controller 移植到 K02 顶层。读顺序：底层 -> 顶层。
# phy_ctrl.v 内部实例化 pat_gen，因此 pat_gen 必须先读。
read_verilog     [file join $project_dir rtl/phy/phy_ctrl_pat_gen_lane.v]
read_verilog     [file join $project_dir rtl/phy/phy_ctrl_pat_gen.v]
read_verilog     [file join $project_dir rtl/phy/phy_ctrl.v]
read_verilog -sv [file join $project_dir rtl/phy/phy_bringup_seq.sv]
read_verilog -sv [file join $project_dir rtl/phy/k02_phy_event_recorder.sv]
read_verilog -sv [file join $project_dir rtl/phy/kcu105_pcie_phy_bringup_top.sv]
read_xdc [file join $script_dir k02_pcie_phy_bringup.xdc]

synth_design -top $top_name -part $part_name \
    -generic K02_PHY_CTRL_WAIT_AFTER_READY_NS=$k02_wait_after_ready_ns

if {$k02_ila_debug} {
    # K02 standalone PHY 没有协议层 ILA；这里直接从综合网表中的 GT Wizard
    # 网络/primitive pin 建立一个同一 phy_pclk 域的诊断 ILA。所有连接失败
    # 都让构建失败，避免生成"看似有 ILA、实际没有 QPLL1LOCK"的假 bit。
    proc k02_net {regexp_pattern} {
        set nets [get_nets -hierarchical -quiet -regexp $regexp_pattern]
        if {[llength $nets] != 1} {
            error "K02 ILA网络不存在或不唯一：$regexp_pattern，实际[llength $nets]，候选=[join $nets { | }]"
        }
        set_property MARK_DEBUG TRUE $nets
        return $nets
    }
    proc k02_primitive_pin {cell_ref ref_pin} {
        set cells [get_cells -hierarchical -quiet -filter "REF_NAME == $cell_ref"]
        if {[llength $cells] != 1} {
            error "K02 ILA primitive不存在或不唯一：$cell_ref，实际[llength $cells]"
        }
        set pins [get_pins -quiet -of_objects [lindex $cells 0] \
                    -filter "REF_PIN_NAME == $ref_pin"]
        if {[llength $pins] != 1} {
            error "K02 ILA primitive pin不存在或不唯一：$cell_ref/$ref_pin，实际[llength $pins]"
        }
        set nets [get_nets -quiet -of_objects $pins]
        if {[llength $nets] != 1} {
            error "K02 ILA primitive pin无唯一网络：$cell_ref/$ref_pin"
        }
        set_property MARK_DEBUG TRUE $nets
        return $nets
    }
    proc k02_primitive_bus_pin {cell_ref ref_pin expected_width} {
        set cells [get_cells -hierarchical -quiet -filter "REF_NAME =~ ${cell_ref}*"]
        if {[llength $cells] != 1} {
            error "K02 ILA primitive不存在或不唯一：$cell_ref，实际[llength $cells]"
        }
        set pin_pairs {}
        foreach pin [get_pins -quiet -of_objects [lindex $cells 0]] {
            set ref_pin_name [get_property REF_PIN_NAME $pin]
            if {[regexp "^${ref_pin}\\\[[0-9]+\\\]$" $ref_pin_name]} {
                set pin_nets [get_nets -quiet -of_objects $pin]
                if {[llength $pin_nets] != 1} {
                    error "K02 ILA primitive端口无唯一网络：$cell_ref/$ref_pin_name"
                }
                lappend pin_pairs [list $ref_pin_name [lindex $pin_nets 0]]
            }
        }
        set pin_pairs [lsort -dictionary -index 0 $pin_pairs]
        set nets {}
        foreach pin_pair $pin_pairs {
            lappend nets [lindex $pin_pair 1]
        }
        if {[llength $nets] != $expected_width} {
            error "K02 ILA primitive总线位宽错误：$cell_ref/$ref_pin，实际[llength $nets]，期望$expected_width"
        }
        set_property MARK_DEBUG TRUE $nets
        return $nets
    }
    proc k02_bus {regexp_pattern expected_width} {
        set nets [lsort -dictionary [get_nets -hierarchical -quiet -regexp $regexp_pattern]]
        if {[llength $nets] != $expected_width} {
            error "K02 ILA总线宽度错误：$regexp_pattern，实际[llength $nets]，期望$expected_width"
        }
        set_property MARK_DEBUG TRUE $nets
        return $nets
    }
    proc k02_add_probe {core_name probe_index nets} {
        if {$probe_index != 0} { create_debug_port $core_name probe }
        set port [get_debug_ports ${core_name}/probe${probe_index}]
        set_property port_width [llength $nets] $port
        connect_debug_port $port $nets
    }

    proc k02_connect_recorder_input {pin_pattern source_net} {
        set pins [get_pins -hierarchical -quiet -regexp $pin_pattern]
        if {[llength $pins] != 1} {
            error "K02 event recorder输入不存在或不唯一：$pin_pattern，实际[llength $pins]"
        }
        set pin [lindex $pins 0]
        set old_nets [get_nets -quiet -of_objects $pin]
        # The GT Wizard marks primitive output nets DONT_TOUCH.  Clear that
        # implementation-only property before retargeting the recorder tap;
        # otherwise Vivado reports success but leaves the recorder input on
        # its synthesized constant net.
        set_property DONT_TOUCH FALSE [get_nets -quiet -of_objects $pin]
        set_property DONT_TOUCH FALSE [get_nets -quiet $source_net]
        if {[llength $old_nets] == 1} {
            disconnect_net -net [lindex $old_nets 0] -pinlist [list $pin]
        }
        connect_net -hier -net $source_net -objects [list $pin]
    }

    # 将 recorder 的两个 GT 输入直接接到 primitive pin 网络。这样记录器
    # 看到的是实际 QPLL1LOCK/QPLL1RESET，而不是 wrapper 的替代/常量端口。
    set k02_qpll1lock_net  [k02_primitive_pin GTHE3_COMMON QPLL1LOCK]
    set k02_qpll1reset_net [k02_primitive_pin GTHE3_COMMON QPLL1RESET]
    k02_connect_recorder_input {^u_k02_event_recorder/qpll1lock$}  $k02_qpll1lock_net
    k02_connect_recorder_input {^u_k02_event_recorder/qpll1reset$} $k02_qpll1reset_net

    create_debug_core u_ila_k02 ila
    set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_k02]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_k02]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_k02]
    set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_k02]
    connect_debug_port u_ila_k02/clk [k02_net {(^|/)phy_pclk$}]

    # probe0 = GT 关键 pin + phy_ctrl 关键输出。
    set k02_probe0 [concat \
        [k02_primitive_pin GTHE3_COMMON QPLL1LOCK] \
        [k02_primitive_pin GTHE3_COMMON QPLL1RESET] \
        [k02_bus {^phy_rate_cmd\[[0-1]\]$} 2] \
        [k02_bus {^phy_powerdown\[[0-1]\]$} 2] \
        [k02_net {^phy_txelecidle_cmd$}] \
        [k02_bus {^phy_ctrl_debug_state_w\[[0-7]\]$} 8] \
        [k02_net {^as_mac_in_detect_cmd$}] \
        [k02_net {^as_cdr_hold_cmd$}] \
        [k02_primitive_bus_pin GTHE3_CHANNEL PCIERATEQPLLRESET 2] \
        [k02_primitive_pin GTHE3_CHANNEL PCIERATEGEN3] \
        [k02_primitive_pin GTHE3_CHANNEL PCIEUSERGEN3RDY] \
        [k02_primitive_pin GTHE3_COMMON QPLL1REFCLKLOST] \
        [k02_primitive_pin GTHE3_COMMON QPLL1FBCLKLOST]]
    k02_add_probe u_ila_k02 0 $k02_probe0

    # probe1 = phy_bringup_seq 进度 + phy_phystatus 边沿。
    set k02_probe1 [concat \
        [k02_bus {^seq_state_w\[[0-3]\]$} 4] \
        [k02_net {^gen3_request_w$}] \
        [k02_net {^tx_elec_idle_w$}] \
        [k02_net {^phy_ready_en_w$}] \
        [k02_net {^gen1_en_w$}] \
        [k02_net {^gen3_en_w$}] \
        [k02_net {^u_phy_wrapper/phy_phystatus$}] \
        [k02_net {^u_phy_wrapper/phy_phystatus_rst$}]]
    k02_add_probe u_ila_k02 1 $k02_probe1

    # probe2 = rate-change事件记录器：所有时间戳相对于本次QPLL reset/rate
    # change开始，避免依赖单个8192点窗口覆盖完整80 us流程。
    set k02_probe2 [k02_bus {^k02_event_record_w\[[0-9]+\]$} 118]
    k02_add_probe u_ila_k02 2 $k02_probe2

    puts "K02_PHY_ILA_INSERT_PASS probe0_width=[llength $k02_probe0] probe1_width=[llength $k02_probe1] probe2_width=[llength $k02_probe2] depth=8192"
}
write_checkpoint -force [file join $build_dir k02_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
write_checkpoint -force [file join $build_dir k02_placed.dcp]
route_design
write_checkpoint -force [file join $build_dir k02_routed.dcp]

report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc_routed.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_pin {port_name expected_pin} {
    set port_object [get_ports $port_name]
    if {[llength $port_object] != 1} {
        error "K02 顶层端口不存在：$port_name"
    }
    set actual_pin [get_property PACKAGE_PIN $port_object]
    if {![string equal -nocase $actual_pin $expected_pin]} {
        error "K02 管脚错误：$port_name=$actual_pin，期望 $expected_pin"
    }
}

require_port_pin pcie_refclk_p AB6
require_port_pin pcie_refclk_n AB5
require_port_pin pcie_perst_n  K22
require_port_pin pcie_rxp      AB2
require_port_pin pcie_rxn      AB1
require_port_pin pcie_txp      AC4
require_port_pin pcie_txn      AC3

set gth_channels [get_cells -hierarchical -filter {REF_NAME == GTHE3_CHANNEL}]
set gth_commons  [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1} {
    error "K02 GTHE3_CHANNEL 数量为 [llength $gth_channels]，期望 1"
}
if {[llength $gth_commons] != 1} {
    error "K02 GTHE3_COMMON 数量为 [llength $gth_commons]，期望 1"
}

set channel_loc [get_property LOC $gth_channels]
set common_loc  [get_property LOC $gth_commons]
if {![string equal -nocase $channel_loc GTHE3_CHANNEL_X0Y7]} {
    error "K02 GT Channel LOC=$channel_loc，期望 GTHE3_CHANNEL_X0Y7"
}
if {![string equal -nocase $common_loc GTHE3_COMMON_X0Y1]} {
    error "K02 GT Common LOC=$common_loc，期望 GTHE3_COMMON_X0Y1"
}

set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
    REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} {
    error "K02 错误实例化 PCIe Hard Block，数量 $hard_pcie_count"
}

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} {
    error "K02 找不到可分析的最大延迟路径"
}
set wns [get_property SLACK $worst_path]
if {$wns < 0.0} {
    error "K02 Route 后时序失败：WNS=$wns"
}

set bit_name [expr {$k02_ila_debug ? "${bit_stem}.bit" :
                                      "${bit_stem}.bit"}]
write_bitstream -force [file join $build_dir $bit_name]
if {$k02_ila_debug} {
    write_debug_probes -force [file join $build_dir ${bit_stem}.ltx]
}

set summary_path [file join $build_dir impl_summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "K02_IMPL_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "top=$top_name"
puts $summary_file "GTHE3_CHANNEL_COUNT=[llength $gth_channels]"
puts $summary_file "GTHE3_CHANNEL_LOC=$channel_loc"
puts $summary_file "GTHE3_COMMON_COUNT=[llength $gth_commons]"
puts $summary_file "GTHE3_COMMON_LOC=$common_loc"
puts $summary_file "PCIE_HARD_BLOCK_COUNT=$hard_pcie_count"
puts $summary_file "WNS=$wns"
puts $summary_file "WAIT_AFTER_READY_NS=$k02_wait_after_ready_ns"
puts $summary_file "K02_ILA_DEBUG=$k02_ila_debug"
puts $summary_file "bitstream=[file join $build_dir $bit_name]"
close $summary_file

puts "K02_IMPL_PASS channel=$channel_loc common=$common_loc WNS=$wns"
