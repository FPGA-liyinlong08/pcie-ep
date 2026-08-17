# Build the pcie_phy_0_ex KCU105 standalone PHY debug image.
# The image performs Receiver Detect, Gen1 bring-up, TXEQ preset, then
# Gen1->Gen3 rate change.  The ILA includes the physical GTHE3_COMMON QPLL1LOCK
# pin, so a captured LOCK loss is distinguishable from a PIPE/PHY failure.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $script_dir build_k02_dynamic]
set part_name   xcku040-ffva1156-2-e
set xci_path    [file join $project_dir pcie_phy_0_ex.srcs sources_1 ip pcie_phy_0 pcie_phy_0.xci]

file mkdir $build_dir
set_part $part_name
read_ip $xci_path
generate_target all [get_ips pcie_phy_0]
synth_ip -force [get_ips pcie_phy_0]

foreach source_file {
    pcie_reset_sync.sv
    kcu105_reset_ctrl.sv
    kcu105_refclk_reset.sv
    kcu105_pcie_phy_wrapper.sv
    kcu105_pcie_phy_bringup_top.sv
} {
    read_verilog -sv [file join $script_dir $source_file]
}
read_xdc [file join $script_dir pcie_phy_0_kcu105.xdc]

synth_design -top kcu105_pcie_phy_bringup_top -part $part_name \
    -generic GEN3_TEST_MODE=1 \
    -generic DYNAMIC_RATE_TEST_MODE=1 \
    -generic DYNAMIC_COEFF_QUERY_MODE=0 \
    -generic DIRECT_GEN3_MODE=0 \
    -generic DYNAMIC_START_DELAY_CYCLES=1000000000 \
    -generic DYNAMIC_GEN1_STABLE_CYCLES=1024 \
    -generic DYNAMIC_TXEQ_TIMEOUT_CYCLES=8192 \
    -generic DYNAMIC_GEN3_TIMEOUT_CYCLES=32768

proc one_net {pattern} {
    set nets [get_nets -hierarchical -quiet -regexp $pattern]
    if {[llength $nets] != 1} {
        error "Expected one net for $pattern, got [llength $nets]: [join $nets { | }]"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
}

proc one_pin_net {ref_name ref_pin} {
    set cells [get_cells -hierarchical -quiet -filter "REF_NAME == $ref_name"]
    if {[llength $cells] != 1} {
        error "Expected one $ref_name, got [llength $cells]"
    }
    set pins [get_pins -quiet -of_objects [lindex $cells 0] \
        -filter "REF_PIN_NAME == $ref_pin"]
    if {[llength $pins] != 1} {
        error "Expected one $ref_name/$ref_pin, got [llength $pins]"
    }
    set nets [get_nets -quiet -of_objects $pins]
    if {[llength $nets] != 1} {
        error "Expected one net on $ref_name/$ref_pin, got [llength $nets]"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
}

proc debug_bus {pattern width} {
    set nets [lsort -dictionary [get_nets -hierarchical -quiet -regexp $pattern]]
    if {[llength $nets] != $width} {
        error "Expected $width nets for $pattern, got [llength $nets]: [join $nets { | }]"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
}

proc debug_pin_bus {ref_name ref_pin width} {
    set cells [get_cells -hierarchical -quiet -filter "REF_NAME == $ref_name"]
    if {[llength $cells] != 1} { error "Expected one $ref_name" }
    set pairs {}
    foreach pin [get_pins -quiet -of_objects [lindex $cells 0]] {
        set ref_pin_name [get_property REF_PIN_NAME $pin]
        if {[regexp "^${ref_pin}\\\[[0-9]+\\\]$" $ref_pin_name]} {
            set nets [get_nets -quiet -of_objects $pin]
            if {[llength $nets] != 1} { error "No unique net for $ref_pin_name" }
            lappend pairs [list $ref_pin_name [lindex $nets 0]]
        }
    }
    set pairs [lsort -dictionary -index 0 $pairs]
    if {[llength $pairs] != $width} {
        error "Expected $width pins for $ref_name/$ref_pin, got [llength $pairs]"
    }
    set result {}
    foreach pair $pairs {
        lappend result [lindex $pair 1]
    }
    set_property MARK_DEBUG TRUE $result
    return $result
}

proc add_probe {core index nets} {
    if {$index != 0} { create_debug_port $core probe }
    set port [get_debug_ports ${core}/probe${index}]
    set_property port_width [llength $nets] $port
    connect_debug_port $port $nets
}

set gth_common [get_cells -hierarchical -quiet -filter {REF_NAME == GTHE3_COMMON}]
set gth_channel [get_cells -hierarchical -quiet -filter {REF_NAME == GTHE3_CHANNEL}]
if {[llength $gth_common] != 1 || [llength $gth_channel] != 1} {
    error "Expected one GTHE3_COMMON and one GTHE3_CHANNEL; got \
        [llength $gth_common] and [llength $gth_channel]"
}
create_debug_core u_ila_phy ila
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_phy]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_phy]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_phy]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_phy]
connect_debug_port u_ila_phy/clk [one_net {(^|/)phy_pclk$}]

# probe0: QPLL lock/reset/loss, GT rate handshake, PIPE rate and PHY status.
set probe0 [concat \
    [one_pin_net GTHE3_COMMON QPLL1LOCK] \
    [one_pin_net GTHE3_COMMON QPLL1RESET] \
    [one_pin_net GTHE3_COMMON QPLL1PD] \
    [one_pin_net GTHE3_COMMON QPLL1REFCLKLOST] \
    [one_pin_net GTHE3_COMMON QPLL1FBCLKLOST] \
    [one_pin_net GTHE3_CHANNEL GTPOWERGOOD] \
    [one_pin_net GTHE3_CHANNEL PCIEUSERRATESTART] \
    [one_pin_net GTHE3_CHANNEL PCIERATEIDLE] \
    [debug_pin_bus GTHE3_CHANNEL PCIERATEQPLLRESET 2] \
    [debug_pin_bus GTHE3_CHANNEL PCIERATEQPLLPD 2] \
    [debug_bus {.*phy_rate_debug\[[0-9]+\]$} 2] \
    [debug_bus {.*phy_powerdown_debug\[[0-9]+\]$} 2] \
    [one_net {^u_phy_wrapper/phy_phystatus$}] \
    [one_net {.*phy_txeq_done_debug$}] \
    [debug_bus {.*phy_txeq_ctrl_debug\[[0-9]+\]$} 2] \
    [debug_bus {.*phy_txeq_preset_debug\[[0-9]+\]$} 4]]
add_probe u_ila_phy 0 $probe0

# probe1: dynamic test state and reset/receiver evidence.
set probe1 [concat \
    [debug_bus {.*dynamic_rate_state\[[0-9]+\]$} 4] \
    [one_net {.*dynamic_rate_txeq_active$}] \
    [one_net {.*dynamic_rate_pass$}] \
    [one_net {.*dynamic_rate_fail$}] \
    [one_net {.*gen3_test_active$}] \
    [one_net {.*detect_done$}] \
    [one_net {.*receiver_present$}] \
    [one_net {.*detect_timeout$}] \
    [one_net {^u_phy_wrapper/phy_phystatus_rst$}]]
add_probe u_ila_phy 1 $probe1

opt_design
place_design
if {[string toupper [get_property LOC $gth_common]] ne "GTHE3_COMMON_X0Y1"} {
    error "Unexpected GTHE3_COMMON LOC after placement: [get_property LOC $gth_common]"
}
if {[string toupper [get_property LOC $gth_channel]] ne "GTHE3_CHANNEL_X0Y7"} {
    error "Unexpected GTHE3_CHANNEL LOC after placement: [get_property LOC $gth_channel]"
}
route_design
phys_opt_design

report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_drc -file [file join $build_dir drc.rpt]
report_cdc -details -file [file join $build_dir cdc.rpt]

set bit_path [file join $build_dir pcie_phy_0_ex_gen1_to_gen3_ila.bit]
set ltx_path [file join $build_dir pcie_phy_0_ex_gen1_to_gen3_ila.ltx]
write_debug_probes -force $ltx_path
write_bitstream -force $bit_path

set summary [open [file join $build_dir impl_summary.txt] w]
puts $summary "PCIE_PHY_0_EX_DYNAMIC_IMPL_PASS"
puts $summary "part=$part_name"
puts $summary "GTHE3_COMMON_LOC=[get_property LOC $gth_common]"
puts $summary "GTHE3_CHANNEL_LOC=[get_property LOC $gth_channel]"
puts $summary "probe0_width=[llength $probe0]"
puts $summary "probe1_width=[llength $probe1]"
puts $summary "bitstream=$bit_path"
puts $summary "probes=$ltx_path"
close $summary
puts "PCIE_PHY_0_EX_DYNAMIC_IMPL_PASS bitstream=$bit_path probes=$ltx_path"
