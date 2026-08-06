set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set build_dir   [file join $script_dir build_k02]
set ip_root     [file join $script_dir ip]
set xci_path    [file join $ip_root pcie_phy_x1_gen3 pcie_phy_x1_gen3.xci]
set part_name   xcku040-ffva1156-2-e

file mkdir $build_dir
file mkdir $ip_root

# 整个 pcie_phy_x1_gen3 目录都是 Tcl 可再生物。先删除旧输出可避免 Vivado
# 在已有 IP 目录内再次创建同名子目录，保证连续生成的目录层级也确定。
set ip_module_dir [file join $ip_root pcie_phy_x1_gen3]
if {[file exists $ip_module_dir]} {
    file delete -force $ip_module_dir
}

create_project -force k02_phy_ip [file join $build_dir ip_project] -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

create_ip -name pcie_phy -vendor xilinx.com -library ip -version 1.0 \
    -module_name pcie_phy_x1_gen3 -dir $ip_root

set phy_ip [get_ips pcie_phy_x1_gen3]
if {[llength $phy_ip] != 1} {
    error "K02 无法创建唯一的 pcie_phy_x1_gen3 IP"
}

# 配置与 KCU105/KU040 K02 架构冻结值保持一一对应。
set_property -dict [list \
    CONFIG.phy_lane             {X1} \
    CONFIG.phy_max_speed        {8.0_GT/s} \
    CONFIG.phy_refclk_freq      {100_MHz} \
    CONFIG.phy_userclk_freq     {125_MHz} \
    CONFIG.phy_coreclk_freq     {250_MHz} \
    CONFIG.lane0_gt_bank        {GTH_Quad_225} \
    CONFIG.lane0_gt_location    {GTHE3_CHANNEL_X0Y7} \
    CONFIG.refclk1_location     {Bank_225_MGTREFCLK0} \
    CONFIG.pll_type             {QPLL1} \
    CONFIG.pipeline_stages      {0} \
    CONFIG.ins_loss_profile     {Add-in_Card} \
    CONFIG.aspm                 {No_ASPM} \
    CONFIG.Shared_Logic         {1} \
    CONFIG.gtwiz_in_core        {1} \
    CONFIG.gtcom_in_core        {1} \
    CONFIG.rx_detect            {Default} \
    CONFIG.tx_preset            {4} \
    CONFIG.phy_async_en         {true} \
] $phy_ip

set expected_config [dict create \
    phy_lane             X1 \
    phy_max_speed        8.0_GT/s \
    phy_refclk_freq      100_MHz \
    phy_userclk_freq     125_MHz \
    phy_coreclk_freq     250_MHz \
    lane0_gt_bank        GTH_Quad_225 \
    lane0_gt_location    GTHE3_CHANNEL_X0Y7 \
    refclk1_location     Bank_225_MGTREFCLK0 \
    pll_type             QPLL1 \
    pipeline_stages      0 \
    ins_loss_profile     Add-in_Card \
    aspm                 No_ASPM \
    Shared_Logic         1 \
    gtwiz_in_core        1 \
    gtcom_in_core        1 \
    rx_detect            Default \
    tx_preset            4 \
    phy_async_en         true]

dict for {name expected} $expected_config {
    set actual [get_property CONFIG.$name $phy_ip]
    if {![string equal -nocase $actual $expected]} {
        error "K02 IP 配置错误：CONFIG.$name=$actual，期望 $expected"
    }
}

generate_target all $phy_ip

if {![file exists $xci_path]} {
    error "K02 XCI 未生成：$xci_path"
}

set summary_path [file join $build_dir ip_generation_summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "K02_IP_GENERATION_PASS"
puts $summary_file "part=$part_name"
puts $summary_file "vlnv=xilinx.com:ip:pcie_phy:1.0"
dict for {name expected} $expected_config {
    puts $summary_file "CONFIG.$name=[get_property CONFIG.$name $phy_ip]"
}
puts $summary_file "xci=$xci_path"
close $summary_file

puts "K02_IP_GENERATION_PASS xci=$xci_path"
close_project
