# K14 endpoint Recovery.Speed ILA program/capture helper.
set script_dir  [file dirname [file normalize [info script]]]
set phase_e1_debug [expr {[info exists ::env(PHASE_E1_BOARD_DEBUG)] &&
                          $::env(PHASE_E1_BOARD_DEBUG) eq "1"}]
set phase_e2_debug [expr {[info exists ::env(PHASE_E2_RCVRLOCK_DEBUG)] &&
                          $::env(PHASE_E2_RCVRLOCK_DEBUG) eq "1"}]
set phase_e1_auto_retrain_cycles 0
if {[info exists ::env(PHASE_E1_AUTO_RETRAIN_CYCLES)]} {
  set phase_e1_auto_retrain_cycles $::env(PHASE_E1_AUTO_RETRAIN_CYCLES)
}
if {![string is integer -strict $phase_e1_auto_retrain_cycles] ||
    $phase_e1_auto_retrain_cycles ni {0 1}} {
  error "PHASE_E1_AUTO_RETRAIN_CYCLES must be 0 or 1"
}
if {!$phase_e1_debug && $phase_e1_auto_retrain_cycles != 0} {
  error "AUTO retrain override is only valid for PHASE_E1_BOARD_DEBUG"
}
set phase_e1_timing_debug [expr {[info exists ::env(PHASE_E1_TIMING_DEBUG)] &&
                                 $::env(PHASE_E1_TIMING_DEBUG) eq "1"}]
if {$phase_e1_timing_debug && !$phase_e1_debug} {
  error "Phase E1 timing recorder requires PHASE_E1_BOARD_DEBUG"
}
if {$phase_e1_debug && $phase_e2_debug} {
  error "Phase E1 and E2 hardware helpers must remain independent"
}
if {$phase_e1_debug} {
  set build_name [expr {$phase_e1_auto_retrain_cycles == 1 ?
                        "build_phase_e1_board_auto1" :
                        "build_phase_e1_board"}]
  if {$phase_e1_timing_debug} {
    set build_name [expr {$phase_e1_auto_retrain_cycles == 1 ?
                          "build_phase_e1_timing_auto1" :
                          "build_phase_e1_timing"}]
  }
  set file_prefix "phase_e1_board"
  set pass_prefix "PHASE_E1_BOARD"
} elseif {$phase_e2_debug} {
  set build_name "build_phase_e2_rcvrlock"
  set file_prefix "phase_e2_rcvrlock"
  set pass_prefix "PHASE_E2_RCVRLOCK"
} else {
  set build_name "build_k14_recovery_speed"
  set file_prefix "k14_recovery_speed"
  set pass_prefix "K14_RECOVERY"
}
set build_root  [file join $script_dir $build_name]
set impl_dir    [file join $build_root impl]
set capture_dir [file join $build_root capture]
set bit_path    [file join $impl_dir ${file_prefix}_ila.bit]
set ltx_path    [file join $impl_dir ${file_prefix}_ila.ltx]

set server_url 127.0.0.1:3122
set action status
set post_program_settle_ms 0
if {[info exists ::env(K14_POST_PROGRAM_SETTLE_MS)]} {
  set post_program_settle_ms $::env(K14_POST_PROGRAM_SETTLE_MS)
}
if {![string is integer -strict $post_program_settle_ms] ||
    $post_program_settle_ms < 0} {
  error "K14_POST_PROGRAM_SETTLE_MS must be a non-negative integer"
}
if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
if {[llength $argv] >= 2} { set action [lindex $argv 1] }
if {[info exists ::env(K14_HW_SERVER_URL)] &&
    $::env(K14_HW_SERVER_URL) ne ""} {
  set server_url $::env(K14_HW_SERVER_URL)
}
if {$action ni {program-arm program-capture-wait arm-only arm-capture-wait capture-wait upload status}} {
  error "K14 Recovery.Speed ILA invalid action: $action"
}
if {![file exists $bit_path]} { error "K14 bitstream missing: $bit_path" }
if {![file exists $ltx_path]} { error "K14 probes missing: $ltx_path" }
file mkdir $capture_dir

open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target
set devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $devices] != 1} {
  error "K14 expected one xcku040 device, found [llength $devices]"
}
set device [lindex $devices 0]
set_property PROBES.FILE $ltx_path $device
set_property FULL_PROBES.FILE $ltx_path $device

if {$action eq "program-arm" || $action eq "program-capture-wait"} {
  set_property PROGRAM.FILE $bit_path $device
  program_hw_devices $device
  if {$post_program_settle_ms > 0} {
    after $post_program_settle_ms
  }
}
refresh_hw_device $device
set ilas [get_hw_ilas -of_objects $device]
if {[llength $ilas] != 1} {
  error "K14 expected one ILA, found [llength $ilas]"
}
set ila [lindex $ilas 0]

set trigger_probe {}
set target_probe_name [expr {[info exists ::env(K14_ILA_TRIGGER_PROBE)] ?
                              $::env(K14_ILA_TRIGGER_PROBE) :
                              "k14_event_state_w"}]
set trigger_compare [expr {[info exists ::env(K14_ILA_TRIGGER_COMPARE)] ?
                            $::env(K14_ILA_TRIGGER_COMPARE) : "eq4'h8"}]
set trigger_pos [expr {[info exists ::env(K14_ILA_TRIGGER_POS)] ?
                        $::env(K14_ILA_TRIGGER_POS) : 2048}]
foreach probe [get_hw_probes -of_objects $ila] {
  set probe_name [get_property NAME $probe]
  if {[string match "*$target_probe_name*" $probe_name] ||
      $probe_name eq $target_probe_name} {
    lappend trigger_probe $probe
  }
}
if {[llength $trigger_probe] != 1} {
  puts "K14 available probes:"
  foreach probe [get_hw_probes -of_objects $ila] {
    puts "  [get_property NAME $probe]"
  }
  error "K14 trigger probe missing/non-unique: $target_probe_name"
}
set trigger_probe [lindex $trigger_probe 0]
set rate_trigger_probe {}
set rate_trigger_compare {}
if {[info exists ::env(K14_ILA_RATE_COMPARE)]} {
  set rate_trigger_compare $::env(K14_ILA_RATE_COMPARE)
  foreach probe [get_hw_probes -of_objects $ila] {
    set probe_name [get_property NAME $probe]
    if {[string match "*k14_phy_rate_w*" $probe_name]} {
      lappend rate_trigger_probe $probe
    }
  }
  if {[llength $rate_trigger_probe] != 1} {
    error "K14 rate trigger probe missing/non-unique count=[llength $rate_trigger_probe]"
  }
  set rate_trigger_probe [lindex $rate_trigger_probe 0]
}

if {$action eq "program-arm" || $action eq "program-capture-wait" ||
    $action eq "arm-only" ||
    $action eq "arm-capture-wait"} {
  set_property CONTROL.TRIGGER_POSITION $trigger_pos $ila
  reset_hw_ila $ila
  set_property TRIGGER_COMPARE_VALUE $trigger_compare $trigger_probe
  if {$rate_trigger_compare ne ""} {
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property TRIGGER_COMPARE_VALUE $rate_trigger_compare $rate_trigger_probe
  }
  run_hw_ila $ila
  puts "${pass_prefix}_ILA_ARM_PASS trigger=[get_property NAME $trigger_probe] compare=[get_property TRIGGER_COMPARE_VALUE $trigger_probe] rate_compare=$rate_trigger_compare pos=$trigger_pos"
}
if {$action eq "program-capture-wait" || $action eq "arm-capture-wait" ||
    $action eq "capture-wait" || $action eq "upload"} {
  if {$action eq "program-capture-wait" || $action eq "arm-capture-wait" ||
      $action eq "capture-wait"} {
    wait_on_hw_ila -timeout 30 $ila
  }
  set data [upload_hw_ila_data $ila]
  set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
  set csv_path [file join $capture_dir ${timestamp}_${file_prefix}.csv]
  set ila_path [file join $capture_dir ${timestamp}_${file_prefix}.ila]
  write_hw_ila_data -force -csv_file $csv_path $data
  write_hw_ila_data -force $ila_path $data
  puts "${pass_prefix}_ILA_CAPTURE_PASS csv=$csv_path ila=$ila_path"
} elseif {$action eq "status"} {
  puts "${pass_prefix}_ILA_STATUS_PASS device=$device ila=$ila"
  foreach property [lsort [list_property $ila]] {
    if {[string match "STATUS.*" $property]} {
      puts "K14_ILA_${property}=[get_property $property $ila]"
    }
  }
}

close_hw_target
disconnect_hw_server
close_hw_manager
