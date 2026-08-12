set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set ila_debug   [expr {[info exists ::env(K11B2_ILA_DEBUG)] &&
                       $::env(K11B2_ILA_DEBUG) eq "1"}]
set ila_pipe_only [expr {$ila_debug && [info exists ::env(K11B2_ILA_PIPE_ONLY)] &&
                         $::env(K11B2_ILA_PIPE_ONLY) eq "1"}]
set g2_gen1_only [expr {[info exists ::env(G2_GEN1_ONLY)] &&
                        $::env(G2_GEN1_ONLY) eq "1"}]
set g7_rx_p0_quiet [expr {[info exists ::env(G7_RX_P0_QUIET)] &&
                          $::env(G7_RX_P0_QUIET) eq "1"}]
set g8_fast_detect [expr {[info exists ::env(G8_FAST_DETECT)] &&
                          $::env(G8_FAST_DETECT) eq "1"}]
if {$ila_debug && $g2_gen1_only} {
  error "G2 Gen1/CPLL诊断构建不支持ILA模式"
}
if {$g7_rx_p0_quiet && !$ila_debug} {
  error "G7 Detect.Quiet P0诊断必须启用K11B2_ILA_DEBUG"
}
if {$g8_fast_detect && !$ila_debug} {
  error "G8快速首次Detect诊断必须启用K11B2_ILA_DEBUG"
}
if {$g7_rx_p0_quiet && $g8_fast_detect} {
  error "G7与G8必须单变量A/B，不能同时启用"
}
set ila_resume  [expr {$ila_debug && [info exists ::env(K11B2_ILA_RESUME)] &&
                       $::env(K11B2_ILA_RESUME) eq "1"}]
set phy_module  pcie_phy_x1_gen3
set phy_ip_root [file join $script_dir \
                  [expr {$g2_gen1_only ? "ip_g2_gen1" : "ip"}]]
set build_dir   [file join $script_dir \
                  [expr {$g2_gen1_only ? "build_g2_gen1" :
                         ($g7_rx_p0_quiet ? "build_g7_rxp0_ila" :
                         ($g8_fast_detect ? "build_g8_fast_detect_ila" :
                         ($ila_debug ? "build_k11b2_ila" : "build_k11b2")))}] impl]
set xci_path    [file join $phy_ip_root $phy_module ${phy_module}.xci]
set afifo_path  /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
set part_name   xcku040-ffva1156-2-e
set top_name    kcu105_pcie_ep_gen1_board_top
file mkdir $build_dir

if {$ila_resume} {
  set resume_dcp [file join $build_dir k11b3_pre_ila_synth.dcp]
  if {![file exists $resume_dcp]} { error "K11-B3续跑DCP不存在：$resume_dcp" }
  open_checkpoint $resume_dcp
  puts "K11B3_ILA_RESUME_FROM_DCP=$resume_dcp"
} else {
if {![file exists $xci_path]} { error "K11-B2 XCI不存在，请先执行make k02-ip：$xci_path" }
if {![file exists $afifo_path]} { error "缺少冻结afifo依赖：$afifo_path" }

set_part $part_name
read_ip $xci_path
generate_target all [get_ips $phy_module]
set ip_dcp [file join $phy_ip_root $phy_module ${phy_module}.dcp]
if {[file exists $ip_dcp]} { file delete -force $ip_dcp }
synth_ip -force [get_ips $phy_module]

read_verilog $afifo_path
set sv_files [list \
  rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
  rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
  rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
  rtl/common/pcie_cdc_pulse.sv \
  rtl/phy/kcu105_reset_ctrl.sv rtl/phy/kcu105_refclk_reset.sv \
  rtl/phy/kcu105_pcie_phy_wrapper.sv rtl/phy/pcie_gen12_scrambler.sv \
  rtl/phy/pcie_gen1_rx_symbol_aligner.sv rtl/phy/pcie_gen1_os_rx.sv \
  rtl/phy/pcie_gen1_os_tx.sv rtl/phy/pcie_gen1_framer.sv \
  rtl/common/pcie_link_loss_trigger.sv \
  rtl/phy/pcie_ltssm_mac_gen1.sv \
  rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv \
  rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv \
  rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv \
  rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv \
  rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv \
  rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv \
  rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv \
  sim/verilator/k09_integration/k09_tlp_test_top.sv \
  rtl/ep/k11a_offline_top.sv rtl/ep/kcu105_pcie_ep_gen1_top.sv \
  rtl/ep/kcu105_pcie_ep_gen1_board_top.sv]
foreach f $sv_files { read_verilog -sv [file join $project_dir $f] }
read_xdc [file join $script_dir k03_gen1_ltssm_mac.xdc]

if {$ila_debug} {
  if {$g7_rx_p0_quiet} {
    synth_design -top $top_name -part $part_name \
      -generic K11B2_ILA_DEBUG=1 -generic G7_RX_P0_QUIET=1
  } elseif {$g8_fast_detect} {
    # 250 MHz PIPE时钟下25,000周期约100 us，只验证首次Detect启动竞态。
    synth_design -top $top_name -part $part_name \
      -generic K11B2_ILA_DEBUG=1 -generic DETECT_QUIET_CYCLES=25000
  } else {
    synth_design -top $top_name -part $part_name -generic K11B2_ILA_DEBUG=1
  }
  write_checkpoint -force [file join $build_dir k11b3_pre_ila_synth.dcp]
} else {
  synth_design -top $top_name -part $part_name
}
}

if {$ila_debug} {
  proc debug_bus_nets {regexp_pattern expected_width} {
    set result [lsort -dictionary [get_nets -hierarchical -quiet -regexp \
                                   $regexp_pattern -filter {MARK_DEBUG == 1}]]
    if {[llength $result] != $expected_width} {
      error "K11-B3调试总线宽度错误：$regexp_pattern，实际[llength $result]，期望$expected_width"
    }
    return $result
  }
  proc debug_scalar_net {net_name} {
    set result [get_nets -hierarchical -quiet $net_name -filter {MARK_DEBUG == 1}]
    if {[llength $result] == 0} {
      set leaf_name [file tail $net_name]
      set result [get_nets -hierarchical -quiet -regexp ".*${leaf_name}.*" \
                  -filter {MARK_DEBUG == 1}]
    }
    if {[llength $result] != 1} {
      error "K11-B3调试标量不存在或不唯一：$net_name，实际[llength $result]"
    }
    return $result
  }
  # K11-B4：直接从生成的 standalone PHY/GTHE3 层级引出只读诊断网。
  # 这些网不进入正式协议逻辑，只用于确认 TX 复位、PLL/GT 状态和
  # PHY 到 GT 的 Electrical Idle 控制是否一致。层级路径来自 K02 XCI
  # 生成的固定网表；若 XCI 重新生成导致路径变化，应让构建明确失败。
  proc phy_boundary_net {regexp_pattern} {
    set result [get_nets -hierarchical -quiet -regexp $regexp_pattern]
    if {[llength $result] != 1} {
      error "K11-B4 PHY诊断网不存在或不唯一：$regexp_pattern，实际[llength $result]"
    }
    set_property MARK_DEBUG TRUE $result
    return $result
  }
  proc phy_boundary_net_first {regexp_patterns} {
    foreach regexp_pattern $regexp_patterns {
      set result [get_nets -hierarchical -quiet -regexp $regexp_pattern]
      if {[llength $result] == 1} {
        set_property MARK_DEBUG TRUE $result
        return $result
      }
    }
    error "K11-B4 PHY诊断网候选均不存在或不唯一：$regexp_patterns"
  }
  proc phy_boundary_bus {regexp_pattern expected_width} {
    set result [lsort -dictionary [get_nets -hierarchical -quiet -regexp $regexp_pattern]]
    if {[llength $result] != $expected_width} {
      error "K11-G3 PHY诊断总线不存在或宽度错误：$regexp_pattern，实际[llength $result]，期望$expected_width"
    }
    set_property MARK_DEBUG TRUE $result
    return $result
  }
  proc add_ila_probe {core_name probe_index nets} {
    if {$probe_index != 0} { create_debug_port $core_name probe }
    set port [get_debug_ports ${core_name}/probe${probe_index}]
    set_property port_width [llength $nets] $port
    connect_debug_port $port $nets
  }

  create_debug_core u_ila_pipe ila
  # 1024 TS1 = 8192个125 MHz PIPE周期；这里保留更长的GT RX复位/CDR
  # 取证窗口，确认RXRESETDONE不是仅仅晚于上一版131 us采集窗口。
  set_property C_DATA_DEPTH 32768 [get_debug_cores u_ila_pipe]
  set_property C_TRIGIN_EN false [get_debug_cores u_ila_pipe]
  set_property C_TRIGOUT_EN false [get_debug_cores u_ila_pipe]
  set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_pipe]
  connect_debug_port u_ila_pipe/clk \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_pipe_clk]
  add_ila_probe u_ila_pipe 0 \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_pipe_tlp_trigger]
  add_ila_probe u_ila_pipe 1 \
    [debug_bus_nets {.*dbg_pipe_top.*\[[0-9]+\]$} 64]
  add_ila_probe u_ila_pipe 2 \
    [debug_bus_nets {.*dbg_pipe_dll.*\[[0-9]+\]$} 128]
  add_ila_probe u_ila_pipe 3 \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_pipe_link_loss_trigger]
  add_ila_probe u_ila_pipe 4 \
    [debug_bus_nets {.*dbg_ltssm_detail.*\[[0-9]+\]$} 256]
  add_ila_probe u_ila_pipe 5 \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_phy_rxidle_conflict]
  # probe6 位序（由低到高对应列表顺序）：
  # 同步后的PERST#、PERST#上升沿脉冲、PIPE_RST_N、PHY TX_VALID、PHY TX_ELECIDLE、
  # GT TXRESETDONE、GT POWERGOOD、QPLL1LOCK、PCIe TX sync done、
  # GT 侧 TXELECIDLE 输入、PHY状态复位撤销事件。
  set phy_probe_nets [list \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_perst_n_pipe] \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_perst_rise_pipe] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/pipe_rst_n$}] \
    [phy_boundary_net_first [list \
      {^u_endpoint/phy_txdata_valid$} \
      {^u_endpoint/u_phy_wrapper/phy_txdata_valid$}]] \
    [phy_boundary_net {^u_endpoint/phy_txelecidle$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/txresetdone_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/gtpowergood_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/qpll1lock_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pciesynctxsyncdone_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/txelecidle_in\[0\]$}] \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_phystatus_rst_fall_pipe]]
  add_ila_probe u_ila_pipe 6 $phy_probe_nets

  # G3：直接观察GTHE3解码输出，区分“GT本身仍判定Electrical Idle”与
  # “standalone PHY在GT之后屏蔽了有效数据”。probe7从低到高依次为：
  # RXRESETDONE、原始RXELECIDLE、原始RXVALID、原始RXSTATUS[2:0]。
  # 上一轮已确认原始RXDATA/RXCTRL0全程为0，本轮移除这34位，
  # 为接收控制探针释放布线余量。
  set g3_gt_prefix {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/}
  set g3_rx_probe_nets [list \
    [phy_boundary_net [format {%srxresetdone_out\[0\]$} $g3_gt_prefix]] \
    [phy_boundary_net [format {%srxelecidle_out\[0\]$} $g3_gt_prefix]] \
    [phy_boundary_net [format {%srxvalid_out\[0\]$} $g3_gt_prefix]]]
  set g3_rx_probe_nets [concat $g3_rx_probe_nets \
    [phy_boundary_bus [format {%srxstatus_out\[[0-2]\]$} $g3_gt_prefix] 3]]
  add_ila_probe u_ila_pipe 7 $g3_rx_probe_nets

  # G4：采集送入GTHE3的动态RX控制。probe8从低到高依次为：
  # RXCDRHOLD、RXRATE[1:0]、RXPD[1:0]、RXPOLARITY、RX8B10BEN。
  # GTRXRESET/RXUSERRDY来自100 MHz复位域，直接接入250 MHz ILA会形成CDC-1；
  # RXRESETDONE已足够确认其最终复位/ready结果，因此不跨域采集这两位。
  # 这些信号用于验证静态GT属性相同后，接收电源/CDR控制时序是否仍有差异。
  set g4_rx_control_nets [list \
    [phy_boundary_net [format {%srxcdrhold_in\[0\]$} $g3_gt_prefix]]]
  set g4_rx_control_nets [concat $g4_rx_control_nets \
    [phy_boundary_bus [format {%srxrate_in\[[0-1]\]$} $g3_gt_prefix] 2] \
    [phy_boundary_bus [format {%srxpd_in\[[0-1]\]$} $g3_gt_prefix] 2] \
    [list \
      [phy_boundary_net [format {%srxpolarity_in\[0\]$} $g3_gt_prefix]] \
      [phy_boundary_net [format {%srx8b10ben_in\[0\]$} $g3_gt_prefix]]]]
  add_ila_probe u_ila_pipe 8 $g4_rx_control_nets
  # probe9：Polling.Active中已经完成发送的TS1数量（每个TS1=8个125 MHz pclk）。
  add_ila_probe u_ila_pipe 9 \
    [debug_bus_nets {.*dbg_polling_tx_ts1_count.*\[[0-9]+\]$} 11]
  if {!$ila_pipe_only} {
    create_debug_core u_ila_core ila
    set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_core]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_core]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_core]
    set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_core]
    connect_debug_port u_ila_core/clk \
      [debug_scalar_net u_endpoint/u_protocol_core/g_ila_debug_core/dbg_core_clk]
    add_ila_probe u_ila_core 0 \
      [debug_scalar_net u_endpoint/u_protocol_core/g_ila_debug_core/dbg_core_tlp_trigger]
    add_ila_probe u_ila_core 1 \
      [debug_bus_nets {.*dbg_core_stream.*\[[0-9]+\]$} 128]
    add_ila_probe u_ila_core 2 \
      [debug_bus_nets {.*dbg_core_detail.*\[[0-9]+\]$} 320]
    add_ila_probe u_ila_core 3 \
      [debug_scalar_net u_endpoint/u_protocol_core/g_ila_debug_core/dbg_core_link_loss_trigger]
  }

  puts "K11G4_ILA_INSERT_PASS pipe_width=475 core_width=[expr {$ila_pipe_only ? 0 : 450}] depth=32768"
}
set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
  {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
if {[llength $afifo_gray_sync_cells] == 0} { error "K11-B2未找到afifo Gray同步寄存器" }
set_property ASYNC_REG TRUE $afifo_gray_sync_cells
set_property SHREG_EXTRACT NO $afifo_gray_sync_cells
write_checkpoint -force [file join $build_dir k11b2_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
# 路由后对正式与ILA构建统一执行进取物理优化。这不改变RTL，
# 主要收敛MAC TX到GTHE3 TXDATA的跨层长路由；正式构建仍由下方
# WNS/WHS>=0门禁决定是否生成bitstream。
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $build_dir k11b2_routed.dcp]
report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc_routed.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_pin {port_name expected_pin} {
  set port_object [get_ports $port_name]
  if {[llength $port_object] != 1} { error "K11-B2顶层端口不存在：$port_name" }
  set actual_pin [get_property PACKAGE_PIN $port_object]
  if {![string equal -nocase $actual_pin $expected_pin]} {
    error "K11-B2管脚错误：$port_name=$actual_pin，期望$expected_pin"
  }
}
require_port_pin pcie_refclk_p AB6
require_port_pin pcie_refclk_n AB5
require_port_pin pcie_perst_n K22
require_port_pin pcie_rxp AB2
require_port_pin pcie_rxn AB1
require_port_pin pcie_txp AC4
require_port_pin pcie_txn AC3

set gth_channels [get_cells -hierarchical -filter {REF_NAME == GTHE3_CHANNEL}]
set gth_commons  [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1} { error "K11-B2 GTHE3_CHANNEL数量错误：[llength $gth_channels]" }
set channel_loc [get_property LOC $gth_channels]
if {![string equal -nocase $channel_loc GTHE3_CHANNEL_X0Y7]} { error "K11-B2 GT Channel LOC错误：$channel_loc" }
if {$g2_gen1_only} {
  if {[llength $gth_commons] > 1} {
    error "G2 Gen1/CPLL GTHE3_COMMON数量错误：[llength $gth_commons]"
  }
  set common_loc [expr {[llength $gth_commons] == 1 ?
                        [get_property LOC $gth_commons] : "NONE_CPLL"}]
} else {
  if {[llength $gth_commons] != 1} { error "K11-B2 GTHE3_COMMON数量错误：[llength $gth_commons]" }
  set common_loc [get_property LOC $gth_commons]
  if {![string equal -nocase $common_loc GTHE3_COMMON_X0Y1]} { error "K11-B2 GT Common LOC错误：$common_loc" }
}

set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
  REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} { error "K11-B2错误实例化PCIe Hard Block：$hard_pcie_count" }

proc require_hierarchy {module_name} {
  set cells [get_cells -quiet -hierarchical -filter "ORIG_REF_NAME == $module_name"]
  if {[llength $cells] == 0} { set cells [get_cells -quiet -hierarchical -filter "REF_NAME == $module_name"] }
  if {[llength $cells] == 0} { error "K11-B2找不到层次：$module_name" }
  return [llength $cells]
}
set mac_count  [require_hierarchy pcie_ltssm_mac_gen1]
set dll_count  [require_hierarchy pcie_dll]
set cfg_count  [require_hierarchy pcie_cfg_space]
set bar_count  [require_hierarchy pcie_bar_axil_master]
set demo_count [require_hierarchy demo_axil_slave]

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {!$ila_debug && [llength $setup_paths] != 0} { error "K11-B2存在setup负时序" }
if {!$ila_debug && [llength $hold_paths] != 0} { error "K11-B2存在hold负时序" }
if {$ila_debug && ([llength $setup_paths] != 0 || [llength $hold_paths] != 0)} {
  puts "K11B3_ILA_DIAGNOSTIC_TIMING_ONLY setup_negative=[llength $setup_paths] hold_negative=[llength $hold_paths]"
}
set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} { error "K11-B2找不到可分析的最大延迟路径" }
set wns [get_property SLACK $worst_path]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
  error "K11-B2 DRC存在Error或Critical Warning"
}
set cdc_fp [open [file join $build_dir cdc_routed.rpt] r]
set cdc_text [read $cdc_fp]
close $cdc_fp
if {[regexp -line {^CDC-[0-9]+[ \t]+Critical[ \t]+[1-9][0-9]*} $cdc_text]} {
  error "K11-B2 CDC存在Critical路径"
}

set bit_name [expr {$g2_gen1_only ? "g2_gen1_cpll_endpoint.bit" :
                     ($ila_debug ? "k11b2_gen1_endpoint_ila.bit" :
                                   "k11b2_gen1_endpoint.bit")}]
write_bitstream -force [file join $build_dir $bit_name]
if {$ila_debug} {
  write_debug_probes -force [file join $build_dir k11b2_gen1_endpoint_ila.ltx]
}
set summary_file [open [file join $build_dir summary.txt] w]
set pass_marker [expr {$g2_gen1_only ? "G2_GEN1_CPLL_IMPL_PASS" :
                        ($ila_debug ? "K11B3_ILA_IMPL_PASS" :
                                      "K11B2_IMPL_PASS")}]
puts $summary_file $pass_marker
puts $summary_file "part=$part_name"
puts $summary_file "top=$top_name"
puts $summary_file "GTHE3_CHANNEL_LOC=$channel_loc"
puts $summary_file "GTHE3_COMMON_LOC=$common_loc"
puts $summary_file "PCIE_HARD_BLOCK_COUNT=$hard_pcie_count"
puts $summary_file "MAC_HIERARCHY_COUNT=$mac_count"
puts $summary_file "DLL_HIERARCHY_COUNT=$dll_count"
puts $summary_file "CFG_HIERARCHY_COUNT=$cfg_count"
puts $summary_file "BAR_HIERARCHY_COUNT=$bar_count"
puts $summary_file "DEMO_HIERARCHY_COUNT=$demo_count"
puts $summary_file "WNS=$wns"
puts $summary_file "ILA_DEBUG=$ila_debug"
puts $summary_file "ILA_PIPE_ONLY=$ila_pipe_only"
puts $summary_file "G2_GEN1_ONLY=$g2_gen1_only"
puts $summary_file "G7_RX_P0_QUIET=$g7_rx_p0_quiet"
puts $summary_file "G8_FAST_DETECT=$g8_fast_detect"
puts $summary_file "PHY_MODULE=$phy_module"
puts $summary_file "TIMING_POLICY=[expr {$ila_debug ? "DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED" : "WNS_GE_0_REQUIRED"}]"
puts $summary_file "bitstream=[file join $build_dir $bit_name]"
close $summary_file
puts "$pass_marker channel=$channel_loc common=$common_loc WNS=$wns"
