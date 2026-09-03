`timescale 1ns/1fs
`include "svt_pcie.vmm.pkg"

program xdma_x1_svt_program;
  import svt_vmm_pkg::*;
  import svt_pcie_vmm_pkg::*;
  `include "xdma_x1_svt_env.sv"

  xdma_x1_svt_env env;
  `include "xdma_x1_svt_test.sv"

  initial begin
    env = new("env");
    vmm_simulation::run_tests();
  end
endprogram
