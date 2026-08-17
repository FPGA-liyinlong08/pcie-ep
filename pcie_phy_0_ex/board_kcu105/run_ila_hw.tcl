# Program and capture the pcie_phy_0_ex dynamic Gen1->Gen3 ILA.
# Usage:
#   vivado -mode batch -source run_ila_hw.tcl -tclargs localhost:3122 program-arm
#   vivado -mode batch -source run_ila_hw.tcl -tclargs localhost:3122 capture-wait

set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build_k02_dynamic]
set bit_path   [file join $build_dir pcie_phy_0_ex_gen1_to_gen3_ila.bit]
set ltx_path   [file join $build_dir pcie_phy_0_ex_gen1_to_gen3_ila.ltx]
set capture_dir [file join $build_dir capture]
set server_url localhost:3122
set action program-arm
if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
if {[llength $argv] >= 2} { set action [lindex $argv 1] }
if {$action ni {program-arm program-arm-fail capture-wait upload status}} {
    error "action must be program-arm, program-arm-fail, capture-wait, upload, or status"
}
if {![file exists $bit_path] || ![file exists $ltx_path]} {
    error "bit/ltx not found under $build_dir"
}
file mkdir $capture_dir

open_hw_manager
connect_hw_server -url $server_url -allow_non_jtag
open_hw_target
set devices [get_hw_devices -filter {PART =~ "xcku040*"}]
if {[llength $devices] != 1} { error "Expected one xcku040, got [llength $devices]" }
set device [lindex $devices 0]
set_property PROBES.FILE $ltx_path $device
set_property FULL_PROBES.FILE $ltx_path $device
if {$action eq "program-arm" || $action eq "program-arm-fail"} {
    set_property PROGRAM.FILE $bit_path $device
    program_hw_devices $device
}
refresh_hw_device $device
set ilas [get_hw_ilas -of_objects $device]
if {[llength $ilas] != 1} { error "Expected one ILA, got [llength $ilas]" }
set ila [lindex $ilas 0]

if {$action eq "program-arm" || $action eq "program-arm-fail"} {
    set trigger_name dynamic_rate_txeq_active
    if {$action eq "program-arm-fail"} { set trigger_name dynamic_rate_fail }
    set trigger [get_hw_probes -of_objects $ila -filter [format {NAME =~ "*%s*"} $trigger_name]]
    if {[llength $trigger] != 1} { error "${trigger_name} probe not found" }
    set_property CONTROL.TRIGGER_POSITION 4096 $ila
    reset_hw_ila $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b1 [lindex $trigger 0]
    run_hw_ila $ila
    puts "PCIE_PHY_0_EX_ILA_ARM_PASS device=$device ila=$ila trigger=$trigger_name"
} elseif {$action eq "capture-wait"} {
    wait_on_hw_ila -timeout 20 $ila
    set data [upload_hw_ila_data $ila]
    set stamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
    write_hw_ila_data -force -csv_file [file join $capture_dir ${stamp}_phy.csv] $data
    write_hw_ila_data -force [file join $capture_dir ${stamp}_phy.ila] $data
    puts "PCIE_PHY_0_EX_ILA_CAPTURE_PASS capture_dir=$capture_dir"
} elseif {$action eq "upload"} {
    set data [upload_hw_ila_data $ila]
    set stamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
    write_hw_ila_data -force -csv_file [file join $capture_dir ${stamp}_phy.csv] $data
    write_hw_ila_data -force [file join $capture_dir ${stamp}_phy.ila] $data
    puts "PCIE_PHY_0_EX_ILA_UPLOAD_PASS capture_dir=$capture_dir"
} else {
    puts "PCIE_PHY_0_EX_ILA_STATUS_PASS device=$device ila=$ila"
}

close_hw_target
disconnect_hw_server
close_hw_manager
