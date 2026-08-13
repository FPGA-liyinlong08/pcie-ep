set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build_k02]
set bit_path   [file join $build_dir k02_pcie_phy_bringup.bit]
set common_tcl [file join $script_dir .. .. scripts program_ku040.tcl]

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
set ::KU040_SOURCE_ONLY 1
source $common_tcl
unset ::KU040_SOURCE_ONLY
::ku040::run $server_url $bit_path $action K02
