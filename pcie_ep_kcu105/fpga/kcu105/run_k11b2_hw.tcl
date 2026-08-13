set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build_k11b2 hw]
set bit_path   [file join $script_dir build_k11b2 impl k11b2_gen1_endpoint.bit]
set common_tcl [file join $script_dir .. .. scripts program_ku040.tcl]

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
set ::KU040_SOURCE_ONLY 1
source $common_tcl
unset ::KU040_SOURCE_ONLY
set ku040_action [expr {$action eq "probe" ? "probe" : "program"}]
::ku040::run $server_url $bit_path $ku040_action K11B2
if {$ku040_action eq "program"} {
    puts "K11B2_HW_PROGRAM_VARIANT_PASS action=$action bitstream=[file normalize $bit_path]"
}
