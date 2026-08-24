# K02 standalone PHY ILA programming/capture helper.
# Default trigger is `seq_state_w` reaching S_GEN3_WAIT (4'd6) so the capture
# contains the pre-Gen3 divergence (QPLL1 1->0->1, debug_state==8'h04).
set script_dir  [file dirname [file normalize [info script]]]
set build_dir   [file join $script_dir build_k02]
set bit_stem    k02_pcie_phy_bringup_ila
set capture_dir [file join $build_dir capture]
set bit_path    [file join $build_dir ${bit_stem}.bit]
set ltx_path    [file join $build_dir ${bit_stem}.ltx]

set server_url 127.0.0.1:3122
set action status
if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
if {[llength $argv] >= 2} { set action [lindex $argv 1] }
if {$action ni {program-arm arm-only capture-wait upload status}} {
  error "K02 PHY ILA action非法：$action"
}
if {![file exists $bit_path]} { error "K02 PHY ILA bitstream不存在：$bit_path" }
if {![file exists $ltx_path]} { error "K02 PHY ILA probes不存在：$ltx_path" }
file mkdir $capture_dir

open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target
set devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $devices] != 1} { error "K02 PHY ILA期望唯一xcku040，实际[llength $devices]" }
set device [lindex $devices 0]
set_property PROBES.FILE $ltx_path $device
set_property FULL_PROBES.FILE $ltx_path $device

if {$action eq "program-arm"} {
  set_property PROGRAM.FILE $bit_path $device
  program_hw_devices $device
}
refresh_hw_device $device
set ilas [get_hw_ilas -of_objects $device]
if {[llength $ilas] != 1} { error "K02 PHY ILA期望唯一ILA，实际[llength $ilas]" }
set ila [lindex $ilas 0]
set trigger_probe {}
set trigger_compare [expr {[info exists ::env(K02_ILA_TRIGGER_COMPARE)] ?
                            $::env(K02_ILA_TRIGGER_COMPARE) : "eq4'h6"}]
set trigger_pos [expr {[info exists ::env(K02_ILA_TRIGGER_POS)] ?
                        $::env(K02_ILA_TRIGGER_POS) : 2048}]

if {[info exists ::env(K02_ILA_TRIGGER_PROBE)]} {
  set target_probe_name $::env(K02_ILA_TRIGGER_PROBE)
  foreach probe [get_hw_probes -of_objects $ila] {
    set probe_name [get_property NAME $probe]
    if {[string match "*$target_probe_name*" $probe_name] ||
        $probe_name eq $target_probe_name} {
      lappend trigger_probe $probe
    }
  }
  set trigger_error "K02 PHY ILA 自定义触发探针不存在或不唯一：$target_probe_name"
} else {
  # 默认触发：phy_bringup_seq.seq_state 走到 S_GEN3_WAIT (4'd6)。
  foreach probe [get_hw_probes -of_objects $ila] {
    set probe_name [get_property NAME $probe]
    if {$probe_name eq "seq_state_w"} {
      lappend trigger_probe $probe
    }
  }
  set trigger_error "K02 PHY ILA seq_state_w触发探针不存在或不唯一"
}
if {[llength $trigger_probe] != 1} {
  puts "K02 PHY ILA available probes:"
  foreach probe [get_hw_probes -of_objects $ila] {
    puts "  [get_property NAME $probe]"
  }
  error $trigger_error
}
set trigger_probe [lindex $trigger_probe 0]

if {$action eq "program-arm" || $action eq "arm-only"} {
  set_property CONTROL.TRIGGER_POSITION $trigger_pos $ila
  reset_hw_ila $ila
  set_property TRIGGER_COMPARE_VALUE $trigger_compare $trigger_probe
  run_hw_ila $ila
  puts "K02_PHY_ILA_ARM_PASS trigger=[get_property NAME $trigger_probe] compare=[get_property TRIGGER_COMPARE_VALUE $trigger_probe] pos=$trigger_pos"
} elseif {$action eq "capture-wait"} {
  set capture_timeout 20
  wait_on_hw_ila -timeout $capture_timeout $ila
  set data [upload_hw_ila_data $ila]
  set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
  set csv_path [file join $capture_dir ${timestamp}_k02_phy.csv]
  set ila_path [file join $capture_dir ${timestamp}_k02_phy.ila]
  write_hw_ila_data -force -csv_file $csv_path $data
  write_hw_ila_data -force $ila_path $data
  puts "K02_PHY_ILA_CAPTURE_PASS csv=$csv_path ila=$ila_path"
} elseif {$action eq "upload"} {
  set data [upload_hw_ila_data $ila]
  set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
  set csv_path [file join $capture_dir ${timestamp}_k02_phy.csv]
  set ila_path [file join $capture_dir ${timestamp}_k02_phy.ila]
  write_hw_ila_data -force -csv_file $csv_path $data
  write_hw_ila_data -force $ila_path $data
  puts "K02_PHY_ILA_UPLOAD_PASS csv=$csv_path ila=$ila_path"
} else {
  puts "K02_PHY_ILA_STATUS_PASS device=$device ila=$ila"
}

close_hw_target
disconnect_hw_server
close_hw_manager
