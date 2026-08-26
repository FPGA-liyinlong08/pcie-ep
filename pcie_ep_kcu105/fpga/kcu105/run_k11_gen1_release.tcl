set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set k14_recovery_speed [expr {[info exists ::env(K14_RECOVERY_SPEED)] &&
                              $::env(K14_RECOVERY_SPEED) eq "1"}]
set phase_e2_rcvrlock_debug [expr {
  [info exists ::env(PHASE_E2_RCVRLOCK_DEBUG)] &&
  $::env(PHASE_E2_RCVRLOCK_DEBUG) eq "1"}]
set phase_e1_board_debug [expr {
  [info exists ::env(PHASE_E1_BOARD_DEBUG)] &&
  $::env(PHASE_E1_BOARD_DEBUG) eq "1"}]
set phase_e1_function_only [expr {
  [info exists ::env(PHASE_E1_FUNCTION_ONLY)] &&
  $::env(PHASE_E1_FUNCTION_ONLY) eq "1"}]
set phase_e1_timing_debug [expr {
  [info exists ::env(PHASE_E1_TIMING_DEBUG)] &&
  $::env(PHASE_E1_TIMING_DEBUG) eq "1"}]
set phase_e1_disable_reset_buffer_guard [expr {
  [info exists ::env(PHASE_E1_DISABLE_RESET_BUFFER_GUARD)] &&
  $::env(PHASE_E1_DISABLE_RESET_BUFFER_GUARD) eq "1"}]
set k14_allow_timing_failure [expr {
  [info exists ::env(K14_ALLOW_TIMING_FAILURE)] &&
  $::env(K14_ALLOW_TIMING_FAILURE) eq "1"}]
set k14_ila_depth 8192
if {[info exists ::env(K14_ILA_DEPTH)]} {
  set k14_ila_depth $::env(K14_ILA_DEPTH)
}
if {![string is integer -strict $k14_ila_depth] ||
    $k14_ila_depth ni {4096 8192}} {
  error "K14_ILA_DEPTH must be 4096 or 8192"
}
if {($phase_e1_board_debug || $phase_e2_rcvrlock_debug) &&
    !$k14_recovery_speed} {
  error "Phase E debug requires the frozen K14 Recovery.Speed path"
}
if {$phase_e1_function_only && !$k14_recovery_speed} {
  error "Phase E1 function-only build requires the frozen K14 Recovery.Speed path"
}
if {$phase_e1_function_only && ($phase_e1_board_debug || $phase_e2_rcvrlock_debug)} {
  error "Phase E1 function-only build must not combine with E1/E2 instrumentation"
}
if {$phase_e1_board_debug && $phase_e2_rcvrlock_debug} {
  error "Phase E1 and E2 debug builds must remain independent"
}
if {$phase_e1_timing_debug && !$phase_e1_board_debug} {
  error "Phase E1 timing recorder requires PHASE_E1_BOARD_DEBUG"
}
if {$phase_e1_board_debug} {
  # The normal E1 build remains the RP-directed AUTO=0 baseline.  AUTO=1 is
  # an explicitly named diagnostic variant so its bit/LTX cannot overwrite
  # the baseline artifacts.
  set build_name "build_phase_e1_board"
} elseif {$phase_e1_function_only} {
  set build_name "build_phase_e1_function_only"
} elseif {$phase_e2_rcvrlock_debug} {
  set build_name "build_phase_e2_rcvrlock"
} elseif {$k14_recovery_speed} {
  set build_name "build_k14_recovery_speed"
} else {
  set build_name "build_k11_gen1_release"
}
set phy_module pcie_phy_x1_gen3
set xci_path [file join $script_dir ip $phy_module ${phy_module}.xci]
set afifo_path /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
set part_name xcku040-ffva1156-2-e
set top_name kcu105_pcie_ep_gen1_board_top
set g9_cycles 6250000
set k14_place_directive "Default"
# E1 signoff is manually controlled by default: the board must remain in
# Gen1 L0 until the ILA is armed and the Root Port explicitly requests Gen3
# retrain.  The AUTO=1 value is reserved for the controlled diagnostic A/B.
set phase_e1_auto_retrain_cycles 0
if {[info exists ::env(PHASE_E1_AUTO_RETRAIN_CYCLES)]} {
  set phase_e1_auto_retrain_cycles $::env(PHASE_E1_AUTO_RETRAIN_CYCLES)
}
if {![string is integer -strict $phase_e1_auto_retrain_cycles] ||
    $phase_e1_auto_retrain_cycles ni {0 1}} {
  error "PHASE_E1_AUTO_RETRAIN_CYCLES must be 0 or 1"
}
if {!$phase_e1_board_debug && !$phase_e1_function_only &&
    $phase_e1_auto_retrain_cycles != 0} {
  error "AUTO retrain override is only valid for an E1 functional build"
}
if {$phase_e1_board_debug && $phase_e1_auto_retrain_cycles == 1} {
  set build_name "build_phase_e1_board_auto1"
}
if {$phase_e1_timing_debug} {
  set build_name [expr {$phase_e1_auto_retrain_cycles == 1 ?
                        "build_phase_e1_timing_auto1" :
                        "build_phase_e1_timing"}]
}
set build_dir [file join $script_dir $build_name impl]
if {[info exists ::env(G9_WAIT_REMOTE_DETECT_CYCLES)]} {
  set g9_cycles $::env(G9_WAIT_REMOTE_DETECT_CYCLES)
}
if {[info exists ::env(K14_PLACE_DIRECTIVE)]} {
  set k14_place_directive $::env(K14_PLACE_DIRECTIVE)
}
if {$g9_cycles < 1} { error "G9_WAIT_REMOTE_DETECT_CYCLES must be positive" }
if {![file exists $xci_path]} { error "K02 PHY XCI missing: $xci_path" }
if {![file exists $afifo_path]} { error "Frozen afifo dependency missing: $afifo_path" }
file mkdir $build_dir
cd $project_dir

set resume_dcp ""
if {[info exists ::env(K14_RESUME_SYNTH_DCP)]} {
  set resume_dcp [file normalize $::env(K14_RESUME_SYNTH_DCP)]
}
set resume_routed_dcp ""
if {[info exists ::env(K14_RESUME_ROUTED_DCP)]} {
  set resume_routed_dcp [file normalize $::env(K14_RESUME_ROUTED_DCP)]
}
if {$resume_routed_dcp ne ""} {
  if {!$k14_recovery_speed} { error "K14 routed resume is experimental-only" }
  if {![file exists $resume_routed_dcp]} {
    error "K14 routed checkpoint missing: $resume_routed_dcp"
  }
  open_checkpoint $resume_routed_dcp
  puts "K14_RESUME_ROUTED_PASS dcp=$resume_routed_dcp"
} elseif {$resume_dcp ne ""} {
  if {!$k14_recovery_speed} { error "K14 resume is experimental-only" }
  if {![file exists $resume_dcp]} { error "K14 resume checkpoint missing: $resume_dcp" }
  open_checkpoint $resume_dcp
  puts "K14_RESUME_SYNTH_PASS dcp=$resume_dcp"
} else {
  set_part $part_name
  read_ip $xci_path
  generate_target all [get_ips $phy_module]
  set ip_dcp [file join $script_dir ip $phy_module ${phy_module}.dcp]
  if {[file exists $ip_dcp]} { file delete -force $ip_dcp }
  synth_ip -force [get_ips $phy_module]

  read_verilog $afifo_path
  set sv_files [list \
  rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
  rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
  rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
  rtl/common/pcie_cdc_pulse.sv rtl/common/pcie_link_loss_trigger.sv \
  rtl/common/pcie_retrain_cdc_mailbox.sv \
  rtl/phy/kcu105_reset_ctrl.sv rtl/phy/kcu105_refclk_reset.sv \
  rtl/phy/kcu105_pcie_phy_wrapper.sv rtl/phy/pcie_gen12_scrambler.sv \
  rtl/phy/pcie_gen1_rx_symbol_aligner.sv rtl/phy/pcie_gen1_os_rx.sv \
  rtl/phy/pcie_gen1_os_tx.sv rtl/phy/pcie_gen3_scrambler32.sv \
  rtl/phy/pcie_gen3_os_rx.sv rtl/phy/pcie_gen3_rcvrlock_ctrl.sv \
  rtl/phy/pcie_gen3_os_tx.sv \
  rtl/phy/pcie_gen1_framer.sv rtl/phy/k02_phy_event_recorder.sv \
  rtl/phy/pcie_recovery_timing_recorder.sv \
  rtl/phy/pcie_phy_command_ctrl.sv rtl/phy/pcie_recovery_speed_ctrl.sv \
  rtl/phy/pcie_ltssm_mac_gen1.sv \
  rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv \
  rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv \
  rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv \
  rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv \
  rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv \
  rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv \
  rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv \
  sim/verilator/k09_integration/k09_tlp_test_top.sv \
  rtl/ep/k11a_offline_top.sv rtl/ep/kcu105_pcie_ep_gen1_top.sv \
  rtl/ep/kcu105_pcie_ep_gen1_board_top.sv]
  foreach f $sv_files { read_verilog -sv [file join $project_dir $f] }
  read_xdc [file join $script_dir k03_gen1_ltssm_mac.xdc]

  if {$k14_recovery_speed} {
    synth_design -top $top_name -part $part_name \
      -generic G9_WAIT_REMOTE_DETECT=1 \
      -generic G9_WAIT_REMOTE_DETECT_CYCLES=$g9_cycles \
      -generic K14_RATE_DEBUG=1 \
      -generic PHASE_E1_BOARD_DEBUG=$phase_e1_board_debug \
      -generic PHASE_E1_FUNCTION_ONLY=$phase_e1_function_only \
      -generic PHASE_E2_RCVRLOCK_DEBUG=$phase_e2_rcvrlock_debug \
      -generic GEN3_AUTO_RETRAIN_CYCLES=$phase_e1_auto_retrain_cycles \
      -generic PHASE_E1_TIMING_DEBUG=$phase_e1_timing_debug \
      -generic GEN3_RATE_CHANGE_ENABLE=1
  } else {
    synth_design -top $top_name -part $part_name \
      -generic G9_WAIT_REMOTE_DETECT=1 \
      -generic G9_WAIT_REMOTE_DETECT_CYCLES=$g9_cycles
  }
}

if {$k14_recovery_speed && $resume_routed_dcp eq ""} {
  # Preserve the synthesized design before instrumentation.  This checkpoint
  # makes ILA probe maintenance deterministic without re-running synthesis.
  write_checkpoint -force [file join $build_dir k14_pre_ila_synth.dcp]

  proc k14_net {regexp_pattern} {
    set nets [get_nets -hierarchical -quiet -regexp $regexp_pattern]
    if {[llength $nets] != 1} {
      error "K14 ILA net missing/non-unique: $regexp_pattern count=[llength $nets] candidates=[join $nets { | }]"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
  }
  proc k14_bus {regexp_pattern expected_width} {
    set nets [lsort -dictionary [get_nets -hierarchical -quiet -regexp $regexp_pattern]]
    if {[llength $nets] != $expected_width} {
      error "K14 ILA bus width mismatch: $regexp_pattern count=[llength $nets] expected=$expected_width"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
  }
  proc k14_primitive_pin {cell_ref ref_pin} {
    set cells [get_cells -hierarchical -quiet -filter "REF_NAME == $cell_ref"]
    if {[llength $cells] != 1} {
      error "K14 primitive missing/non-unique: $cell_ref count=[llength $cells]"
    }
    set pins [get_pins -quiet -of_objects [lindex $cells 0] \
                -filter "REF_PIN_NAME == $ref_pin"]
    if {[llength $pins] != 1} {
      error "K14 primitive pin missing/non-unique: $cell_ref/$ref_pin"
    }
    set nets [get_nets -quiet -of_objects $pins]
    if {[llength $nets] != 1} {
      error "K14 primitive pin has no unique net: $cell_ref/$ref_pin"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
  }
  proc k14_primitive_bus_pin {cell_ref ref_pin expected_width} {
    set cells [get_cells -hierarchical -quiet -filter "REF_NAME =~ ${cell_ref}*"]
    if {[llength $cells] != 1} {
      error "K14 primitive missing/non-unique: $cell_ref count=[llength $cells]"
    }
    set pin_pairs {}
    foreach pin [get_pins -quiet -of_objects [lindex $cells 0]] {
      set ref_pin_name [get_property REF_PIN_NAME $pin]
      if {[regexp "^${ref_pin}\\\[[0-9]+\\\]$" $ref_pin_name]} {
        set pin_nets [get_nets -quiet -of_objects $pin]
        if {[llength $pin_nets] != 1} {
          error "K14 primitive bus pin has no unique net: $cell_ref/$ref_pin_name"
        }
        lappend pin_pairs [list $ref_pin_name [lindex $pin_nets 0]]
      }
    }
    set pin_pairs [lsort -dictionary -index 0 $pin_pairs]
    set nets {}
    foreach pin_pair $pin_pairs { lappend nets [lindex $pin_pair 1] }
    if {[llength $nets] != $expected_width} {
      error "K14 primitive bus width mismatch: $cell_ref/$ref_pin count=[llength $nets] expected=$expected_width"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
  }
  proc k14_connect_recorder {pin_pattern source_net} {
    set pins [get_pins -hierarchical -quiet -regexp $pin_pattern]
    if {[llength $pins] != 1} {
      error "K14 recorder pin missing/non-unique: $pin_pattern count=[llength $pins]"
    }
    set pin [lindex $pins 0]
    set old_nets [get_nets -quiet -of_objects $pin]
    set_property DONT_TOUCH FALSE [get_nets -quiet -of_objects $pin]
    set_property DONT_TOUCH FALSE [get_nets -quiet $source_net]
    if {[llength $old_nets] == 1} {
      disconnect_net -net [lindex $old_nets 0] -pinlist [list $pin]
    }
    connect_net -hier -net $source_net -objects [list $pin]
  }
  proc k14_add_probe {core_name probe_index nets} {
    if {$probe_index != 0} { create_debug_port $core_name probe }
    set port [get_debug_ports ${core_name}/probe${probe_index}]
    set_property port_width [llength $nets] $port
    connect_debug_port $port $nets
  }
  proc k14_pin_net {regexp_pattern} {
    set pins [get_pins -hierarchical -quiet -regexp $regexp_pattern]
    if {[llength $pins] != 1} {
      error "K14 pin missing/non-unique: $regexp_pattern count=[llength $pins]"
    }
    set nets [get_nets -quiet -of_objects [lindex $pins 0]]
    if {[llength $nets] != 1} {
      error "K14 pin has no unique net: $regexp_pattern count=[llength $nets]"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
  }

  set qpll1lock_net [k14_primitive_pin GTHE3_COMMON QPLL1LOCK]
  set qpll1reset_net [k14_primitive_pin GTHE3_COMMON QPLL1RESET]
  k14_connect_recorder {.*u_k14_event_recorder/qpll1lock$} $qpll1lock_net
  k14_connect_recorder {.*u_k14_event_recorder/qpll1reset$} $qpll1reset_net
  if {$phase_e1_timing_debug} {
    set rate_reset_nets [k14_primitive_bus_pin GTHE3_CHANNEL PCIERATEQPLLRESET 2]
    k14_connect_recorder {.*u_phase_e1_timing_recorder/pcierateqpllreset$} \
      [lindex $rate_reset_nets 0]
    set rate_idle_net [k14_primitive_pin GTHE3_CHANNEL PCIERATEIDLE]
    k14_connect_recorder {.*u_phase_e1_timing_recorder/pcierateidle$} \
      $rate_idle_net
  }

  create_debug_core u_ila_k14 ila
  set_property C_DATA_DEPTH $k14_ila_depth [get_debug_cores u_ila_k14]
  set_property C_TRIGIN_EN false [get_debug_cores u_ila_k14]
  set_property C_TRIGOUT_EN false [get_debug_cores u_ila_k14]
  set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_k14]
  # The board-level phy_pclk alias is optimized into the PHY IP output net.
  # Anchor the ILA clock to the structural IP output pin so net renaming does
  # not affect the instrumentation build.
  connect_debug_port u_ila_k14/clk \
    [k14_pin_net {.*u_phy_wrapper/u_pcie_phy/phy_pclk$}]

  set probe0 [concat \
    [k14_primitive_pin GTHE3_COMMON QPLL1LOCK] \
    [k14_primitive_pin GTHE3_COMMON QPLL1RESET] \
    [k14_primitive_bus_pin GTHE3_CHANNEL PCIERATEQPLLRESET 2] \
    [k14_primitive_pin GTHE3_CHANNEL PCIERATEGEN3] \
    [k14_primitive_pin GTHE3_CHANNEL PCIEUSERGEN3RDY] \
    [k14_bus {.*k14_phy_rate_w\[[0-1]\]$} 2] \
    [k14_bus {.*k14_phy_powerdown_w\[[0-1]\]$} 2] \
    [k14_net {.*k14_phy_txei_w$}] \
    [k14_net {.*k14_detect_assist_w$}] \
    [k14_net {.*k14_cdr_hold_w$}] \
    [k14_bus {.*k14_rate_state_w\[[0-3]\]$} 4] \
    [k14_bus {.*k14_speed_state_w\[[0-2]\]$} 3] \
    [k14_bus {.*k14_ltssm_state_w\[[0-5]\]$} 6] \
    [k14_bus {.*k14_event_state_w\[[0-3]\]$} 4] \
    [k14_net {^u_endpoint/phy_phystatus$}]]
  k14_add_probe u_ila_k14 0 $probe0
  set probe1 [k14_bus {.*k14_event_record_w\[[0-9]+\]$} 118]
  k14_add_probe u_ila_k14 1 $probe1
  puts "K14_RECOVERY_ILA_INSERT_PASS probe0_width=[llength $probe0] probe1_width=[llength $probe1]"
  if {$phase_e1_board_debug} {
    set probe2 [k14_bus {.*e1_event_record_w\[[0-9]+\]$} 32]
    k14_add_probe u_ila_k14 2 $probe2
    set probe3 [concat \
      [k14_primitive_pin GTHE3_CHANNEL RXCDRLOCK] \
      [k14_primitive_pin GTHE3_CHANNEL RXRESETDONE] \
      [k14_primitive_pin GTHE3_CHANNEL PCIERATEIDLE] \
      [k14_primitive_bus_pin GTHE3_CHANNEL RXDATAVALID 2] \
      [k14_primitive_bus_pin GTHE3_CHANNEL RXHEADERVALID 2] \
      [k14_primitive_pin GTHE3_CHANNEL RXVALID]]
    k14_add_probe u_ila_k14 3 $probe3
    # A malformed-triggered capture must retain the four raw PIPE words and
    # their semantic context.  These probes are E1-only and leave the frozen
    # K14 probe0/probe1 bit ordering untouched.
    set probe4 [k14_bus {^u_endpoint/phy_rxdata\[[0-9]+\]$} 32]
    k14_add_probe u_ila_k14 4 $probe4
    set probe5 [concat \
      [k14_net {^u_endpoint/os_malformed$}] \
      [k14_net {^u_endpoint/gen3_block_locked$}] \
      [k14_net {^u_endpoint/gen3_lock_lost$}] \
      [k14_net {^u_endpoint/os_ts1_valid$}] \
      [k14_net {^u_endpoint/os_ts2_valid$}] \
      [k14_net {^u_endpoint/gen3_eieos_valid$}] \
      [k14_net {^u_endpoint/phy_rxdata_valid$}] \
      [k14_net {^u_endpoint/phy_rxstart_block$}] \
      [k14_bus {^u_endpoint/phy_rxsync_header\[[0-1]\]$} 2]]
    k14_add_probe u_ila_k14 5 $probe5
    set probe6 {}
    set probe7 {}
    if {$phase_e1_timing_debug} {
      set probe6 [k14_bus {.*phase_e1_timing_record_w\[[0-9]+\]$} 64]
      k14_add_probe u_ila_k14 6 $probe6
      set probe7 [k14_net {.*phase_e1_timing_dump_active_w$}]
      k14_add_probe u_ila_k14 7 $probe7
    }
    set probe6_width [expr {$phase_e1_timing_debug ? [llength $probe6] : 0}]
    set probe7_width [expr {$phase_e1_timing_debug ? [llength $probe7] : 0}]
    puts "PHASE_E1_BOARD_ILA_INSERT_PASS probe0_width=[llength $probe0] probe1_width=[llength $probe1] probe2_width=[llength $probe2] probe3_width=[llength $probe3] probe4_width=[llength $probe4] probe5_width=[llength $probe5] probe6_width=$probe6_width probe7_width=$probe7_width depth=$k14_ila_depth"
  } elseif {$phase_e2_rcvrlock_debug} {
    set probe2 [concat \
      [k14_net {.*e2_gen3_block_locked_w$}] \
      [k14_net {.*e2_rcvrlock_complete_w$}] \
      [k14_net {.*e2_rcvrlock_failed_w$}] \
      [k14_bus {.*e2_rx_ts_count_w\[[0-4]\]$} 5] \
      [k14_net {.*e2_os_ts1_valid_w$}] \
      [k14_net {.*e2_os_ts2_valid_w$}] \
      [k14_net {.*e2_os_malformed_w$}] \
      [k14_net {.*e2_speed_fallback_req_w$}] \
      [k14_net {.*e2_speed_fallback_active_w$}] \
      [k14_net {.*e2_phy_rxelecidle_w$}]]
    k14_add_probe u_ila_k14 2 $probe2
    set probe3 [concat \
      [k14_net {.*e2_phy_rxdata_valid_w$}] \
      [k14_net {.*e2_phy_rxstart_block_w$}] \
      [k14_bus {.*e2_phy_rxsync_header_w\[[0-1]\]$} 2] \
      [k14_net {.*e2_phy_rxvalid_w$}] \
      [k14_bus {.*e2_phy_rxstatus_w\[[0-2]\]$} 3]]
    k14_add_probe u_ila_k14 3 $probe3
    puts "PHASE_E2_RCVRLOCK_ILA_INSERT_PASS probe0_width=[llength $probe0] probe1_width=[llength $probe1] probe2_width=[llength $probe2] probe3_width=[llength $probe3] depth=$k14_ila_depth"
  }

  # Keep the existing synchronized core reset on fabric routing in E1.  With
  # the diagnostic one-shot enabled, automatic BUFG insertion can turn its
  # asynchronous-clear recovery path into the global WNS limiter even though
  # no functional datapath changed.
  if {$phase_e1_board_debug} {
    set e1_core_reset_net [get_nets -hierarchical -quiet -regexp \
      {^u_endpoint/u_phy_wrapper/u_refclk_reset/u_reset_ctrl/u_core_reset_sync/sync_reg\[3\]$}]
    if {[llength $e1_core_reset_net] != 1} {
      error "Phase E1 synchronized core reset net missing/non-unique"
    }
    if {$phase_e1_disable_reset_buffer_guard} {
      puts "PHASE_E1_RESET_BUFFER_GUARD_DISABLED net=$e1_core_reset_net"
    } else {
      set_property CLOCK_BUFFER_TYPE NONE $e1_core_reset_net
      puts "PHASE_E1_RESET_BUFFER_GUARD_PASS net=$e1_core_reset_net"
    }
  }
}

if {$resume_routed_dcp eq ""} {
  set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
    {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
  if {[llength $afifo_gray_sync_cells] == 0} { error "afifo Gray synchronizers not found" }
  set_property ASYNC_REG TRUE $afifo_gray_sync_cells
  set_property SHREG_EXTRACT NO $afifo_gray_sync_cells

  write_checkpoint -force [file join $build_dir k11_gen1_synth.dcp]
  opt_design
  if {$k14_recovery_speed} {
    place_design -directive $k14_place_directive
  } else {
    place_design
  }
  phys_opt_design -directive AggressiveExplore
  route_design -directive AggressiveExplore
  phys_opt_design -directive AggressiveExplore
  write_checkpoint -force [file join $build_dir k11_gen1_routed.dcp]
}
report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 50 -sort_by group \
  -file [file join $build_dir timing_paths_50.rpt]
check_timing -verbose -file [file join $build_dir check_timing.rpt]
report_cdc -details -file [file join $build_dir cdc_routed.rpt]
report_drc -file [file join $build_dir drc.rpt]

proc require_port_pin {port_name expected_pin} {
  set port_object [get_ports $port_name]
  if {[llength $port_object] != 1} { error "Missing top port: $port_name" }
  set actual_pin [get_property PACKAGE_PIN $port_object]
  if {![string equal -nocase $actual_pin $expected_pin]} {
    error "Pin mismatch $port_name=$actual_pin expected=$expected_pin"
  }
}
require_port_pin pcie_refclk_p AB6
require_port_pin pcie_refclk_n AB5
require_port_pin pcie_perst_n K22
require_port_pin pcie_rxp AB2
require_port_pin pcie_rxn AB1
require_port_pin pcie_txp AC4
require_port_pin pcie_txn AC3

set gth_channels [get_cells -hierarchical -filter {REF_NAME == GTHE3_CHANNEL}]
set gth_commons [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1 ||
    ![string equal -nocase [get_property LOC $gth_channels] GTHE3_CHANNEL_X0Y7]} {
  error "GTHE3 channel placement mismatch"
}
if {[llength $gth_commons] != 1 ||
    ![string equal -nocase [get_property LOC $gth_commons] GTHE3_COMMON_X0Y1]} {
  error "GTHE3 common placement mismatch"
}
set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
  REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} { error "Unexpected PCIe hard block count=$hard_pcie_count" }

proc require_hierarchy_count {module_name expected} {
  set cells [get_cells -quiet -hierarchical -filter "ORIG_REF_NAME == $module_name"]
  if {[llength $cells] == 0} {
    set cells [get_cells -quiet -hierarchical -filter "REF_NAME == $module_name"]
  }
  if {[llength $cells] != $expected} {
    error "$module_name hierarchy count=[llength $cells] expected=$expected"
  }
}
require_hierarchy_count pcie_phy_command_ctrl 1
require_hierarchy_count pcie_ltssm_mac_gen1 1
require_hierarchy_count pcie_dll 1
require_hierarchy_count pcie_cfg_space 1
require_hierarchy_count pcie_bar_axil_master 1
require_hierarchy_count demo_axil_slave 1
if {$k14_recovery_speed} {
  require_hierarchy_count pcie_recovery_speed_ctrl 1
  require_hierarchy_count pcie_retrain_cdc_mailbox 1
}

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
set max_path [get_timing_paths -delay_type max -max_paths 1]
set min_path [get_timing_paths -delay_type min -max_paths 1]
set wns [get_property SLACK $max_path]
set whs [get_property SLACK $min_path]
set setup_floor [expr {$phase_e1_board_debug ? -0.093 :
                       ($phase_e2_rcvrlock_debug ? -0.060 : 0.000)}]
if {$wns < $setup_floor && !$k14_allow_timing_failure} {
  error "Implementation setup timing WNS=$wns below floor=$setup_floor"
}
if {$wns < $setup_floor && $k14_allow_timing_failure} {
  puts "K14_TIMING_GUARD_BYPASS WNS=$wns floor=$setup_floor"
}
if {[llength $hold_paths] != 0} { error "Gen1 release has negative hold timing" }
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
  error "DRC contains Error or Critical Warning"
}
if {!$k14_recovery_speed && [llength [get_debug_cores -quiet]] != 0} {
  error "Debug core found in release"
}
if {$k14_recovery_speed && [llength [get_debug_cores -quiet u_ila*]] != 1} {
  error "K14 experimental build requires exactly one ILA"
}

if {$phase_e1_board_debug} {
  set impl_pass "PHASE_E1_BOARD_IMPL_PASS"
  set bit_name "phase_e1_board_ila.bit"
} elseif {$phase_e1_function_only} {
  set impl_pass "PHASE_E1_FUNCTION_ONLY_IMPL_PASS"
  set bit_name "phase_e1_function_only_ila.bit"
} elseif {$phase_e2_rcvrlock_debug} {
  set impl_pass "PHASE_E2_RCVRLOCK_IMPL_PASS"
  set bit_name "phase_e2_rcvrlock_ila.bit"
} elseif {$k14_recovery_speed} {
  set impl_pass "K14_RECOVERY_SPEED_IMPL_PASS"
  set bit_name "k14_recovery_speed_ila.bit"
} else {
  set impl_pass "K11_GEN1_COMMAND_BOUNDARY_IMPL_PASS"
  set bit_name "k11b2_gen1_endpoint.bit"
}
set bit_path [file join $build_dir $bit_name]
write_bitstream -force $bit_path
if {$k14_recovery_speed} {
  if {$phase_e1_board_debug} {
    set ltx_name "phase_e1_board_ila.ltx"
  } elseif {$phase_e2_rcvrlock_debug} {
    set ltx_name "phase_e2_rcvrlock_ila.ltx"
  } else {
    set ltx_name "k14_recovery_speed_ila.ltx"
  }
  write_debug_probes -force [file join $build_dir $ltx_name]
}
set summary [open [file join $build_dir summary.txt] w]
puts $summary $impl_pass
puts $summary "part=$part_name"
puts $summary "top=$top_name"
puts $summary "G9_WAIT_REMOTE_DETECT=1"
puts $summary "G9_WAIT_REMOTE_DETECT_CYCLES=$g9_cycles"
puts $summary "PHY_COMMAND_CTRL_COUNT=1"
puts $summary "GEN3_RATE_CHANGE_ENABLE=$k14_recovery_speed"
if {$k14_recovery_speed} {
  puts $summary "K14_PLACE_DIRECTIVE=$k14_place_directive"
}
puts $summary "PHASE_E2_RCVRLOCK_DEBUG=$phase_e2_rcvrlock_debug"
puts $summary "PHASE_E1_BOARD_DEBUG=$phase_e1_board_debug"
puts $summary "PHASE_E1_FUNCTION_ONLY=$phase_e1_function_only"
puts $summary "GEN3_AUTO_RETRAIN_CYCLES=$phase_e1_auto_retrain_cycles"
puts $summary "PHASE_E1_TIMING_DEBUG=$phase_e1_timing_debug"
puts $summary "K14_ILA_DEPTH=$k14_ila_depth"
puts $summary "SETUP_TIMING_FLOOR=$setup_floor"
puts $summary "WNS=$wns"
puts $summary "WHS=$whs"
puts $summary "DRC_ERROR_COUNT=[llength $drc_errors]"
puts $summary "DEBUG_CORE_COUNT=[llength [get_debug_cores -quiet]]"
puts $summary "bitstream=$bit_path"
close $summary
puts "$impl_pass WNS=$wns WHS=$whs"
