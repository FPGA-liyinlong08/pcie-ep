# K02 standalone PHY ILA programming/capture helper.
# The ILA data bus contains the direct GTHE3_COMMON QPLL1LOCK pin. The trigger
# uses the retained gen3_test_active scalar so it is independent of probe-port
# naming in Vivado Hardware Manager.
set script_dir  [file dirname [file normalize [info script]]]
set build_dir   [file join $script_dir build_k02]
set capture_dir [file join $build_dir capture]
set bit_path    [file join $build_dir k02_pcie_phy_bringup_ila.bit]
set ltx_path    [file join $build_dir k02_pcie_phy_bringup_ila.ltx]

set server_url 127.0.0.1:3122
set action status
if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
if {[llength $argv] >= 2} { set action [lindex $argv 1] }
if {$action ni {program-arm capture-wait upload status}} {
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
set trigger_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*gen3_test_active*"}]
if {[llength $trigger_probe] != 1} {
  puts "K02 PHY ILA available probes:"
  foreach probe [get_hw_probes -of_objects $ila] {
    puts "  [get_property NAME $probe]"
  }
  error "K02 PHY ILA gen3_test_active触发探针不存在或不唯一"
}
set trigger_probe [lindex $trigger_probe 0]

if {$action eq "program-arm"} {
  set_property TRIGGER_COMPARE_VALUE eq1'b1 $trigger_probe
  set_property CONTROL.TRIGGER_POSITION 4096 $ila
  reset_hw_ila $ila
  run_hw_ila $ila
  puts "K02_PHY_ILA_ARM_PASS trigger=[get_property NAME $trigger_probe]"
} elseif {$action eq "capture-wait"} {
  wait_on_hw_ila -timeout 10 $ila
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
