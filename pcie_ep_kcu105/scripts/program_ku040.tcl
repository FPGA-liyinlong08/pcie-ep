# Common KU040 JTAG probe/program helper.
#
# Direct invocation from Vivado batch mode:
#   vivado -mode batch -source scripts/program_ku040.tcl \
#       -tclargs localhost:3122 path/to/image.bit program
#   vivado -mode batch -source scripts/program_ku040.tcl \
#       -tclargs localhost:3122 - probe
#
# When source-ing this file from another Tcl wrapper, set
# ::KU040_SOURCE_ONLY before source-ing it.

namespace eval ::ku040 {
    proc run {server_url bit_path action {label KU040}} {
        if {$action ni {probe program}} {
            error "$label Hardware action必须为 probe 或 program"
        }
        if {$action eq "program" && ![file exists $bit_path]} {
            error "$label bitstream不存在：$bit_path"
        }

        set target_open 0
        set manager_open 0
        set status [catch {
            open_hw_manager
            set manager_open 1
            connect_hw_server -url $server_url -allow_non_jtag
            open_hw_target
            set target_open 1

            set devices [get_hw_devices]
            if {[llength $devices] == 0} {
                error "$label 没有发现 JTAG Hardware Device"
            }
            puts "${label}_HW_DEVICE_COUNT=[llength $devices]"
            foreach device $devices {
                puts "${label}_HW_DEVICE name=$device part=[get_property PART $device]"
            }

            set ku040_devices [get_hw_devices -filter {PART =~ "xcku040*"}]
            if {[llength $ku040_devices] != 1} {
                error "$label 期望唯一 xcku040，实际数量 [llength $ku040_devices]"
            }
            set ku040 [lindex $ku040_devices 0]

            if {$action eq "program"} {
                set_property PROGRAM.FILE [file normalize $bit_path] $ku040
                program_hw_devices $ku040
                refresh_hw_device $ku040
                puts "${label}_HW_PROGRAM_PASS device=$ku040 bitstream=[file normalize $bit_path]"
            } else {
                puts "${label}_HW_PROBE_PASS device=$ku040 part=[get_property PART $ku040]"
            }
        } result options]

        if {$target_open} {
            catch {close_hw_target}
        }
        if {$manager_open} {
            catch {disconnect_hw_server}
            catch {close_hw_manager}
        }
        if {$status} {
            return -options $options $result
        }
        return $result
    }
}

if {![info exists ::KU040_SOURCE_ONLY]} {
    set server_url localhost:3122
    set bit_path ""
    set action probe
    if {[llength $argv] >= 1} { set server_url [lindex $argv 0] }
    if {[llength $argv] >= 2} { set bit_path [lindex $argv 1] }
    if {[llength $argv] >= 3} { set action [lindex $argv 2] }
    if {$action eq "program" && $bit_path eq ""} {
        error "program动作必须提供bitstream路径"
    }
    ::ku040::run $server_url $bit_path $action KU040
}
