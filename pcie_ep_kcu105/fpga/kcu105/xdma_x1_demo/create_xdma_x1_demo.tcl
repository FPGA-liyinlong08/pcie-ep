set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir build]
set ip_dir     [file join $build_dir ip]
set example_dir [file join $build_dir example]
set part_name  xcku040-ffva1156-2-e

file delete -force $build_dir
file mkdir $ip_dir
create_project -force xdma_x1_ip $ip_dir -part $part_name
create_ip -name xdma -vendor xilinx.com -library ip -version 4.1 \
    -module_name xdma_x1

set xdma [get_ips xdma_x1]
set_property -dict [list \
    CONFIG.mode_selection {Advanced} \
    CONFIG.functional_mode {DMA} \
    CONFIG.device_port_type {PCI_Express_Endpoint_device} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.pl_link_cap_max_link_width {X1} \
    CONFIG.ref_clk_freq {100_MHz} \
    CONFIG.en_gt_selection {true} \
    CONFIG.select_quad {GTH_Quad_225} \
    CONFIG.pcie_blk_locn {X0Y0} \
    CONFIG.axisten_freq {250} \
    CONFIG.vendor_id {10EE} \
    CONFIG.pf0_device_id {9031}] $xdma

generate_target all $xdma
export_ip_user_files -of_objects $xdma -no_script -sync -force -quiet
puts "XDMA_X1_IP_PASS width=[get_property CONFIG.pl_link_cap_max_link_width $xdma] quad=[get_property CONFIG.select_quad $xdma]"

open_example_project -force -dir $example_dir $xdma
puts "XDMA_X1_EXAMPLE_PASS project=[current_project] top=[get_property TOP [current_fileset]]"
save_project_as -force xdma_x1_example [file join $example_dir xdma_x1_example]
close_project
