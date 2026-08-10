set script_dir [file dirname [file normalize [info script]]]
set bit_path  [file join $script_dir build xdma_x1_demo.bit]

set server_url localhost:3122
if {[llength $argv] >= 1} {
    set server_url [lindex $argv 0]
}

if {![file exists $bit_path]} {
    error "XDMA x1 bitstream不存在：$bit_path；请先执行make xdma-x1-demo"
}

open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target

set ku040_devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $ku040_devices] != 1} {
    error "XDMA x1下载期望唯一xcku040，实际数量[llength $ku040_devices]"
}
set ku040 [lindex $ku040_devices 0]

set_property PROGRAM.FILE $bit_path $ku040
program_hw_devices $ku040
refresh_hw_device $ku040

puts "XDMA_X1_HW_PROGRAM_PASS device=$ku040 bitstream=$bit_path"

close_hw_target
disconnect_hw_server
close_hw_manager
