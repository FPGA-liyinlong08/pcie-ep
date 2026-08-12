set script_dir  [file dirname [file normalize [info script]]]
set g7_rx_p0_quiet [expr {[info exists ::env(G7_RX_P0_QUIET)] &&
                          $::env(G7_RX_P0_QUIET) eq "1"}]
set g8_fast_detect [expr {[info exists ::env(G8_FAST_DETECT)] &&
                          $::env(G8_FAST_DETECT) eq "1"}]
set g9_wait_remote_detect [expr {[info exists ::env(G9_WAIT_REMOTE_DETECT)] &&
                                 $::env(G9_WAIT_REMOTE_DETECT) eq "1"}]
set g10_cfg_complete [expr {[info exists ::env(G10_CFG_COMPLETE)] &&
                            $::env(G10_CFG_COMPLETE) eq "1"}]
set g11_rx_parser [expr {[info exists ::env(G11_RX_PARSER)] &&
                         $::env(G11_RX_PARSER) eq "1"}]
if {$g10_cfg_complete && !$g9_wait_remote_detect} {
  error "G10 CFG_COMPLETE诊断必须保留G9 WAIT_REMOTE_DETECT基线"
}
if {$g11_rx_parser && !$g9_wait_remote_detect} {
  error "G11 RX解析诊断必须保留G9 WAIT_REMOTE_DETECT基线"
}
if {[llength [lsearch -all -inline [list $g7_rx_p0_quiet $g8_fast_detect] 1]] > 0 &&
    [llength [lsearch -all -inline [list $g9_wait_remote_detect $g10_cfg_complete $g11_rx_parser] 1]] > 0} {
  error "G7/G8不能与G9/G10/G11诊断组合"
}
set build_name "build_k11b2_ila"
if {$g9_wait_remote_detect} { set build_name "build_g9_wait_remote_detect_ila" }
if {$g10_cfg_complete} { set build_name "build_g10_cfg_complete_ila" }
if {$g11_rx_parser} { set build_name "build_g11_rx_parser_ila" }
if {$g8_fast_detect} { set build_name "build_g8_fast_detect_ila" }
if {$g7_rx_p0_quiet} { set build_name "build_g7_rxp0_ila" }
set impl_dir    [file join $script_dir $build_name impl]
set capture_dir [file join $script_dir $build_name capture]
set bit_path    [file join $impl_dir k11b2_gen1_endpoint_ila.bit]
set ltx_path    [file join $impl_dir k11b2_gen1_endpoint_ila.ltx]

set server_url localhost:3122
set action status
if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
if {[llength $argv] >= 2} { set action [lindex $argv 1] }
if {$action ni {program-arm program-arm-linkdown program-arm-rxidle-conflict program-arm-cfg-complete program-arm-detect-active arm-detect-active program-arm-perst program-arm-perst-release program-arm-phy-reset-release program-arm-g9-rxidle program-arm-g9-timeout capture-wait capture-cfg-wait capture-cfg-complete-wait capture-tx-wait capture-linkdown-wait capture-rxidle-conflict-wait capture-g9-rxidle-wait capture-g9-timeout-wait capture-now status upload}} {
  error "K11-B3 ILA action非法：$action"
}
if {![file exists $bit_path]} { error "K11-B3 ILA bitstream不存在：$bit_path" }
if {![file exists $ltx_path]} { error "K11-B3 ILA probes文件不存在：$ltx_path" }
file mkdir $capture_dir

open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target
set ku040_devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $ku040_devices] != 1} {
  error "K11-B3期望唯一xcku040，实际数量[llength $ku040_devices]"
}
set ku040 [lindex $ku040_devices 0]
set_property PROBES.FILE $ltx_path $ku040
set_property FULL_PROBES.FILE $ltx_path $ku040

if {$action in {program-arm program-arm-linkdown program-arm-rxidle-conflict program-arm-cfg-complete program-arm-detect-active program-arm-perst program-arm-perst-release program-arm-phy-reset-release program-arm-g9-rxidle program-arm-g9-timeout capture-wait capture-cfg-wait capture-cfg-complete-wait capture-tx-wait capture-g9-rxidle-wait capture-g9-timeout-wait}} {
  set_property PROGRAM.FILE $bit_path $ku040
  program_hw_devices $ku040
}
refresh_hw_device $ku040

set ilas [get_hw_ilas -of_objects $ku040]
if {[llength $ilas] ni {1 2}} {
  error "K11-B3期望一个PIPE ILA或PIPE+Core两个ILA，实际数量[llength $ilas]"
}
foreach ila $ilas {
  set cell_name [get_property CELL_NAME $ila]
  puts "K11B3_ILA_CORE name=$ila cell=$cell_name"
  foreach probe [get_hw_probes -of_objects $ila] {
    set width unknown
    catch {set width [get_property WIDTH $probe]}
    puts "K11B3_ILA_PROBE ila=$cell_name name=[get_property NAME $probe] width=$width"
  }
}

if {$action in {program-arm program-arm-linkdown program-arm-rxidle-conflict program-arm-cfg-complete program-arm-detect-active arm-detect-active program-arm-perst program-arm-perst-release program-arm-phy-reset-release program-arm-g9-rxidle program-arm-g9-timeout capture-wait capture-cfg-wait capture-cfg-complete-wait capture-tx-wait capture-linkdown-wait capture-rxidle-conflict-wait capture-g9-rxidle-wait capture-g9-timeout-wait capture-now}} {
  foreach ila $ilas {
    set cell_name [get_property CELL_NAME $ila]
    if {$action eq "program-arm-perst" && $cell_name eq "u_ila_pipe"} {
      # PIPE域捕获同步后的PERST#低电平。
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_perst_n_pipe*"}]
    } elseif {$action eq "program-arm-perst-release" && $cell_name eq "u_ila_pipe"} {
      # 使用同步后的上升沿脉冲，避免主机已运行时Arm在高电平立即触发。
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_perst_rise_pipe*"}]
    } elseif {$action eq "program-arm-phy-reset-release" && $cell_name eq "u_ila_pipe"} {
      # 捕获PHY phystatus_rst撤销事件，观察PIPE复位释放和TS1启动。
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_phystatus_rst_fall_pipe*"}]
    } elseif {$action in {program-arm-linkdown capture-linkdown-wait}} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*link_loss_trigger*"}]
    } elseif {$action in {program-arm-rxidle-conflict capture-rxidle-conflict-wait} && $cell_name eq "u_ila_pipe"} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*phy_rxidle_conflict*"}]
    } elseif {$action in {program-arm-rxidle-conflict capture-rxidle-conflict-wait} && $cell_name eq "u_ila_core"} {
      # Core域没有RxElecIdle信号，使用同一次PHY链路退出的CDC脉冲对齐采样。
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*link_loss_trigger*"}]
    } elseif {$action in {program-arm-g9-rxidle capture-g9-rxidle-wait} && $cell_name eq "u_ila_pipe"} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_g9_rxelecidle_low_seen*"}]
    } elseif {$action in {program-arm-g9-timeout capture-g9-timeout-wait} && $cell_name eq "u_ila_pipe"} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_g9_timeout_seen*"}]
    } elseif {$action in {program-arm-cfg-complete capture-cfg-complete-wait program-arm-detect-active arm-detect-active} && $cell_name eq "u_ila_pipe"} {
      # 复用已有dbg_pipe_top，不修改RTL/ILA位宽；匹配LTSSM=CFG_COMPLETE(0x08)。
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_pipe_top*"}]
    } elseif {$action in {program-arm-cfg-complete capture-cfg-complete-wait} && $cell_name eq "u_ila_core"} {
      # Core域用Cfg请求原始详情对齐同一次启动。
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_core_detail*"}]
    } elseif {$action eq "capture-now"} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*tlp_trigger*"}]
    } elseif {$action in {capture-cfg-wait capture-cfg-complete-wait program-arm-cfg-complete capture-tx-wait} && $cell_name eq "u_ila_core"} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_core_detail*"}]
    } elseif {$action eq "capture-tx-wait" && $cell_name eq "u_ila_pipe"} {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*dbg_pipe_dll*"}]
    } else {
      set trigger_probes [get_hw_probes -of_objects $ila -filter {NAME =~ "*tlp_trigger*"}]
    }
    if {[llength $trigger_probes] != 1} {
      error "K11-B3 ILA触发探针不存在或不唯一：[get_property CELL_NAME $ila]"
    }
    if {$action eq "program-arm-perst" && $cell_name eq "u_ila_pipe"} {
      set_property TRIGGER_COMPARE_VALUE eq1'b0 [lindex $trigger_probes 0]
    } elseif {$action in {program-arm-perst-release program-arm-phy-reset-release} && $cell_name eq "u_ila_pipe"} {
      set_property TRIGGER_COMPARE_VALUE eq1'b1 [lindex $trigger_probes 0]
    } elseif {$action in {program-arm-linkdown capture-linkdown-wait program-arm-rxidle-conflict capture-rxidle-conflict-wait program-arm-g9-rxidle capture-g9-rxidle-wait program-arm-g9-timeout capture-g9-timeout-wait}} {
      set_property TRIGGER_COMPARE_VALUE eq1'b1 [lindex $trigger_probes 0]
    } elseif {$action eq "capture-now"} {
      set_property TRIGGER_COMPARE_VALUE eq1'bx [lindex $trigger_probes 0]
    } elseif {$action in {program-arm-cfg-complete capture-cfg-complete-wait program-arm-detect-active arm-detect-active} && $cell_name eq "u_ila_pipe"} {
      set pattern [string repeat x 64]
      if {$action in {program-arm-detect-active arm-detect-active}} {
        # dbg_pipe_top[32:27] = DETECT_ACTIVE (6'd1).
        foreach {bit_index bit_value} {27 1 28 0 29 0 30 0 31 0 32 0} {
          set string_index [expr {63 - $bit_index}]
          set pattern [string replace $pattern $string_index $string_index $bit_value]
        }
      } else {
        foreach {bit_index bit_value} {27 0 28 0 29 0 30 1 31 0 32 0} {
          set string_index [expr {63 - $bit_index}]
          set pattern [string replace $pattern $string_index $string_index $bit_value]
        }
      }
      set_property TRIGGER_COMPARE_VALUE "eq64'b$pattern" [lindex $trigger_probes 0]
    } elseif {$action in {capture-cfg-wait capture-cfg-complete-wait program-arm-cfg-complete capture-tx-wait} && $cell_name eq "u_ila_core"} {
      if {$action eq "capture-tx-wait"} {
        # 低字节0?001010：匹配Cpl(0x0a)和CplD(0x4a)。
        set compare_value "eq320'b[string repeat x 312]0x001010"
      } else {
        # 低字节0?000100：匹配CfgRd0(0x04)和CfgWr0(0x44)。
        set compare_value "eq320'b[string repeat x 312]0x000100"
      }
      set_property TRIGGER_COMPARE_VALUE $compare_value [lindex $trigger_probes 0]
    } elseif {$action eq "capture-tx-wait" && $cell_name eq "u_ila_pipe"} {
      # 仅匹配DLL TX valid(bit 9)，用采样值区分CDC无输出与DLL ready阻塞。
      set tx_pattern [string repeat x 128]
      foreach bit_index {9} {
        set string_index [expr {127 - $bit_index}]
        set tx_pattern [string replace $tx_pattern $string_index $string_index 1]
      }
      set_property TRIGGER_COMPARE_VALUE "eq128'b$tx_pattern" [lindex $trigger_probes 0]
    } else {
      set_property TRIGGER_COMPARE_VALUE eq1'b1 [lindex $trigger_probes 0]
    }
    set_property CONTROL.TRIGGER_POSITION [expr {$action in {program-arm-linkdown capture-linkdown-wait program-arm-rxidle-conflict capture-rxidle-conflict-wait program-arm-cfg-complete capture-cfg-complete-wait program-arm-detect-active arm-detect-active} ? 3072 : 1024}] $ila
    if {$action ni {capture-linkdown-wait capture-rxidle-conflict-wait capture-cfg-complete-wait}} {
      run_hw_ila $ila
    }
    puts "K11B3_ILA_ARMED cell=[get_property CELL_NAME $ila] trigger=[get_property NAME [lindex $trigger_probes 0]]"
  }
  puts "K11B3_ILA_PROGRAM_ARM_PASS bitstream=$bit_path mode=$action"
    if {$action in {capture-wait capture-cfg-wait capture-cfg-complete-wait capture-tx-wait capture-linkdown-wait capture-rxidle-conflict-wait capture-g9-rxidle-wait capture-g9-timeout-wait capture-now}} {
    set timeout_minutes [expr {$action eq "capture-now" ? 1 :
                              ($action eq "capture-wait" ? 2 :
                              ($action in {capture-linkdown-wait capture-rxidle-conflict-wait capture-cfg-complete-wait capture-g9-rxidle-wait capture-g9-timeout-wait} ? 5 : 3))}]
    puts "K11B3_ILA_WAITING timeout_minutes=$timeout_minutes mode=$action"
    wait_on_hw_ila -timeout $timeout_minutes $ilas
    puts "K11B3_ILA_TRIGGERED"
    set action upload
  }
}
if {$action eq "upload"} {
  set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
  foreach ila $ilas {
    set cell_name [string map {/ _ \\ _ : _} [get_property CELL_NAME $ila]]
    if {[catch {set data [upload_hw_ila_data $ila]} upload_error]} {
      error "K11-B3 ILA尚无可上传采样：$cell_name，$upload_error"
    }
    set csv_path [file join $capture_dir ${timestamp}_${cell_name}.csv]
    set ila_path [file join $capture_dir ${timestamp}_${cell_name}.ila]
    write_hw_ila_data -force -csv_file $csv_path $data
    write_hw_ila_data -force $ila_path $data
    puts "K11B3_ILA_CAPTURE_PASS cell=$cell_name csv=$csv_path ila=$ila_path"
  }
} elseif {$action eq "status"} {
  puts "K11B3_ILA_STATUS_PASS device=$ku040"
}

close_hw_target
disconnect_hw_server
close_hw_manager
