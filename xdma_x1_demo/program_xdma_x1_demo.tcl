set script_dir [file dirname [file normalize [info script]]]
set bit_path  [file join $script_dir build xdma_x1_demo.bit]
set common_tcl [file join $script_dir .. .. .. scripts program_ku040.tcl]

set server_url localhost:3122
if {[llength $argv] >= 1} {
    set server_url [lindex $argv 0]
}

if {![file exists $bit_path]} {
    error "XDMA x1 bitstream不存在：$bit_path；请先执行make xdma-x1-demo"
}

set ::KU040_SOURCE_ONLY 1
source $common_tcl
unset ::KU040_SOURCE_ONLY
::ku040::run $server_url $bit_path program XDMA_X1
