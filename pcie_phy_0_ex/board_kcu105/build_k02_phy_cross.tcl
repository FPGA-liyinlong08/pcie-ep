# Build the 2x2 controller x PHY IP cell #3 image: the proven Xilinx
# phy_ctrl.v + phy_bringup_seq drive K02's pcie_phy_x1_gen3 XCI
# (8.0_GT/s, QPLL1, GTHE3_CHANNEL_X0Y7, Add-in_Card, tx_preset 4).
#
# Pass criterion: identical to baseline pcie_phy_0_ex Hardware Golden -
# the seq_state must walk S_POWER_UP -> S_GEN1_HOLD -> S_GEN1_OFF_GAP ->
# S_GEN3_HOLD -> S_DONE, and phy_ctrl's debug_state must reach 8'h04 at
# least once during the S_GEN3_WAIT window with QPLL1 doing 1->0->1.
# Failure of this combination is the evidence that K02's PHY IP / GT
# configuration contributes to the K02 FSM failure.
#
# K02's IP XCI is reused as-is from
#   pcie_ep_kcu105/fpga/kcu105/ip/pcie_phy_x1_gen3/pcie_phy_x1_gen3.xci
# so this build does NOT regenerate the IP.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set imports_dir [file join $project_dir imports]
set build_dir   [file join $script_dir build_k02_phy_cross]
set part_name   xcku040-ffva1156-2-e

# K02 IP XCI is the same xilinx.com:ip:pcie_phy:1.0 IP as the baseline
# pcie_phy_0, just generated with K02's settings and a different module
# name.  Read it directly; do not regenerate.
set k02_ip_root [file normalize [file join $script_dir ../.. \
    pcie_ep_kcu105 fpga kcu105 ip pcie_phy_x1_gen3]]
set xci_path    [file join $k02_ip_root pcie_phy_x1_gen3.xci]
if {![file exists $xci_path]} {
    error "K02 PHY IP XCI 不存在: $xci_path - 请先 make k02-ip"
}

file mkdir $build_dir
set_part $part_name
read_ip $xci_path
generate_target all [get_ips pcie_phy_x1_gen3]
synth_ip -force [get_ips pcie_phy_x1_gen3]

foreach source_file {
    phy_ctrl_pat_gen_lane.v
    phy_ctrl_pat_gen.v
    phy_ctrl.v
} {
    read_verilog [file join $imports_dir $source_file]
}

foreach source_file {
    pcie_reset_sync.sv
    kcu105_reset_ctrl.sv
    kcu105_refclk_reset.sv
    phy_bringup_seq.sv
    kcu105_pcie_phy_wrapper_k02.sv
    kcu105_pcie_phy_bringup_top_k02.sv
} {
    read_verilog -sv [file join $script_dir $source_file]
}
read_xdc [file join $script_dir pcie_phy_0_kcu105.xdc]

synth_design -top kcu105_pcie_phy_bringup_top_k02 -part $part_name \
    -generic SEQ_CLK_HZ=250000000 \
    -generic WAIT_AFTER_READY_NS=10000 \
    -generic WAIT_AFTER_GEN1_ON_NS=5000 \
    -generic GEN1_HOLD_NS=50000 \
    -generic WAIT_AFTER_GEN1_OFF_NS=10000 \
    -generic GEN3_HOLD_NS=80000

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
    if {[llength $cells] != 1} { error "Expected one $ref_name, got [llength $cells]" }
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
    foreach pair $pairs { lappend result [lindex $pair 1] }
    set_property MARK_DEBUG TRUE $result
    return $result
}

proc add_probe {core index nets} {
    if {$index != 0} { create_debug_port $core probe }
    set port [get_debug_ports ${core}/probe${index}]
    set_property port_width [llength $nets] $port
    connect_debug_port $port $nets
}

set gth_common  [get_cells -hierarchical -quiet -filter {REF_NAME == GTHE3_COMMON}]
set gth_channel [get_cells -hierarchical -quiet -filter {REF_NAME == GTHE3_CHANNEL}]
if {[llength $gth_common] != 1 || [llength $gth_channel] != 1} {
    error "Expected one GTHE3_COMMON and one GTHE3_CHANNEL; got \
        [llength $gth_common] and [llength $gth_channel]"
}

create_debug_core u_ila_phy_golden_k02 ila
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_phy_golden_k02]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_phy_golden_k02]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_phy_golden_k02]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_phy_golden_k02]
connect_debug_port u_ila_phy_golden_k02/clk [one_net {(^|/)phy_pclk$}]

# probe0: requested PHY/GT rate-change and status evidence.
set probe0 [concat \
    [debug_bus {^phy_rate\[[0-9]+\]$} 3] \
    [one_net {^phy_phystatus_debug$}] \
    [debug_bus {^debug_state\[[0-9]+\]$} 8] \
    [one_net {^as_mac_in_detect$}] \
    [one_net {^as_cdr_hold_req$}] \
    [one_pin_net GTHE3_COMMON QPLL1RESET] \
    [one_pin_net GTHE3_COMMON QPLL1LOCK] \
    [debug_pin_bus GTHE3_CHANNEL PCIERATEQPLLRESET 2] \
    [one_pin_net GTHE3_CHANNEL PCIERATEGEN3] \
    [one_pin_net GTHE3_CHANNEL PCIEUSERGEN3RDY] \
    [one_pin_net GTHE3_COMMON QPLL1REFCLKLOST] \
    [one_pin_net GTHE3_COMMON QPLL1FBCLKLOST]]
add_probe u_ila_phy_golden_k02 0 $probe0

# probe1: exact board.v stimulus and sequence timing context.
set probe1 [concat \
    [debug_bus {^seq_state\[[0-9]+\]$} 4] \
    [one_net {^gen3_request$}] \
    [one_net {^tx_elec_idle$}] \
    [one_net {^phy_ready_en$}] \
    [one_net {^gen1_en$}] \
    [one_net {^gen2_en$}] \
    [one_net {^gen3_en$}] \
    [one_net {^gen4_en$}] \
    [one_net {^phy_phystatus_rst_debug$}]]
add_probe u_ila_phy_golden_k02 1 $probe1

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

set bit_path [file join $build_dir pcie_phy_0_ex_hardware_golden_k02_phy_ila.bit]
set ltx_path [file join $build_dir pcie_phy_0_ex_hardware_golden_k02_phy_ila.ltx]
write_debug_probes -force $ltx_path
write_bitstream -force $bit_path

set summary [open [file join $build_dir impl_summary.txt] w]
puts $summary "K02_PHY_CROSS_IMPL_PASS"
puts $summary "controller=Golden_phy_ctrl"
puts $summary "phy_ip=K02_pcie_phy_x1_gen3"
puts $summary "k02_xci=$xci_path"
puts $summary "part=$part_name"
puts $summary "GTHE3_COMMON_LOC=[get_property LOC $gth_common]"
puts $summary "GTHE3_CHANNEL_LOC=[get_property LOC $gth_channel]"
puts $summary "probe0_width=[llength $probe0]"
puts $summary "probe1_width=[llength $probe1]"
puts $summary "bitstream=$bit_path"
puts $summary "probes=$ltx_path"
close $summary
puts "K02_PHY_CROSS_IMPL_PASS bitstream=$bit_path probes=$ltx_path"
