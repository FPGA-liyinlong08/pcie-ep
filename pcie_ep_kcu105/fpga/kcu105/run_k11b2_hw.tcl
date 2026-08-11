set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build_k11b2 hw]
set bit_path   [file join $script_dir build_k11b2 impl k11b2_gen1_endpoint.bit]

set server_url localhost:3122
set action probe
if {[llength $argv] >= 1} {
    set server_url [lindex $argv 0]
}
if {[llength $argv] >= 2} {
    set action [lindex $argv 1]
}
if {$action ni {probe program program-debug program-g2-gen1}} {
    error "K11-B2 Hardware action必须为probe、program、program-debug或program-g2-gen1"
}

if {$action eq "program-debug"} {
    set bit_path [file join $script_dir build_k11b2 impl \
                      k11b2_gen1_endpoint_debug.bit]
}
if {$action eq "program-g2-gen1"} {
    set bit_path [file join $script_dir build_g2_gen1 impl \
                      g2_gen1_cpll_endpoint.bit]
}

file mkdir $build_dir
open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target

set devices [get_hw_devices]
puts "K11B2_HW_DEVICE_COUNT=[llength $devices]"
foreach device $devices {
    puts "K11B2_HW_DEVICE name=$device part=[get_property PART $device]"
}

set ku040_devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $ku040_devices] != 1} {
    error "K11-B2期望唯一xcku040，实际数量[llength $ku040_devices]"
}
set ku040 [lindex $ku040_devices 0]

if {$action in {program program-debug program-g2-gen1}} {
    if {![file exists $bit_path]} {
        error "K11-B2 bitstream不存在：$bit_path"
    }
    set_property PROGRAM.FILE $bit_path $ku040
    program_hw_devices $ku040
    refresh_hw_device $ku040
    puts "K11B2_HW_PROGRAM_PASS action=$action device=$ku040 bitstream=$bit_path"
} else {
    puts "K11B2_HW_PROBE_PASS device=$ku040 part=[get_property PART $ku040]"
}

close_hw_target
disconnect_hw_server
close_hw_manager
