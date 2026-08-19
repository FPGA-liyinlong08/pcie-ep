set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set xci_path    [file join $script_dir ip pcie_phy_x1_gen3 pcie_phy_x1_gen3.xci]
set part_name   xcku040-ffva1156-2-e
set top_name    kcu105_pcie_phy_bringup_top

set k02_ila_debug [expr {![info exists ::env(K02_ILA_DEBUG)] ||
                          $::env(K02_ILA_DEBUG) eq "1"}]
set k02_gen3_test [expr {![info exists ::env(K02_GEN3_TEST)] ||
                          $::env(K02_GEN3_TEST) eq "1"}]
set k02_dynamic_rate [expr {[info exists ::env(K02_DYNAMIC_GEN1_TO_GEN3)] &&
                            $::env(K02_DYNAMIC_GEN1_TO_GEN3) eq "1"}]
set k02_coeff_query [expr {[info exists ::env(K02_DYNAMIC_COEFF_QUERY)] &&
                           $::env(K02_DYNAMIC_COEFF_QUERY) eq "1"}]
set k02_off_gap [expr {[info exists ::env(K02_DYNAMIC_GEN1_OFF_GAP)] &&
                       $::env(K02_DYNAMIC_GEN1_OFF_GAP) eq "1"}]
set k02_mac_in_detect_low [expr {[info exists ::env(K02_DYNAMIC_MAC_IN_DETECT_LOW)] &&
                                   $::env(K02_DYNAMIC_MAC_IN_DETECT_LOW) eq "1"}]
set k02_cdr_hold_low [expr {[info exists ::env(K02_DYNAMIC_CDR_HOLD_LOW)] &&
                             $::env(K02_DYNAMIC_CDR_HOLD_LOW) eq "1"}]
set k02_skip_txeq [expr {[info exists ::env(K02_DYNAMIC_SKIP_TXEQ)] &&
                          $::env(K02_DYNAMIC_SKIP_TXEQ) eq "1"}]
if {$k02_coeff_query} { set k02_dynamic_rate 1 }
set k02_direct_gen3 [expr {[info exists ::env(K02_DIRECT_GEN3)] &&
                            $::env(K02_DIRECT_GEN3) eq "1"}]
set k02_dynamic_start_delay [expr {$k02_dynamic_rate ? 1000000000 : 1024}]
# Golden-vs-K02 A/B Test 组合目标命名：每个组合使用独立目录，
# 避免不同 A/B 变量的 bit/probe 互相覆盖。
set k02_any_ab [expr {$k02_mac_in_detect_low || $k02_cdr_hold_low || $k02_skip_txeq}]
set k02_ab_combo_dir ""
set k02_ab_combo_stem ""
if {$k02_any_ab} {
    set k02_ab_combo_dir "build_k02_ab"
    if {$k02_mac_in_detect_low} { append k02_ab_combo_dir "_mac" }
    if {$k02_cdr_hold_low}     { append k02_ab_combo_dir "_cdr" }
    if {$k02_skip_txeq}        { append k02_ab_combo_dir "_skiptxeq" }
    set k02_ab_combo_stem "k02_pcie_phy_bringup_ab"
    if {$k02_mac_in_detect_low} { append k02_ab_combo_stem "_mac" }
    if {$k02_cdr_hold_low}     { append k02_ab_combo_stem "_cdr" }
    if {$k02_skip_txeq}        { append k02_ab_combo_stem "_skiptxeq" }
}
if {$k02_direct_gen3} {
    set build_dir [file join $script_dir build_k02_gen3]
    set bit_stem k02_pcie_phy_bringup_gen3
} elseif {$k02_dynamic_rate} {
    if {$k02_off_gap && $k02_coeff_query} {
        set build_dir [file join $script_dir build_k02_dynamic_offgap_query]
        set bit_stem k02_pcie_phy_bringup_dynamic_offgap_query
    } elseif {$k02_off_gap && $k02_any_ab} {
        set build_dir [file join $script_dir $k02_ab_combo_dir]
        set bit_stem $k02_ab_combo_stem
    } elseif {$k02_off_gap} {
        set build_dir [file join $script_dir build_k02_dynamic_offgap]
        set bit_stem k02_pcie_phy_bringup_dynamic_offgap
    } elseif {$k02_coeff_query} {
        set build_dir [file join $script_dir build_k02_dynamic_query]
        set bit_stem k02_pcie_phy_bringup_dynamic_query
    } else {
        set build_dir [file join $script_dir build_k02_dynamic]
        set bit_stem k02_pcie_phy_bringup_dynamic
    }
} else {
    set build_dir [file join $script_dir build_k02]
    set bit_stem k02_pcie_phy_bringup
}

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
read_verilog -sv [file join $project_dir rtl/phy/kcu105_pcie_phy_bringup_top.sv]
read_xdc [file join $script_dir k02_pcie_phy_bringup.xdc]

synth_design -top $top_name -part $part_name \
    -generic GEN3_TEST_MODE=$k02_gen3_test \
    -generic DYNAMIC_RATE_TEST_MODE=$k02_dynamic_rate \
    -generic DYNAMIC_COEFF_QUERY_MODE=$k02_coeff_query \
    -generic DYNAMIC_GEN1_OFF_GAP_MODE=$k02_off_gap \
    -generic DIRECT_GEN3_MODE=$k02_direct_gen3 \
    -generic DYNAMIC_START_DELAY_CYCLES=$k02_dynamic_start_delay \
    -generic DYNAMIC_GEN1_OFF_GAP_CYCLES=2500 \
    -generic DYNAMIC_MAC_IN_DETECT_LOW_MODE=$k02_mac_in_detect_low \
    -generic DYNAMIC_CDR_HOLD_LOW_MODE=$k02_cdr_hold_low \
    -generic DYNAMIC_SKIP_TXEQ_MODE=$k02_skip_txeq

if {$k02_ila_debug} {
    # K02 standalone PHY 没有协议层 ILA；这里直接从综合网表中的 GT Wizard
    # 网络/primitive pin 建立一个同一 phy_pclk 域的诊断 ILA。所有连接失败
    # 都让构建失败，避免生成“看似有 ILA、实际没有 QPLL1LOCK”的假 bit。
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

    create_debug_core u_ila_k02 ila
    set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_k02]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_k02]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_k02]
    set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_k02]
    connect_debug_port u_ila_k02/clk [k02_net {(^|/)phy_pclk$}]
    set k02_gt_prefix {^u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/}

    # probe0 低到高位映射：QPLL1、PHY rate/powerdown/TX idle、
    # PLLCLKSEL/SYSCLKSEL、TXEQ/CDR hold、Gen3 rate handshake、
    # RX reset/data、PhyStatus、动态测试状态。
    set k02_probe0 [list \
        [k02_primitive_pin GTHE3_COMMON QPLL1LOCK] \
        [k02_net [format {%sqpll1lock_out\[0\]$} $k02_gt_prefix]] \
        [k02_primitive_pin GTHE3_COMMON QPLL1RESET] \
        [k02_primitive_pin GTHE3_COMMON QPLL1PD] \
        [k02_primitive_pin GTHE3_COMMON QPLL1LOCKEN] \
        [k02_primitive_pin GTHE3_COMMON QPLL1LOCKDETCLK] \
        [k02_primitive_pin GTHE3_COMMON QPLL1REFCLKLOST] \
        [k02_primitive_pin GTHE3_COMMON QPLL1FBCLKLOST] \
        [k02_primitive_bus_pin GTHE3_COMMON QPLL1REFCLKSEL 3] \
        [k02_primitive_pin GTHE3_CHANNEL GTPOWERGOOD] \
        [k02_bus {.*phy_rate_debug\[0\]$} 1] \
        [k02_bus {.*phy_rate_debug\[1\]$} 1] \
        [k02_bus {.*phy_powerdown_debug\[0\]$} 1] \
        [k02_bus {.*phy_powerdown_debug\[1\]$} 1] \
        [k02_net {.*phy_txelecidle_debug$}] \
        [k02_net [format {%spcierategen3_out\[0\]$} $k02_gt_prefix]] \
        [k02_primitive_bus_pin GTHE3_CHANNEL PCIERATEQPLLRESET 2] \
        [k02_primitive_bus_pin GTHE3_CHANNEL PCIERATEQPLLPD 2] \
        [k02_primitive_pin GTHE3_CHANNEL PCIERATEIDLE] \
        [k02_primitive_bus_pin GTHE3_CHANNEL TXPLLCLKSEL 2] \
        [k02_primitive_bus_pin GTHE3_CHANNEL RXPLLCLKSEL 2] \
        [k02_primitive_bus_pin GTHE3_CHANNEL TXSYSCLKSEL 2] \
        [k02_primitive_bus_pin GTHE3_CHANNEL RXSYSCLKSEL 2] \
        [k02_bus {.*phy_txeq_ctrl_debug\[[0-1]\]$} 2] \
        [k02_bus {.*phy_txeq_preset_debug\[[0-3]\]$} 4] \
        [k02_net {.*as_cdr_hold_debug$}] \
        [k02_net {.*as_mac_in_detect_debug$}] \
        [k02_net {.*phy_txeq_done_debug$}] \
        [k02_bus {.*phy_txeq_new_coeff_debug\[[0-9]+\]$} 18] \
        [k02_primitive_pin GTHE3_CHANNEL PCIEUSERGEN3RDY] \
        [k02_primitive_pin GTHE3_CHANNEL PCIEUSERRATESTART] \
        [k02_net [format {%srxresetdone_out\[0\]$} $k02_gt_prefix]] \
        [k02_net [format {%srxelecidle_out\[0\]$} $k02_gt_prefix]] \
        [k02_net [format {%srxvalid_out\[0\]$} $k02_gt_prefix]] \
        [k02_bus [format {%srxstatus_out\[0\]$} $k02_gt_prefix] 1] \
        [k02_bus [format {%srxstatus_out\[1\]$} $k02_gt_prefix] 1] \
        [k02_bus [format {%srxstatus_out\[2\]$} $k02_gt_prefix] 1] \
        [k02_net {^u_phy_wrapper/phy_phystatus$}] \
        [k02_net {^u_phy_wrapper/phy_phystatus_rst$}] \
        [k02_bus {.*phy_rate_debug\[0\]$} 1] \
        [k02_bus {.*phy_rate_debug\[1\]$} 1] \
        [k02_net {.*gen3_test_active$}] \
        [k02_bus {.*dynamic_rate_state\[[0-3]\]$} 4] \
        [k02_net {.*dynamic_rate_txeq_active$}] \
        [k02_net {.*dynamic_rate_txeq_query_active$}] \
        [k02_net {.*dynamic_rate_phystatus_seen$}] \
        [k02_net {.*dynamic_rate_pass$}] \
        [k02_net {.*dynamic_rate_fail$}]]
    set k02_probe0 [concat {*}$k02_probe0]
    if {[llength $k02_probe0] != 80} {
        error "K02 ILA probe0宽度错误：[llength $k02_probe0]，期望80"
    }
    k02_add_probe u_ila_k02 0 $k02_probe0

    # probe1：bring-up FSM 和 Detect 结果，便于把 QPLL1 变化对齐到状态转换。
    set k02_probe1 [concat \
        [k02_bus {.*bup_state\[[0-2]\]$} 3] \
        [k02_net {.*detect_done$}] \
        [k02_net {.*receiver_present$}] \
        [k02_net {.*detect_timeout$}] \
        [k02_net {.*unexpected_status$}] \
        [k02_bus {.*detected_rxstatus\[[0-2]\]$} 3]]
    k02_add_probe u_ila_k02 1 $k02_probe1
    puts "K02_PHY_ILA_INSERT_PASS probe0_width=[llength $k02_probe0] probe1_width=[llength $k02_probe1] depth=8192 gen3_test=$k02_gen3_test dynamic_rate=$k02_dynamic_rate coeff_query=$k02_coeff_query direct_gen3=$k02_direct_gen3 mac_in_detect_low=$k02_mac_in_detect_low cdr_hold_low=$k02_cdr_hold_low skip_txeq=$k02_skip_txeq"
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

set bit_name [expr {$k02_ila_debug ? "${bit_stem}_ila.bit" :
                                      "${bit_stem}.bit"}]
write_bitstream -force [file join $build_dir $bit_name]
if {$k02_ila_debug} {
    write_debug_probes -force [file join $build_dir ${bit_stem}_ila.ltx]
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
puts $summary_file "K02_ILA_DEBUG=$k02_ila_debug"
puts $summary_file "GEN3_TEST_MODE=$k02_gen3_test"
puts $summary_file "DYNAMIC_RATE_TEST_MODE=$k02_dynamic_rate"
puts $summary_file "DYNAMIC_COEFF_QUERY_MODE=$k02_coeff_query"
puts $summary_file "DYNAMIC_GEN1_OFF_GAP_MODE=$k02_off_gap"
puts $summary_file "DYNAMIC_GEN1_OFF_GAP_CYCLES=2500"
puts $summary_file "DIRECT_GEN3_MODE=$k02_direct_gen3"
puts $summary_file "DYNAMIC_START_DELAY_CYCLES=$k02_dynamic_start_delay"
puts $summary_file "DYNAMIC_MAC_IN_DETECT_LOW_MODE=$k02_mac_in_detect_low"
puts $summary_file "DYNAMIC_CDR_HOLD_LOW_MODE=$k02_cdr_hold_low"
puts $summary_file "DYNAMIC_SKIP_TXEQ_MODE=$k02_skip_txeq"
puts $summary_file "bitstream=[file join $build_dir $bit_name]"
close $summary_file

puts "K02_IMPL_PASS channel=$channel_loc common=$common_loc WNS=$wns"
