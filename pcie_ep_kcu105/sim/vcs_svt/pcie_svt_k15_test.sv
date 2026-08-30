class k15_svt_x1_test extends vmm_test;
  `vmm_typename(k15_svt_x1_test)
  k15_svt_pcie_cfg cust_cfg;
  k15_svt_x1_scenario scenario;

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
    scenario = new(cust_cfg.root_cfg, env.root_status);
    env.root.driver_transaction_ms_scenario_gen[0].register_ms_scenario(
      "k15_svt_x1_scenario", scenario);
  endfunction
endclass

k15_svt_x1_test t_k15_svt_x1_test = new("k15_svt_x1_test");

class k14_svt_x1_test extends vmm_test;
  `vmm_typename(k14_svt_x1_test)
  k15_svt_pcie_cfg cust_cfg;
  k14_svt_x1_scenario scenario;

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
    scenario = new(cust_cfg.root_cfg, env.root_status);
    env.root.driver_transaction_ms_scenario_gen[0].register_ms_scenario(
      "k14_svt_x1_scenario", scenario);
  endfunction
endclass

k14_svt_x1_test t_k14_svt_x1_test = new("k14_svt_x1_test");
