`timescale 1ns/1fs
`include "svt_pcie.vmm.pkg"

program pcie_svt_k14_golden_x1;
  import svt_vmm_pkg::*;
  import svt_pcie_vmm_pkg::*;
  `include "pcie_svt_k14_golden_env.sv"

  k14_golden_svt_env env;
  `include "pcie_svt_k14_golden_test.sv"

  initial begin
    env = new("env");
    vmm_simulation::run_tests();
  end
endprogram
