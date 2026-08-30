`ifndef GUARD_PCIE_SVT_K14_GOLDEN_ENV_SV
`define GUARD_PCIE_SVT_K14_GOLDEN_ENV_SV

class k14_golden_svt_cfg extends vmm_object;
  static vmm_log log = new("k14_golden_svt_cfg", "class");
  rand svt_pcie_device_configuration root_cfg;

  function new(string name = "k14_golden_svt_cfg", vmm_object parent = null);
    super.new(parent, name);
    root_cfg = new(log);
  endfunction

  virtual function string get_class_name();
    return "k14_golden_svt_cfg";
  endfunction

  function void setup_defaults();
    root_cfg.device_is_root = 1;
    root_cfg.pcie_spec_ver = svt_pcie_device_configuration::PCIE_SPEC_VER_3_0;
    root_cfg.pipe_spec_ver = svt_pcie_device_configuration::PIPE_SPEC_VER_4;
    root_cfg.pcie_cfg.pl_cfg.set_link_width_values(1, 32'h0000_0001, 1);
    root_cfg.pcie_cfg.pl_cfg.set_link_speed_values(
      `SVT_PCIE_SPEED_2_5G | `SVT_PCIE_SPEED_5_0G | `SVT_PCIE_SPEED_8_0G,
      `SVT_PCIE_SPEED_8_0G, `SVT_PCIE_SPEED_8_0G);
    root_cfg.pcie_cfg.pl_cfg.skip_polling_active = 1;
    root_cfg.pcie_cfg.pl_cfg.downstream_lanes_recovery_eq_phase1_timeout_ns = 100000;
    root_cfg.pcie_cfg.stop_after_n_dl_service_insts = 1;
    root_cfg.pcie_cfg.stop_after_n_dl_service_scenarios = 1;
    root_cfg.pcie_cfg.stop_after_n_pl_service_insts = 2;
    root_cfg.pcie_cfg.stop_after_n_pl_service_scenarios = 1;
    root_cfg.stop_after_n_driver_trans_insts = 1;
    root_cfg.stop_after_n_driver_trans_scenarios = 1;
    root_cfg.driver_cfg[0].enable_shadow_memory_checking = 0;
    root_cfg.pcie_cfg.enable_transaction_logging = 1;
    root_cfg.pcie_cfg.transaction_log_filename = "k14_golden_svt_x1_transaction.log";
    root_cfg.pcie_cfg.enable_symbol_logging = 1;
    root_cfg.pcie_cfg.symbol_log_filename = "k14_golden_svt_x1_symbol.log";
  endfunction
endclass

class k14_golden_link_scenario extends vmm_ms_scenario;
  svt_pcie_dl_service blueprint;
  svt_pcie_dl_configuration dl_cfg;
  `vmm_scenario_new(k14_golden_link_scenario)

  function new(svt_pcie_dl_configuration dl_cfg = null);
    super.new(null);
    this.dl_cfg = dl_cfg;
    blueprint = svt_pcie_dl_service::create_instance(
      this, "blueprint", `__FILE__, `__LINE__);
    blueprint.cfg = dl_cfg;
  endfunction

  virtual task execute(ref int n);
    bit ok;
    vmm_channel out_chan = get_channel("dl_svc_chan");
    ok = blueprint.randomize() with {
      service_type == svt_pcie_dl_service::SET_LINK_ENABLE;
      enable == 1;
    };
    if (!ok)
      `vmm_error(log, "Failed to randomize SVT Link Enable service");
    else begin out_chan.put(blueprint); n++; end
  endtask
  `vmm_class_factory(k14_golden_link_scenario)
endclass

class k14_golden_equalization_scenario extends vmm_ms_scenario;
  svt_pcie_pl_service blueprint;
  svt_pcie_pl_configuration pl_cfg;
  svt_pcie_device_status root_status;
  `vmm_scenario_new(k14_golden_equalization_scenario)

  function new(svt_pcie_pl_configuration pl_cfg = null,
               svt_pcie_device_status root_status = null);
    super.new(null);
    this.pl_cfg = pl_cfg;
    this.root_status = root_status;
    blueprint = svt_pcie_pl_service::create_instance(
      this, "blueprint", `__FILE__, `__LINE__);
    blueprint.cfg = pl_cfg;
  endfunction

  virtual task execute(ref int n);
    bit ok;
    int epoch;
    vmm_channel out_chan = get_channel("pl_svc_chan");
    if (out_chan == null)
      `vmm_fatal(log, "Could not get SVT PL service channel");
    for (epoch = 0; epoch < 1; epoch++) begin
      wait (test_top.reset_epoch_count >= epoch + 1);
      wait (root_status.pcie_status.pl_status.link_up == 1'b1 &&
            root_status.pcie_status.pl_status.ltssm_state == svt_pcie_types::L0);
      ok = blueprint.randomize() with {
        service_type == svt_pcie_pl_service::PERFORM_EQUALIZATION;
      };
      if (!ok)
        `vmm_error(log, "Failed to randomize SVT equalization service");
      else begin
        $display("K14_GOLDEN_SVT_EQ_REQUEST epoch=%0d", epoch);
        out_chan.put(blueprint);
        n++;
      end
    end
  endtask
  `vmm_class_factory(k14_golden_equalization_scenario)
endclass

class k14_golden_svt_env extends vmm_group;
  vmm_consensus consensus;
  svt_pcie_device_group root;
  svt_pcie_device_status root_status;
  k14_golden_svt_cfg cfg;
  k14_golden_link_scenario link_scenario;
  k14_golden_equalization_scenario eq_scenario;

  function new(string inst = "", string name = "k14_golden_svt_env",
               vmm_object parent = null);
    super.new(name, inst, parent);
    consensus = new("k14_golden_svt_consensus", {log.get_instance(), ".consensus"});
  endfunction

  virtual function void build_ph();
    k14_golden_svt_cfg new_cfg;
    super.build_ph();
    if ($cast(new_cfg, vmm_opts::get_object_obj(is_set, this, "cfg", cfg)))
      cfg = new_cfg;
    else begin cfg = new("cfg", this); cfg.setup_defaults(); end
    cfg.root_cfg.model_instance_scope = "test_top.root0";
    root_status = svt_pcie_device_status::create_instance(this, "root_status");
    vmm_opts::set_object("root:cfg", cfg.root_cfg, this);
    vmm_opts::set_object("root:shared_status", root_status, this);
    root = new("root", "root", this, consensus);
  endfunction

  virtual function void configure_test_ph();
    super.configure_test_ph();
    link_scenario = new(cfg.root_cfg.pcie_cfg.dl_cfg);
    root.pcie_group.dl_svc_ms_scenario_gen.register_ms_scenario(
      "k14_golden_link", link_scenario);
    eq_scenario = new(cfg.root_cfg.pcie_cfg.pl_cfg, root_status);
    root.pcie_group.pl_svc_ms_scenario_gen.register_ms_scenario(
      "k14_golden_equalization", eq_scenario);
  endfunction

  virtual task run_ph();
    fork
      begin consensus.wait_for_consensus(); #3000; end
      begin #5000000; `vmm_error(log, "K14 Golden SVT consensus timeout"); end
    join_any
    disable fork;
  endtask
endclass

class k14_golden_gate_scenario extends vmm_ms_scenario;
  svt_pcie_device_configuration drv_cfg;
  svt_pcie_device_status root_status;
  `vmm_scenario_new(k14_golden_gate_scenario)

  function new(svt_pcie_device_configuration drv_cfg = null,
               svt_pcie_device_status root_status = null);
    super.new(null);
    this.drv_cfg = drv_cfg;
    this.root_status = root_status;
  endfunction

  task automatic wait_for_golden_contract(output bit timed_out);
    timed_out = 0;
    fork
      begin
        wait(test_top.seen_partner_accept && test_top.seen_gen3_rate &&
             test_top.seen_qpll_lock && test_top.seen_gen3_phystatus);
      end
      // The SVT Recovery.RcvrLock watchdog is 240 us.  Allow more than twice
      // that interval for the K14 PHY contract, without idling for milliseconds
      // after the VIP has already abandoned Recovery.
      begin #600000; timed_out = 1; end
    join_any
    disable fork;
  endtask

  virtual task execute(ref int n);
    bit timed_out;
    int epoch;
    wait (test_top.reset_epoch_count >= 1);
    for (epoch = 0; epoch < 1; epoch++) begin
      wait_for_golden_contract(timed_out);
      if (timed_out) begin
        test_top.display_diagnostics();
        $display("K14_GOLDEN_SVT_X1_FAIL epoch=%0d reason=rate_qpll_phystatus_timeout", epoch);
        `vmm_error(log, $sformatf(
          "K14 Golden epoch %0d did not complete rate/QPLL/PhyStatus", epoch));
        n++;
        #1000;
        $finish;
      end
      $display("K14_GOLDEN_SVT_X1_EPOCH_PASS epoch=%0d", epoch);
    end
    $display("K14_GOLDEN_SVT_X1_PASS epochs=1");
    n++;
  endtask
endclass

`endif
