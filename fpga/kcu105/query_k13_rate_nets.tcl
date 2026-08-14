set dcp [file normalize [lindex $argv 0]]
open_checkpoint $dcp
set patterns {
  {.*pcie_phy_x1_gen3_gt_i/pcierateidle_out\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/pcieuserratestart_out\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/pcieusergen3rdy_out\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/pcierategen3_out\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/pcierateqpllreset_out\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/pcierateqpllpd_out\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/pcieuserratedone_in\[[0-9]+\]$}
  {.*pcie_phy_x1_gen3_gt_i/rxrate_in\[[0-9]+\]$}
}
foreach pattern $patterns {
  set nets [lsort -dictionary [get_nets -hierarchical -quiet -regexp $pattern]]
  puts "PATTERN=$pattern"
  foreach net $nets { puts "  NET=$net" }
}
close_design
