set script_dir [file dirname [file normalize [info script]]]
set build_dir [file join $script_dir build_g5_xdma_rx_ila]
set capture_dir [file join $build_dir capture]
set bit_path [file join $build_dir xdma_x1_rx_ila.bit]
set ltx_path [file join $build_dir xdma_x1_rx_ila.ltx]

set server_url localhost:3122
set action status
if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
if {[llength $argv] >= 2} { set action [lindex $argv 1] }
if {$action ni {program arm-resetdone arm-detect arm-detect-success arm-rxvalid-low arm-rxvalid-high capture-wait status}} {
  error "G5 XDMA ILA action非法：$action"
}
if {![file exists $bit_path]} { error "G5 XDMA ILA bitstream不存在：$bit_path" }
if {![file exists $ltx_path]} { error "G5 XDMA ILA probes不存在：$ltx_path" }
file mkdir $capture_dir

open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target
set devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $devices] != 1} { error "G5期望唯一xcku040，实际[llength $devices]" }
set device [lindex $devices 0]
set_property PROBES.FILE $ltx_path $device
set_property FULL_PROBES.FILE $ltx_path $device

if {$action eq "program"} {
  set_property PROGRAM.FILE $bit_path $device
  program_hw_devices $device
}
refresh_hw_device $device
set ilas [get_hw_ilas -of_objects $device]
if {[llength $ilas] != 1} { error "G5期望唯一ILA，实际[llength $ilas]" }
set ila [lindex $ilas 0]
set resetdone_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*rxresetdone_out*"}]
if {[llength $resetdone_probe] < 1} {
  error "G5 RXRESETDONE触发探针不存在"
}
set resetdone_probe [lindex $resetdone_probe 0]
set detect_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*txdetectrx_in*"}]
if {[llength $detect_probe] < 1} { error "G5 TXDETECTRX触发探针不存在" }
set detect_probe [lindex $detect_probe 0]
set rxstatus_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*rxstatus_out*"}]
if {[llength $rxstatus_probe] != 1} {
  error "G5 RXSTATUS触发探针不存在或不唯一：[llength $rxstatus_probe]"
}
set rxvalid_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*rxvalid_out*"}]
if {[llength $rxvalid_probe] != 1} {
  error "G5 RXVALID触发探针不存在或不唯一：[llength $rxvalid_probe]"
}

if {$action in {arm-resetdone arm-detect arm-detect-success arm-rxvalid-low arm-rxvalid-high}} {
  reset_hw_ila $ila
  if {$action eq "arm-detect-success"} {
    set trigger_probe $rxstatus_probe
    set_property TRIGGER_COMPARE_VALUE eq3'b011 $trigger_probe
  } elseif {$action in {arm-rxvalid-low arm-rxvalid-high}} {
    set trigger_probe $rxvalid_probe
    set trigger_value [expr {$action eq "arm-rxvalid-low" ? "eq1'b0" : "eq1'b1"}]
    set_property TRIGGER_COMPARE_VALUE $trigger_value $trigger_probe
  } else {
    set trigger_probe [expr {$action eq "arm-detect" ? $detect_probe : $resetdone_probe}]
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $trigger_probe
  }
  set_property CONTROL.TRIGGER_POSITION 1024 $ila
  run_hw_ila $ila
  puts "G5_XDMA_ILA_ARM_PASS trigger=[get_property NAME $trigger_probe]"
} elseif {$action eq "capture-wait"} {
  wait_on_hw_ila -timeout 3 $ila
  set data [upload_hw_ila_data $ila]
  set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
  set csv_path [file join $capture_dir ${timestamp}_xdma_rx.csv]
  set ila_path [file join $capture_dir ${timestamp}_xdma_rx.ila]
  write_hw_ila_data -force -csv_file $csv_path $data
  write_hw_ila_data -force $ila_path $data
  puts "G5_XDMA_ILA_CAPTURE_PASS csv=$csv_path ila=$ila_path"
} else {
  puts "G5_XDMA_ILA_STATUS_PASS action=$action device=$device"
}

close_hw_target
disconnect_hw_server
close_hw_manager
