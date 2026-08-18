set script_dir [file dirname [file normalize [info script]]]
set k02_direct_gen3 [expr {[info exists ::env(K02_DIRECT_GEN3)] &&
                            $::env(K02_DIRECT_GEN3) eq "1"}]
set k02_dynamic_rate [expr {[info exists ::env(K02_DYNAMIC_GEN1_TO_GEN3)] &&
                             $::env(K02_DYNAMIC_GEN1_TO_GEN3) eq "1"}]
set k02_coeff_query [expr {[info exists ::env(K02_DYNAMIC_COEFF_QUERY)] &&
                           $::env(K02_DYNAMIC_COEFF_QUERY) eq "1"}]
set k02_off_gap [expr {[info exists ::env(K02_DYNAMIC_GEN1_OFF_GAP)] &&
                       $::env(K02_DYNAMIC_GEN1_OFF_GAP) eq "1"}]
if {$k02_coeff_query} { set k02_dynamic_rate 1 }
if {$k02_direct_gen3} {
    set build_dir [file join $script_dir build_k02_gen3]
    set bit_stem k02_pcie_phy_bringup_gen3
} elseif {$k02_dynamic_rate} {
    if {$k02_off_gap && $k02_coeff_query} {
        set build_dir [file join $script_dir build_k02_dynamic_offgap_query]
        set bit_stem k02_pcie_phy_bringup_dynamic_offgap_query
    } elseif {$k02_off_gap} {
        set build_dir [file join $script_dir build_k02_dynamic_offgap]
        set bit_stem k02_pcie_phy_bringup_dynamic_offgap
    } elseif {$k02_coeff_query} {
        set build_dir [file join $script_dir build_k02_dynamic_query]
        set bit_stem k02_pcie_phy_bringup_dynamic_query
    } else {
        set build_dir [file join $script_dir build_k02_dynamic]
        set bit_stem k02_pcie_phy_bringup_dynamic
    }
} else {
    set build_dir [file join $script_dir build_k02]
    set bit_stem k02_pcie_phy_bringup
}
set k02_ila_debug [expr {![info exists ::env(K02_ILA_DEBUG)] ||
                          $::env(K02_ILA_DEBUG) eq "1"}]
set bit_name [expr {$k02_ila_debug ? "${bit_stem}_ila.bit" :
                                    "${bit_stem}.bit"}]
set bit_path   [file join $build_dir $bit_name]
set common_tcl [file join $script_dir .. .. scripts program_ku040.tcl]

set server_url 127.0.0.1:3122
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
