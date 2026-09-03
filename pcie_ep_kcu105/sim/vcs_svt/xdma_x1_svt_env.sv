`ifndef GUARD_XDMA_X1_SVT_ENV_SV
`define GUARD_XDMA_X1_SVT_ENV_SV

class xdma_x1_svt_pcie_cfg extends vmm_object;
  static vmm_log log = new("xdma_x1_svt_pcie_cfg", "class");
  rand svt_pcie_device_configuration root_cfg;

  function new(string name = "xdma_x1_svt_pcie_cfg", vmm_object parent = null);
    super.new(parent, name);
    root_cfg = new(log);
  endfunction

  virtual function string get_class_name();
    return "xdma_x1_svt_pcie_cfg";
  endfunction

  function void setup_defaults();
    root_cfg.device_is_root = 1;
    root_cfg.pcie_spec_ver = svt_pcie_device_configuration::PCIE_SPEC_VER_3_0;
    root_cfg.pipe_spec_ver = svt_pcie_device_configuration::PIPE_SPEC_VER_4;
    root_cfg.pcie_cfg.pl_cfg.set_link_width_values(1, 32'h0000_0001, 1);
    root_cfg.pcie_cfg.pl_cfg.set_link_speed_values(
      `SVT_PCIE_SPEED_2_5G | `SVT_PCIE_SPEED_5_0G | `SVT_PCIE_SPEED_8_0G,
      `SVT_PCIE_SPEED_8_0G,
      `SVT_PCIE_SPEED_8_0G);
    root_cfg.pcie_cfg.pl_cfg.skip_polling_active = 1;
    root_cfg.pcie_cfg.pl_cfg.downstream_lanes_recovery_eq_phase1_timeout_ns = 100000;
    root_cfg.pcie_cfg.stop_after_n_dl_service_insts = 1;
    root_cfg.pcie_cfg.stop_after_n_dl_service_scenarios = 1;
    root_cfg.pcie_cfg.stop_after_n_pl_service_insts = 1;
    root_cfg.pcie_cfg.stop_after_n_pl_service_scenarios = 1;
    root_cfg.stop_after_n_driver_trans_insts = 1;
    root_cfg.stop_after_n_driver_trans_scenarios = 1;
    root_cfg.driver_cfg[0].enable_shadow_memory_checking = 0;
    root_cfg.pcie_cfg.enable_transaction_logging = 1;
    root_cfg.pcie_cfg.transaction_log_filename = "xdma_x1_svt_transaction.log";
    root_cfg.pcie_cfg.enable_symbol_logging = 1;
    root_cfg.pcie_cfg.symbol_log_filename = "xdma_x1_svt_symbol.log";
  endfunction
endclass

class xdma_x1_svt_dl_link_scenario extends vmm_ms_scenario;
  svt_pcie_dl_service blueprint;
  svt_pcie_dl_configuration dl_cfg;

  `vmm_scenario_new(xdma_x1_svt_dl_link_scenario)
  `vmm_scenario_member_begin(xdma_x1_svt_dl_link_scenario)
    `vmm_scenario_member_vmm_data(blueprint, DO_ALL, DO_REFCOPY)
    `vmm_scenario_member_vmm_data(dl_cfg, DO_ALL, DO_REFCOPY)
  `vmm_scenario_member_end(xdma_x1_svt_dl_link_scenario)
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
      `vmm_error(log, "Failed to randomize SVT link enable service");
    else begin
      out_chan.put(blueprint);
      n++;
    end
  endtask

  `vmm_class_factory(xdma_x1_svt_dl_link_scenario)
endclass

class xdma_x1_svt_equalization_scenario extends vmm_ms_scenario;
  svt_pcie_pl_service blueprint;
  svt_pcie_pl_configuration pl_cfg;
  svt_pcie_device_status root_status;

  `vmm_scenario_new(xdma_x1_svt_equalization_scenario)
  `vmm_scenario_member_begin(xdma_x1_svt_equalization_scenario)
    `vmm_scenario_member_vmm_data(blueprint, DO_ALL, DO_REFCOPY)
    `vmm_scenario_member_vmm_data(pl_cfg, DO_ALL, DO_REFCOPY)
  `vmm_scenario_member_end(xdma_x1_svt_equalization_scenario)
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
    vmm_channel out_chan;
    wait (root_status.pcie_status.pl_status.link_up == 1'b1 &&
          root_status.pcie_status.pl_status.ltssm_state == svt_pcie_types::L0);
    out_chan = get_channel("pl_svc_chan");
    ok = blueprint.randomize() with {
      service_type == svt_pcie_pl_service::PERFORM_EQUALIZATION;
    };
    if (!ok)
      `vmm_error(log, "Failed to randomize SVT equalization service");
    else begin
      out_chan.put(blueprint);
      n++;
    end
  endtask

  `vmm_class_factory(xdma_x1_svt_equalization_scenario)
endclass

class xdma_x1_svt_env extends vmm_group;
  vmm_consensus consensus;
  svt_pcie_device_group root;
  svt_pcie_device_status root_status;
  xdma_x1_svt_pcie_cfg cfg;
  xdma_x1_svt_dl_link_scenario link_scenario;
  xdma_x1_svt_equalization_scenario eq_scenario;

  function new(string inst = "", string name = "xdma_x1_svt_env",
               vmm_object parent = null);
    super.new(name, inst, parent);
    consensus = new("xdma_x1_svt_consensus", {log.get_instance(), ".consensus"});
  endfunction

  virtual function void build_ph();
    xdma_x1_svt_pcie_cfg new_cfg;
    super.build_ph();
    if ($cast(new_cfg, vmm_opts::get_object_obj(is_set, this, "cfg", cfg)))
      cfg = new_cfg;
    else begin
      cfg = new("cfg", this);
      cfg.setup_defaults();
    end
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
      "xdma_x1_svt_link", link_scenario);
    eq_scenario = new(cfg.root_cfg.pcie_cfg.pl_cfg, root_status);
    root.pcie_group.pl_svc_ms_scenario_gen.register_ms_scenario(
      "xdma_x1_svt_equalization", eq_scenario);
  endfunction

  virtual task run_ph();
    fork
      begin consensus.wait_for_consensus(); #3000; end
      begin
        #5000000;
        `vmm_error(log, "XDMA x1 SVT timeout waiting for consensus");
        consensus.display();
      end
    join_any
    disable fork;
  endtask
endclass

class xdma_x1_svt_link_scenario extends vmm_ms_scenario;
  svt_pcie_device_status root_status;

  `vmm_scenario_new(xdma_x1_svt_link_scenario)
  function new(svt_pcie_device_status root_status = null);
    super.new(null);
    this.root_status = root_status;
  endfunction

  virtual task execute(ref int n);
    bit timed_out = 0;
    bit stable_ok = 1;
    int stable_cycles = 0;
    int stable_skp_cycles = 0;
    fork
      begin
        wait (root_status.pcie_status.pl_status.link_up == 1'b1 &&
              root_status.pcie_status.pl_status.ltssm_state == svt_pcie_types::L0 &&
              root_status.pcie_status.pl_status.negotiated_speed ==
                svt_pcie_pl_status::SPEED_8_0G &&
              root_status.pcie_status.pl_status.negotiated_link_width == 1);
      end
      begin #3000000; timed_out = 1; end
    join_any
    disable fork;
    if (timed_out) begin
      $display("XDMA_X1_SVT_FAIL reason=gen3_x1_l0_timeout");
      `vmm_error(log, "Official XDMA endpoint did not reach Gen3 x1 L0");
    end else begin
      // This is intentionally a separate marker from the stability result:
      // entering L0 is not evidence that the first SDS/data/SKP stream was
      // accepted.  8192 PIPE cycles at Gen3 cover many SKP and clock-
      // compensation opportunities before declaring the Golden stable.
      $display("XDMA_SVT_GEN3_L0_PASS speed=8.0GT/s width=1");
      repeat (8192) begin
        @(posedge test_top.root0.port0.pipe_clk);
        #1;
        stable_cycles++;
        if (test_top.root0.port0.pcs0_rx_start_block)
          stable_skp_cycles++;
        if (!(root_status.pcie_status.pl_status.link_up == 1'b1 &&
              root_status.pcie_status.pl_status.ltssm_state ==
                svt_pcie_types::L0 &&
              root_status.pcie_status.pl_status.negotiated_speed ==
                svt_pcie_pl_status::SPEED_8_0G &&
              root_status.pcie_status.pl_status.negotiated_link_width == 1))
          stable_ok = 0;
        if ((test_top.root0.port0.pcs0_rx_sync_header == 2'b11) ||
            (test_top.root0.port0.pcs0_rx_status != 0) ||
            (test_top.root0.port0.pcs0_rx_ei_code != 0))
          stable_ok = 0;
      end
      if (stable_ok) begin
        $display("XDMA_SVT_L0_STABLE_PASS cycles=%0d skp_observed=%0d",
                 stable_cycles, stable_skp_cycles);
        $display("XDMA_X1_SVT_PASS speed=8.0GT/s width=1 stable=1");
      end else begin
        $display("XDMA_SVT_L0_STABLE_FAIL cycles=%0d skp_observed=%0d",
                 stable_cycles, stable_skp_cycles);
        $display("XDMA_X1_SVT_FAIL reason=gen3_l0_unstable");
        `vmm_error(log, "Official XDMA endpoint entered Gen3 L0 but did not remain stable");
      end
    end
    n++;
  endtask
endclass

`endif
