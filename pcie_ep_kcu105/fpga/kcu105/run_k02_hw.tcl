set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build_k02]
set bit_path   [file join $build_dir k02_pcie_phy_bringup.bit]

set server_url localhost:3122
set action probe
if {[llength $argv] >= 1} {
    set server_url [lindex $argv 0]
}
if {[llength $argv] >= 2} {
    set action [lindex $argv 1]
}
if {$action ni {probe program}} {
    error "K02 Hardware action 必须为 probe 或 program"
}

file mkdir $build_dir
open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    error "K02 没有发现 JTAG Hardware Device"
}

puts "K02_HW_DEVICE_COUNT=[llength $devices]"
foreach device $devices {
    puts "K02_HW_DEVICE name=$device part=[get_property PART $device]"
}

set ku040_devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $ku040_devices] != 1} {
    error "K02 期望唯一 xcku040，实际数量 [llength $ku040_devices]"
}
set ku040 [lindex $ku040_devices 0]

if {$action eq "program"} {
    if {![file exists $bit_path]} {
        error "K02 bitstream 不存在：$bit_path"
    }
    set_property PROGRAM.FILE $bit_path $ku040
    program_hw_devices $ku040
    refresh_hw_device $ku040
    puts "K02_HW_PROGRAM_PASS device=$ku040 bitstream=$bit_path"
} else {
    puts "K02_HW_PROBE_PASS device=$ku040 part=[get_property PART $ku040]"
}

close_hw_target
disconnect_hw_server
close_hw_manager
