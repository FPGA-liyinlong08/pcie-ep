class k14_golden_svt_x1_test extends vmm_test;
  `vmm_typename(k14_golden_svt_x1_test)
  k14_golden_svt_cfg cust_cfg;
  k14_golden_gate_scenario scenario;

  function new(string name); super.new(name); endfunction

  virtual function void gen_config_ph();
    cust_cfg = new();
    cust_cfg.setup_defaults();
    vmm_opts::set_object("env:cfg", cust_cfg);
  endfunction

  virtual function void configure_test_ph();
    super.configure_test_ph();
    scenario = new(cust_cfg.root_cfg, env.root_status);
    env.root.driver_transaction_ms_scenario_gen[0].register_ms_scenario(
      "k14_golden_gate_scenario", scenario);
  endfunction
endclass

k14_golden_svt_x1_test t_k14_golden_svt_x1_test =
  new("k14_golden_svt_x1_test");
