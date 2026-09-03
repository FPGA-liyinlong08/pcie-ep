class xdma_x1_svt_test extends vmm_test;
  `vmm_typename(xdma_x1_svt_test)
  xdma_x1_svt_pcie_cfg cust_cfg;
  xdma_x1_svt_link_scenario scenario;

  function new(string name);
    super.new(name);
  endfunction

  virtual function void gen_config_ph();
    cust_cfg = new();
    cust_cfg.setup_defaults();
    vmm_opts::set_object("env:cfg", cust_cfg);
  endfunction

  virtual function void configure_test_ph();
    super.configure_test_ph();
    scenario = new(env.root_status);
    env.root.driver_transaction_ms_scenario_gen[0].register_ms_scenario(
      "xdma_x1_svt_link", scenario);
  endfunction
endclass

xdma_x1_svt_test t_xdma_x1_svt_test = new("xdma_x1_svt_test");
