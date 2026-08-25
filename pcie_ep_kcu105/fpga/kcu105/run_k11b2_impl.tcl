set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set ila_debug   [expr {[info exists ::env(K11B2_ILA_DEBUG)] &&
                       $::env(K11B2_ILA_DEBUG) eq "1"}]
set k13_enable  [expr {[info exists ::env(K13_ENABLE)] &&
                       $::env(K13_ENABLE) eq "1"}]
set k13_rxeq_bootstrap [expr {![info exists ::env(K13_RXEQ_BOOTSTRAP)] ||
                              $::env(K13_RXEQ_BOOTSTRAP) ne "0"}]
set k13_rxeq_two_pass [expr {[info exists ::env(K13_RXEQ_TWO_PASS)] &&
                             $::env(K13_RXEQ_TWO_PASS) eq "1"}]
set k13_pre_rate_txeq_enable [expr {![info exists ::env(K13_PRE_RATE_TXEQ_ENABLE)] ||
                                     $::env(K13_PRE_RATE_TXEQ_ENABLE) ne "0"}]
set k13_golden_rate_replay [expr {[info exists ::env(K13_GOLDEN_RATE_REPLAY)] &&
                                  $::env(K13_GOLDEN_RATE_REPLAY) eq "1"}]
set k13_minimal_diag [expr {[info exists ::env(K13_MINIMAL_DIAG)] &&
                            $::env(K13_MINIMAL_DIAG) eq "1"}]
set k13_gt_rate_done_tie_high [expr {[info exists ::env(K13_GT_RATE_DONE_TIE_HIGH)] &&
                                     $::env(K13_GT_RATE_DONE_TIE_HIGH) eq "1"}]
set k13_gt_rate_done_start_pulse [expr {[info exists ::env(K13_GT_RATE_DONE_START_PULSE)] &&
                                        $::env(K13_GT_RATE_DONE_START_PULSE) eq "1"}]
set k13_gt_rate_done_reset_release_pulse [expr {[info exists ::env(K13_GT_RATE_DONE_RESET_RELEASE_PULSE)] &&
                                                $::env(K13_GT_RATE_DONE_RESET_RELEASE_PULSE) eq "1"}]
set k13_cdr_hold_recovery [expr {[info exists ::env(K13_CDR_HOLD_RECOVERY)] &&
                                  $::env(K13_CDR_HOLD_RECOVERY) eq "1"}]
set k13_cdr_hold_force_low [expr {[info exists ::env(K13_CDR_HOLD_FORCE_LOW)] &&
                                  $::env(K13_CDR_HOLD_FORCE_LOW) eq "1"}]
set k13_gt_rate_qpll_reset_forward [expr {[info exists ::env(K13_GT_RATE_QPLL_RESET_FORWARD)] &&
                                          $::env(K13_GT_RATE_QPLL_RESET_FORWARD) eq "1"}]
set k13_gt_primitive_debug [expr {[info exists ::env(K13_GT_PRIMITIVE_DEBUG)] &&
                                  $::env(K13_GT_PRIMITIVE_DEBUG) eq "1"}]
set k13_gt_qpll_prereq_debug [expr {[info exists ::env(K13_GT_QPLL_PREREQ_DEBUG)] &&
                                    $::env(K13_GT_QPLL_PREREQ_DEBUG) eq "1"}]
set k13_gt_rate_direct_source [expr {$k13_gt_rate_done_tie_high ||
                                     $k13_gt_rate_done_start_pulse ||
                                     $k13_gt_rate_done_reset_release_pulse ||
                                     $k13_gt_rate_qpll_reset_forward ||
                                     $k13_gt_primitive_debug ||
                                     $k13_gt_qpll_prereq_debug ||
                                     $k13_minimal_diag}]
set ila_pipe_only [expr {$ila_debug && [info exists ::env(K11B2_ILA_PIPE_ONLY)] &&
                         $::env(K11B2_ILA_PIPE_ONLY) eq "1"}]
set g2_gen1_only [expr {[info exists ::env(G2_GEN1_ONLY)] &&
                        $::env(G2_GEN1_ONLY) eq "1"}]
set g7_rx_p0_quiet [expr {[info exists ::env(G7_RX_P0_QUIET)] &&
                          $::env(G7_RX_P0_QUIET) eq "1"}]
set g8_fast_detect [expr {[info exists ::env(G8_FAST_DETECT)] &&
                          $::env(G8_FAST_DETECT) eq "1"}]
set g9_wait_remote_detect [expr {[info exists ::env(G9_WAIT_REMOTE_DETECT)] &&
                                 $::env(G9_WAIT_REMOTE_DETECT) eq "1"}]
set g10_cfg_complete [expr {[info exists ::env(G10_CFG_COMPLETE)] &&
                            $::env(G10_CFG_COMPLETE) eq "1"}]
set g11_rx_parser [expr {[info exists ::env(G11_RX_PARSER)] &&
                         $::env(G11_RX_PARSER) eq "1"}]
set g12_ordered_set [expr {[info exists ::env(G12_ORDERED_SET)] &&
                           $::env(G12_ORDERED_SET) eq "1"}]
set g9_wait_remote_detect_cycles 6250000
if {[info exists ::env(G9_WAIT_REMOTE_DETECT_CYCLES)]} {
  set g9_wait_remote_detect_cycles $::env(G9_WAIT_REMOTE_DETECT_CYCLES)
}
if {$ila_debug &&
    ($g9_wait_remote_detect || $g10_cfg_complete || $g11_rx_parser || $g12_ordered_set)} {
  # G9只需要PIPE域结果；省下Core ILA资源和等待一个永远不会触发的Core核。
  set ila_pipe_only 1
}
if {$k13_minimal_diag && (!$k13_enable || !$ila_debug)} {
  error "K13_MINIMAL_DIAG requires K13_ENABLE=1 and K11B2_ILA_DEBUG=1"
}
if {$k13_minimal_diag} {
  # The compact PIPE ILA is the only timing-clean diagnostic artifact.  The
  # core ILA and wide packet probes are not part of this experiment.
  set ila_pipe_only 1
  # The minimal artifact must retain the direct GT evidence and QPLL reference
  # selection probe; make these requirements implicit in the build switch.
  set k13_gt_primitive_debug 1
  set k13_gt_qpll_prereq_debug 1
}
if {$ila_debug && $g2_gen1_only} {
  error "G2 Gen1/CPLL诊断构建不支持ILA模式"
}
if {$k13_gt_primitive_debug && (!$k13_enable || !$ila_debug)} {
  error "K13_GT_PRIMITIVE_DEBUG requires K13_ENABLE=1 and K11B2_ILA_DEBUG=1"
}
if {$k13_gt_qpll_prereq_debug && (!$k13_enable || !$ila_debug || !$k13_gt_primitive_debug)} {
  error "K13_GT_QPLL_PREREQ_DEBUG requires K13_ENABLE=1, K11B2_ILA_DEBUG=1 and K13_GT_PRIMITIVE_DEBUG=1"
}
if {$g7_rx_p0_quiet && !$ila_debug} {
  error "G7 Detect.Quiet P0诊断必须启用K11B2_ILA_DEBUG"
}
if {$g8_fast_detect && !$ila_debug} {
  error "G8快速首次Detect诊断必须启用K11B2_ILA_DEBUG"
}
if {$g10_cfg_complete && !$ila_debug} {
  error "G10 CFG_COMPLETE诊断必须启用K11B2_ILA_DEBUG"
}
if {$g11_rx_parser && !$ila_debug} {
  error "G11 RX解析诊断必须启用K11B2_ILA_DEBUG"
}
if {$g10_cfg_complete && !$g9_wait_remote_detect} {
  error "G10 CFG_COMPLETE诊断必须保留G9 WAIT_REMOTE_DETECT基线"
}
if {$g11_rx_parser && !$g9_wait_remote_detect} {
  error "G11 RX解析诊断必须保留G9 WAIT_REMOTE_DETECT基线"
}
if {$g12_ordered_set && !$g9_wait_remote_detect} {
  error "G12 Ordered Set边界诊断必须保留G9 WAIT_REMOTE_DETECT基线"
}
if {$g9_wait_remote_detect && $g9_wait_remote_detect_cycles < 1} {
  error "G9_WAIT_REMOTE_DETECT_CYCLES必须大于0"
}
if {[llength [lsearch -all -inline [list $g7_rx_p0_quiet $g8_fast_detect] 1]] > 0 &&
    [llength [lsearch -all -inline [list $g9_wait_remote_detect $g10_cfg_complete $g11_rx_parser $g12_ordered_set] 1]] > 0} {
  error "G7/G8不能与G9/G10/G11诊断组合"
}
set ila_resume  [expr {$ila_debug && [info exists ::env(K11B2_ILA_RESUME)] &&
                       $::env(K11B2_ILA_RESUME) eq "1"}]
set phy_module  pcie_phy_x1_gen3
set phy_ip_root [file join $script_dir \
                  [expr {$g2_gen1_only ? "ip_g2_gen1" : "ip"}]]
set build_variant "build_k11b2"
if {$ila_debug} { set build_variant "build_k11b2_ila" }
if {$g9_wait_remote_detect} {
  set build_variant [expr {$ila_debug ?
                          "build_g9_wait_remote_detect_ila" :
                          "build_g9_wait_remote_detect_release"}]
}
if {$g10_cfg_complete} { set build_variant "build_g10_cfg_complete_ila" }
if {$g11_rx_parser} { set build_variant "build_g11_rx_parser_ila" }
if {$g12_ordered_set} {
  set build_variant [expr {$ila_debug ?
                          "build_g12_ordered_set_ila" :
                          "build_g12_ordered_set_release"}]
}
if {$g8_fast_detect} { set build_variant "build_g8_fast_detect_ila" }
if {$g7_rx_p0_quiet} { set build_variant "build_g7_rxp0_ila" }
if {$g2_gen1_only} { set build_variant "build_g2_gen1" }
if {$k13_enable} {
  set build_variant [expr {$ila_debug ? "build_k13_gen3_ila" : "build_k13_gen3"}]
  if {!$k13_rxeq_bootstrap} { set build_variant "${build_variant}_rxeq_off" }
  if {$k13_gt_rate_done_tie_high} { set build_variant "${build_variant}_gt_rate_done1" }
  if {$k13_gt_rate_done_start_pulse} { set build_variant "${build_variant}_gt_rate_done_start" }
  if {$k13_gt_rate_done_reset_release_pulse} { set build_variant "${build_variant}_gt_rate_done_reset_release" }
  if {$k13_cdr_hold_recovery} { set build_variant "${build_variant}_cdr_hold" }
  if {$k13_cdr_hold_force_low} { set build_variant "${build_variant}_cdr_hold_low" }
  if {$k13_gt_rate_qpll_reset_forward} { set build_variant "${build_variant}_gt_qpllreset" }
  if {$k13_gt_primitive_debug} { set build_variant "${build_variant}_gt_primitive" }
  if {$k13_gt_qpll_prereq_debug} { set build_variant "${build_variant}_qpll_prereq" }
  if {!$k13_pre_rate_txeq_enable} { set build_variant "${build_variant}_pre_rate_txeq_off" }
  if {$k13_golden_rate_replay} { set build_variant "${build_variant}_golden_replay" }
  if {$k13_minimal_diag} { set build_variant "${build_variant}_minimal_diag" }
}
set build_dir   [file join $script_dir $build_variant impl]
set xci_path    [file join $phy_ip_root $phy_module ${phy_module}.xci]
set afifo_path  /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
set part_name   xcku040-ffva1156-2-e
set top_name    kcu105_pcie_ep_gen1_board_top
file mkdir $build_dir

if {$ila_resume} {
  set resume_dcp [file join $build_dir k11b3_pre_ila_synth.dcp]
  if {![file exists $resume_dcp]} { error "K11-B3续跑DCP不存在：$resume_dcp" }
  open_checkpoint $resume_dcp
  puts "K11B3_ILA_RESUME_FROM_DCP=$resume_dcp"
} else {
if {![file exists $xci_path]} { error "K11-B2 XCI不存在，请先执行make k02-ip：$xci_path" }
if {![file exists $afifo_path]} { error "缺少冻结afifo依赖：$afifo_path" }

set_part $part_name
read_ip $xci_path
generate_target all [get_ips $phy_module]

# Diagnostic-only A/B variant. With TX/RX both using QPLL1, the generated
# GT Wizard normally lets its reset controller own the active QPLL1 reset.
# Forward the PCIe rate-change QPLL reset request into that active reset path
# for one controlled hardware experiment; never enable this in production.
if {$k13_gt_rate_qpll_reset_forward} {
  if {!$k13_enable} {
    error "K13_GT_RATE_QPLL_RESET_FORWARD requires K13_ENABLE=1"
  }
  if {$k13_gt_rate_done_tie_high} {
    error "Do not combine K13_GT_RATE_QPLL_RESET_FORWARD with K13_GT_RATE_DONE_TIE_HIGH"
  }
  set qpll_reset_src [file join $phy_ip_root $phy_module ip_0 synth \
                      pcie_phy_x1_gen3_gt_gtwizard_gthe3.v]
  if {![file exists $qpll_reset_src]} {
    error "GT Wizard generated source not found: $qpll_reset_src"
  }
  set qpll_reset_f [open $qpll_reset_src r]
  set qpll_reset_text [read $qpll_reset_f]
  close $qpll_reset_f
  # The active shared-common implementation is the QPLL1/QPLL1 vector case
  # below the channel-bonding loop.  The scalar assignments above it belong to
  # inactive generated branches and are not sufficient for this experiment.
  set qpll_reset_vec_old {assign qpll1reset_int[gi_hb_rst_cm] =
                     (|gtwiz_reset_pllreset_tx_int[f_idx_ch_ub(gi_hb_rst_cm):f_idx_ch_lb(gi_hb_rst_cm)]) ||
                     (|gtwiz_reset_pllreset_rx_int[f_idx_ch_ub(gi_hb_rst_cm):f_idx_ch_lb(gi_hb_rst_cm)]);}
  set qpll_reset_vec_new {assign qpll1reset_int[gi_hb_rst_cm] =
                     (|gtwiz_reset_pllreset_tx_int[f_idx_ch_ub(gi_hb_rst_cm):f_idx_ch_lb(gi_hb_rst_cm)]) ||
                     (|gtwiz_reset_pllreset_rx_int[f_idx_ch_ub(gi_hb_rst_cm):f_idx_ch_lb(gi_hb_rst_cm)]) ||
                     qpll1reset_in[gi_hb_rst_cm];}
  set qpll_reset_vec_count 0
  set qpll_reset_vec_offset 0
  while {[set qpll_reset_vec_hit [string first $qpll_reset_vec_old $qpll_reset_text $qpll_reset_vec_offset]] >= 0} {
    incr qpll_reset_vec_count
    set qpll_reset_vec_offset [expr {$qpll_reset_vec_hit + [string length $qpll_reset_vec_old]}]
  }
  if {$qpll_reset_vec_count != 1} {
    error "GT QPLL reset diagnostic expects one active QPLL1/QPLL1 assignment, found $qpll_reset_vec_count"
  }
  set qpll_reset_text [string map [list $qpll_reset_vec_old $qpll_reset_vec_new] $qpll_reset_text]
  set qpll_reset_old {assign qpll1reset_int = {`pcie_phy_x1_gen3_gt_gtwizard_gthe3_SF_CM{gtwiz_reset_pllreset_tx_int || gtwiz_reset_pllreset_rx_int}};}
  set qpll_reset_new {assign qpll1reset_int = {`pcie_phy_x1_gen3_gt_gtwizard_gthe3_SF_CM{gtwiz_reset_pllreset_tx_int || gtwiz_reset_pllreset_rx_int}} || qpll1reset_in;}
  set qpll_reset_count 0
  set qpll_reset_offset 0
  while {[set qpll_reset_hit [string first $qpll_reset_old $qpll_reset_text $qpll_reset_offset]] >= 0} {
    incr qpll_reset_count
    set qpll_reset_offset [expr {$qpll_reset_hit + [string length $qpll_reset_old]}]
  }
  if {$qpll_reset_count != 2} {
    error "GT QPLL reset diagnostic expects two generated assignments, found $qpll_reset_count"
  }
  set qpll_reset_text [string map [list $qpll_reset_old $qpll_reset_new] $qpll_reset_text]
  set qpll_reset_f [open $qpll_reset_src w]
  puts -nonewline $qpll_reset_f $qpll_reset_text
  close $qpll_reset_f
  puts "K13_GT_RATE_QPLL_RESET_FORWARD_PATCH=$qpll_reset_src"
}
set k13_gt_rate_direct_source [expr {$k13_gt_rate_done_tie_high ||
                                      $k13_gt_rate_done_start_pulse ||
                                      $k13_gt_rate_done_reset_release_pulse ||
                                      $k13_gt_rate_qpll_reset_forward ||
                                      $k13_gt_primitive_debug ||
                                      $k13_gt_qpll_prereq_debug}]

# Diagnostic-only A variant. The generated PHY currently hardwires
# GT_PCIEUSERRATEDONE low; patch only this dedicated generated source so the
# default production build remains unchanged. This is not a production
# workaround until the full START/IDLE/DONE handshake is implemented.
if {$k13_gt_rate_direct_source} {
  if {$k13_gt_rate_done_tie_high} {
  set rate_done_src [file join $phy_ip_root $phy_module source pcie_phy_x1_gen3_core_top.v]
  if {![file exists $rate_done_src]} {
    error "GT rate-done diagnostic source not found: $rate_done_src"
  }
  set rate_done_f [open $rate_done_src r]
  set rate_done_text [read $rate_done_f]
  close $rate_done_f
  set rate_done_old {.GT_PCIEUSERRATEDONE    ( {PHY_LANE{1'b0}} ),}
  set rate_done_new {.GT_PCIEUSERRATEDONE    ( {PHY_LANE{1'b1}} ),}
  if {[string first $rate_done_old $rate_done_text] >= 0} {
    set rate_done_matches 0
    set rate_done_offset 0
    while {[set rate_done_hit [string first $rate_done_old $rate_done_text $rate_done_offset]] >= 0} {
      incr rate_done_matches
      set rate_done_offset [expr {$rate_done_hit + [string length $rate_done_old]}]
    }
    if {$rate_done_matches != 1} {
      error "GT rate-done diagnostic expects one hardwired-low connection, found $rate_done_matches"
    }
    set rate_done_text [string map [list $rate_done_old $rate_done_new] $rate_done_text]
  } elseif {[string first $rate_done_new $rate_done_text] < 0} {
    error "GT rate-done diagnostic source has neither low nor high tie"
  }
  set rate_done_f [open $rate_done_src w]
  puts -nonewline $rate_done_f $rate_done_text
  close $rate_done_f
  puts "K13_GT_RATE_DONE_TIE_HIGH_PATCH=$rate_done_src"
  }

  if {$k13_gt_rate_done_start_pulse} {
    set rate_done_src [file join $phy_ip_root $phy_module source pcie_phy_x1_gen3_core_top.v]
    if {![file exists $rate_done_src]} {
      error "GT START/DONE diagnostic source not found: $rate_done_src"
    }
    set rate_done_f [open $rate_done_src r]
    set rate_done_text [read $rate_done_f]
    close $rate_done_f

    # The generated wrapper exposes USERRATESTART from the GT wizard but
    # hardwires USERRATEDONE low.  Echo only the START rising edge one PCLK
    # later, preserving a bounded handshake pulse for this diagnostic build.
    set decl_old {   wire                          phy_pclk2;}
    set decl_new {   wire                          phy_pclk2;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] gt_pcieuserratestart_diag;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg  [PHY_LANE-1:0] gt_pcieuserratestart_diag_d;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg  [PHY_LANE-1:0] gt_pcieuserratedone_diag;
   always @(posedge phy_pclk2) begin
      if (phy_phystatus_rst_pclk2) begin
         gt_pcieuserratestart_diag_d <= {PHY_LANE{1'b0}};
         gt_pcieuserratedone_diag <= {PHY_LANE{1'b0}};
      end else begin
         gt_pcieuserratedone_diag <= gt_pcieuserratestart_diag &
                                     ~gt_pcieuserratestart_diag_d;
         gt_pcieuserratestart_diag_d <= gt_pcieuserratestart_diag;
      end
   end}
    if {[string first $decl_old $rate_done_text] < 0} {
      error "GT START/DONE diagnostic declaration anchor not found"
    }
    set rate_done_text [string map [list $decl_old $decl_new] $rate_done_text]

    set done_old {.GT_PCIEUSERRATEDONE    ( {PHY_LANE{1'b0}} ),}
    set done_new {.GT_PCIEUSERRATEDONE    ( gt_pcieuserratedone_diag ),}
    if {[string first $done_old $rate_done_text] < 0} {
      error "GT START/DONE diagnostic hardwired-low input not found"
    }
    set rate_done_text [string map [list $done_old $done_new] $rate_done_text]

    set start_old {.GT_PCIEUSERRATESTART   (  ),}
    set start_new {.GT_PCIEUSERRATESTART   ( gt_pcieuserratestart_diag ),}
    if {[string first $start_old $rate_done_text] < 0} {
      error "GT START/DONE diagnostic START output connection not found"
    }
    set rate_done_text [string map [list $start_old $start_new] $rate_done_text]

    set rate_done_f [open $rate_done_src w]
    puts -nonewline $rate_done_f $rate_done_text
    close $rate_done_f
    puts "K13_GT_RATE_DONE_START_PULSE_PATCH=$rate_done_src"
  }

  if {$k13_gt_rate_done_reset_release_pulse} {
    set rate_done_src [file join $phy_ip_root $phy_module source pcie_phy_x1_gen3_core_top.v]
    if {![file exists $rate_done_src]} {
      error "GT delayed DONE diagnostic source not found: $rate_done_src"
    }
    set rate_done_f [open $rate_done_src r]
    set rate_done_text [read $rate_done_f]
    close $rate_done_f

    # The GT primitive's USERRATESTART is an output status and was observed
    # low throughout the real rate-change window.  Generate one diagnostic
    # DONE pulse at the measured QPLL reset-release boundary instead of
    # fabricating START.  This tests DONE timing without changing production
    # rate or reset control.
    set decl_old {   wire                          phy_pclk2;}
    set decl_new {   wire                          phy_pclk2;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] gt_pcieuserratestart_diag;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg  [1:0]          phy_rate_diag_d;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg  [4:0]          gt_pcieuserrate_done_delay;
   (* MARK_DEBUG = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg  [PHY_LANE-1:0] gt_pcieuserratedone_diag;
   always @(posedge phy_pclk2) begin
      if (phy_phystatus_rst_pclk2) begin
         phy_rate_diag_d <= 2'b00;
         gt_pcieuserrate_done_delay <= 5'd0;
         gt_pcieuserratedone_diag <= {PHY_LANE{1'b0}};
      end else begin
         gt_pcieuserratedone_diag <= {PHY_LANE{1'b0}};
         if ((phy_rate_32b == 2'b10) && (phy_rate_diag_d != 2'b10)) begin
            gt_pcieuserrate_done_delay <= 5'd15;
         end else if (gt_pcieuserrate_done_delay != 5'd0) begin
            gt_pcieuserrate_done_delay <= gt_pcieuserrate_done_delay - 1'b1;
            if (gt_pcieuserrate_done_delay == 5'd1)
              gt_pcieuserratedone_diag <= {PHY_LANE{1'b1}};
         end
         phy_rate_diag_d <= phy_rate_32b;
      end
   end}
    if {[string first $decl_old $rate_done_text] < 0} {
      error "GT delayed DONE diagnostic declaration anchor not found"
    }
    set rate_done_text [string map [list $decl_old $decl_new] $rate_done_text]

    set done_old {.GT_PCIEUSERRATEDONE    ( {PHY_LANE{1'b0}} ),}
    set done_new {.GT_PCIEUSERRATEDONE    ( gt_pcieuserratedone_diag ),}
    if {[string first $done_old $rate_done_text] < 0} {
      error "GT delayed DONE diagnostic hardwired-low input not found"
    }
    set rate_done_text [string map [list $done_old $done_new] $rate_done_text]

    set start_old {.GT_PCIEUSERRATESTART   (  ),}
    set start_new {.GT_PCIEUSERRATESTART   ( gt_pcieuserratestart_diag ),}
    if {[string first $start_old $rate_done_text] < 0} {
      error "GT delayed DONE diagnostic START output connection not found"
    }
    set rate_done_text [string map [list $start_old $start_new] $rate_done_text]

    set rate_done_f [open $rate_done_src w]
    puts -nonewline $rate_done_f $rate_done_text
    close $rate_done_f
    puts "K13_GT_RATE_DONE_RESET_RELEASE_PULSE_PATCH=$rate_done_src delay=15"
  }

  # Direct-source synthesis otherwise removes the GT boundary nets before the
  # ILA insertion pass. Preserve the same read-only evidence used by the
  # normal IP-DCP build, without changing the default production path.
  set gt_debug_src [file join $phy_ip_root $phy_module source pcie_phy_x1_gen3_gtwizard_top.v]
  set gt_debug_f [open $gt_debug_src r]
  set gt_debug_text [read $gt_debug_f]
  close $gt_debug_f
  foreach {gt_decl gt_decl_keep} [list \
    {wire        [(PHY_LANE-1)>>2:0]     qpll1lock_out;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire        [(PHY_LANE-1)>>2:0]     qpll1lock_out;} \
    {wire [PHY_LANE-1:0]         gtpowergood_out         ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         gtpowergood_out         ;} \
    {wire [PHY_LANE-1:0]         pciesynctxsyncdone_out  ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         pciesynctxsyncdone_out  ;} \
    {wire [PHY_LANE-1:0]         txresetdone_out         ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         txresetdone_out         ;} \
    {wire [PHY_LANE-1:0] txelecidle_in          ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] txelecidle_in          ;} \
    {wire [PHY_LANE-1:0]         rxelecidle_out          ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         rxelecidle_out          ;} \
    {wire [PHY_LANE-1:0]         rxresetdone_out         ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         rxresetdone_out         ;} \
    {wire [(PHY_LANE* 3)-1:0]    rxstatus_out            ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [(PHY_LANE* 3)-1:0]    rxstatus_out            ;} \
    {wire [PHY_LANE-1:0]         rxvalid_out             ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         rxvalid_out             ;} \
    {wire [PHY_LANE-1:0] rxcdrhold_in           ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] rxcdrhold_in           ;} \
    {wire [(PHY_LANE* 3)-1:0]     rxrate_in;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [(PHY_LANE* 3)-1:0]     rxrate_in;} \
    {wire [(PHY_LANE* 2)-1:0]rxpd_in            ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [(PHY_LANE* 2)-1:0]rxpd_in            ;} \
    {wire [PHY_LANE-1:0] rxpolarity_in          ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] rxpolarity_in          ;} \
    {wire [PHY_LANE-1:0] rx8b10ben_in;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] rx8b10ben_in;} \
    {wire        [PHY_LANE-1:0]          pcierategen3_out;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire        [PHY_LANE-1:0]          pcierategen3_out;} \
    {wire        [(PHY_LANE*2)-1:0]      pcierateqpllpd_out;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire        [(PHY_LANE*2)-1:0]      pcierateqpllpd_out;} \
    {wire        [(PHY_LANE*2)-1:0]      pcierateqpllreset_out;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire        [(PHY_LANE*2)-1:0]      pcierateqpllreset_out;} \
    {wire [PHY_LANE-1:0]         pcierateidle_out        ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         pcierateidle_out        ;} \
    {wire [PHY_LANE-1:0]         pcieusergen3rdy_out     ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         pcieusergen3rdy_out     ;} \
    {wire [PHY_LANE-1:0]         pcieuserratestart_out   ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         pcieuserratestart_out   ;} \
    {wire [PHY_LANE-1:0]         pcieuserphystatusrst_out;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0]         pcieuserphystatusrst_out;} \
    {wire [PHY_LANE-1:0] pcieuserratedone_in    ;} \
    {(* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [PHY_LANE-1:0] pcieuserratedone_in    ;}] {
    if {[string first $gt_decl $gt_debug_text] < 0} {
      error "GT rate-done diagnostic declaration not found: $gt_decl"
    }
    set gt_debug_text [string map [list $gt_decl $gt_decl_keep] $gt_debug_text]
  }
  set gt_debug_f [open $gt_debug_src w]
  puts -nonewline $gt_debug_f $gt_debug_text
  close $gt_debug_f
}
set ip_dcp [file join $phy_ip_root $phy_module ${phy_module}.dcp]
if {$k13_gt_rate_direct_source} {
  # The generated PHY source is read directly below for this A build.  This
  # keeps the diagnostic patch in the top-level synthesis instead of relying
  # on an OOC checkpoint's IP metadata.
  puts "K13_GT_RATE_DONE_TIE_HIGH_READ_GENERATED_SOURCE=1"
} else {
  if {[file exists $ip_dcp]} { file delete -force $ip_dcp }
  synth_ip -force [get_ips $phy_module]
}

if {$k13_gt_rate_direct_source} {
  set generated_phy_sources [concat \
    [lsort [glob -nocomplain [file join $phy_ip_root $phy_module source *.v]]] \
    [list [file join $phy_ip_root $phy_module synth ${phy_module}.v]] \
    [lsort [glob -nocomplain [file join $phy_ip_root $phy_module ip_0 synth *.v]]]]
  if {[llength $generated_phy_sources] == 0} {
    error "GT rate-done diagnostic generated PHY source list为空"
  }
  foreach generated_phy_source $generated_phy_sources {
    read_verilog $generated_phy_source
  }
  puts "K13_GT_RATE_DONE_TIE_HIGH_SOURCE_COUNT=[llength $generated_phy_sources]"
}

read_verilog $afifo_path
set sv_files [list \
  rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
  rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
  rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
  rtl/common/pcie_cdc_pulse.sv \
  rtl/phy/kcu105_reset_ctrl.sv rtl/phy/kcu105_refclk_reset.sv \
  rtl/phy/kcu105_pcie_phy_wrapper.sv rtl/phy/pcie_gen12_scrambler.sv \
  rtl/phy/pcie_gen1_rx_symbol_aligner.sv rtl/phy/pcie_gen1_os_rx.sv \
  rtl/phy/pcie_gen1_os_tx.sv rtl/phy/pcie_gen3_scrambler32.sv rtl/phy/pcie_gen3_os_rx.sv \
  rtl/phy/pcie_gen3_os_tx.sv rtl/phy/pcie_gen1_framer.sv \
  rtl/common/pcie_link_loss_trigger.sv \
  rtl/phy/pcie_ltssm_mac_gen1.sv \
  rtl/common/pcie_retrain_cdc_mailbox.sv rtl/phy/pcie_phy_rate_contract.sv \
  rtl/phy/k13_qpll_event_recorder.sv \
  rtl/phy/k13_golden_rate_replay.sv \
  rtl/phy/pcie_recovery_speed_ctrl.sv \
  rtl/phy/pcie_equalization_ctrl.sv rtl/phy/pcie_recovery_ts_guard.sv \
  rtl/phy/pcie_k13_production_ctrl.sv \
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

if {$ila_debug} {
  if {$g7_rx_p0_quiet} {
    synth_design -top $top_name -part $part_name \
      -generic K11B2_ILA_DEBUG=1 -generic G7_RX_P0_QUIET=1
  } elseif {$g8_fast_detect} {
    # 250 MHz PIPE时钟下25,000周期约100 us，只验证首次Detect启动竞态。
    synth_design -top $top_name -part $part_name \
      -generic K11B2_ILA_DEBUG=1 -generic DETECT_QUIET_CYCLES=25000
  } elseif {$g9_wait_remote_detect} {
    synth_design -top $top_name -part $part_name \
      -generic K11B2_ILA_DEBUG=1 \
      -generic G9_WAIT_REMOTE_DETECT=1 \
      -generic G9_WAIT_REMOTE_DETECT_CYCLES=$g9_wait_remote_detect_cycles \
      -generic K13_ENABLE=$k13_enable \
      -generic K13_RXEQ_BOOTSTRAP=$k13_rxeq_bootstrap \
      -generic K13_RXEQ_TWO_PASS=$k13_rxeq_two_pass \
      -generic K13_PRE_RATE_TXEQ_ENABLE=$k13_pre_rate_txeq_enable \
      -generic K13_GOLDEN_RATE_REPLAY=$k13_golden_rate_replay \
      -generic K13_CDR_HOLD_FORCE_LOW=$k13_cdr_hold_force_low
  } else {
    synth_design -top $top_name -part $part_name \
      -generic K11B2_ILA_DEBUG=1 -generic K13_ENABLE=$k13_enable \
      -generic K13_RXEQ_BOOTSTRAP=$k13_rxeq_bootstrap \
      -generic K13_RXEQ_TWO_PASS=$k13_rxeq_two_pass \
      -generic K13_PRE_RATE_TXEQ_ENABLE=$k13_pre_rate_txeq_enable \
      -generic K13_GOLDEN_RATE_REPLAY=$k13_golden_rate_replay \
      -generic K13_CDR_HOLD_FORCE_LOW=$k13_cdr_hold_force_low
  }
  write_checkpoint -force [file join $build_dir k11b3_pre_ila_synth.dcp]
} else {
  if {$g9_wait_remote_detect} {
    # Release版保留已经过硬件验证的G9启动等待，只移除ILA/mark_debug。
    synth_design -top $top_name -part $part_name \
      -generic G9_WAIT_REMOTE_DETECT=1 \
      -generic G9_WAIT_REMOTE_DETECT_CYCLES=$g9_wait_remote_detect_cycles \
      -generic K13_ENABLE=$k13_enable \
      -generic K13_RXEQ_BOOTSTRAP=$k13_rxeq_bootstrap \
      -generic K13_RXEQ_TWO_PASS=$k13_rxeq_two_pass \
      -generic K13_PRE_RATE_TXEQ_ENABLE=$k13_pre_rate_txeq_enable \
      -generic K13_GOLDEN_RATE_REPLAY=$k13_golden_rate_replay \
      -generic K13_CDR_HOLD_FORCE_LOW=$k13_cdr_hold_force_low
  } else {
    synth_design -top $top_name -part $part_name \
      -generic K13_ENABLE=$k13_enable \
      -generic K13_RXEQ_BOOTSTRAP=$k13_rxeq_bootstrap \
      -generic K13_RXEQ_TWO_PASS=$k13_rxeq_two_pass \
      -generic K13_PRE_RATE_TXEQ_ENABLE=$k13_pre_rate_txeq_enable \
      -generic K13_GOLDEN_RATE_REPLAY=$k13_golden_rate_replay \
      -generic K13_CDR_HOLD_FORCE_LOW=$k13_cdr_hold_force_low
  }
}
}

if {$ila_debug} {
  proc debug_bus_nets {regexp_pattern expected_width} {
    set result [lsort -dictionary [get_nets -hierarchical -quiet -regexp \
                                   $regexp_pattern -filter {MARK_DEBUG == 1}]]
    if {[llength $result] != $expected_width} {
      error "K11-B3调试总线宽度错误：$regexp_pattern，实际[llength $result]，期望$expected_width"
    }
    return $result
  }
  proc debug_scalar_net {net_name} {
    set result [get_nets -hierarchical -quiet $net_name -filter {MARK_DEBUG == 1}]
    if {[llength $result] == 0} {
      set leaf_name [file tail $net_name]
      set result [get_nets -hierarchical -quiet -regexp ".*${leaf_name}.*" \
                  -filter {MARK_DEBUG == 1}]
    }
    if {[llength $result] != 1} {
      error "K11-B3调试标量不存在或不唯一：$net_name，实际[llength $result]"
    }
    return $result
  }
  # K11-B4：直接从生成的 standalone PHY/GTHE3 层级引出只读诊断网。
  # 这些网不进入正式协议逻辑，只用于确认 TX 复位、PLL/GT 状态和
  # PHY 到 GT 的 Electrical Idle 控制是否一致。层级路径来自 K02 XCI
  # 生成的固定网表；若 XCI 重新生成导致路径变化，应让构建明确失败。
  proc phy_boundary_net {regexp_pattern} {
    set result [get_nets -hierarchical -quiet -regexp $regexp_pattern]
    if {[llength $result] != 1} {
      error "K11-B4 PHY诊断网不存在或不唯一：$regexp_pattern，实际[llength $result]"
    }
    set_property MARK_DEBUG TRUE $result
    return $result
  }
  proc phy_boundary_net_first {regexp_patterns} {
    foreach regexp_pattern $regexp_patterns {
      set result [get_nets -hierarchical -quiet -regexp $regexp_pattern]
      if {[llength $result] == 1} {
        set_property MARK_DEBUG TRUE $result
        return $result
      }
    }
    error "K11-B4 PHY诊断网候选均不存在或不唯一：$regexp_patterns"
  }
  proc phy_boundary_bus {regexp_pattern expected_width} {
    set result [lsort -dictionary [get_nets -hierarchical -quiet -regexp $regexp_pattern]]
    if {[llength $result] != $expected_width} {
      error "K11-G3 PHY诊断总线不存在或宽度错误：$regexp_pattern，实际[llength $result]，期望$expected_width"
    }
    set_property MARK_DEBUG TRUE $result
    return $result
  }
  proc phy_primitive_pin_nets {cell_ref pin_pattern expected_width} {
    set cells [get_cells -hierarchical -quiet -filter "REF_NAME =~ ${cell_ref}*"]
    if {[llength $cells] != 1} {
      error "K13 primitive cell不存在或不唯一：$cell_ref，实际[llength $cells]"
    }
    set pin_pairs {}
    foreach pin [get_pins -quiet -of_objects [lindex $cells 0]] {
      set ref_pin [get_property REF_PIN_NAME $pin]
      if {$expected_width == 1} {
        if {$ref_pin eq $pin_pattern} {
          set pin_nets [get_nets -quiet -of_objects $pin]
          if {[llength $pin_nets] != 1} {
            error "K13 primitive端口无唯一网络：$cell_ref/$ref_pin"
          }
          lappend pin_pairs [list $ref_pin [lindex $pin_nets 0]]
        }
      } elseif {[regexp "^${pin_pattern}\\\[[0-9]+\\\]$" $ref_pin]} {
        set pin_nets [get_nets -quiet -of_objects $pin]
        if {[llength $pin_nets] != 1} {
          error "K13 primitive端口无唯一网络：$cell_ref/$ref_pin"
        }
        # Preserve one entry per primitive pin.  Synthesis can legally merge
        # multiple vector bits onto the same constant net (for example
        # QPLL1REFCLKSEL[2:0]); an ILA bus still needs those repeated bits.
        lappend pin_pairs [list $ref_pin [lindex $pin_nets 0]]
      }
    }
    set pin_pairs [lsort -dictionary -index 0 $pin_pairs]
    set nets {}
    foreach pin_pair $pin_pairs {
      lappend nets [lindex $pin_pair 1]
    }
    if {[llength $nets] != $expected_width} {
      error "K13 primitive端口宽度错误：$cell_ref/$pin_pattern，实际[llength $nets]，期望$expected_width"
    }
    set_property MARK_DEBUG TRUE $nets
    return $nets
  }
  proc add_ila_probe {core_name probe_index nets} {
    if {$probe_index != 0} { create_debug_port $core_name probe }
    set port [get_debug_ports ${core_name}/probe${probe_index}]
    set_property port_width [llength $nets] $port
    connect_debug_port $port $nets
  }

  proc k13_connect_recorder_input {pin_pattern source_net} {
    set pins [get_pins -hierarchical -quiet -regexp $pin_pattern]
    if {[llength $pins] != 1} {
      error "K13事件记录器输入不存在或不唯一：$pin_pattern，实际[llength $pins]"
    }
    set pin [lindex $pins 0]
    set old_nets [get_nets -quiet -of_objects $pin]
    set_property DONT_TOUCH FALSE [get_nets -quiet -of_objects $pin]
    # The GT diagnostic source nets are deliberately marked DONT_TOUCH by the
    # generated-source patch.  Fan out from them without trying to clear that
    # property; Vivado rejects clearing it even though the source is read-only.
    if {[llength $old_nets] == 1} {
      disconnect_net -net [lindex $old_nets 0] -pinlist [list $pin]
    }
    connect_net -hier -net $source_net -objects [list $pin]
  }

  if {$k13_enable && $k13_gt_primitive_debug} {
    # Replace the recorder's synthesizable zero taps with the real primitive
    # outputs. This is diagnostic-only and does not change PHY control logic.
     k13_connect_recorder_input {.*k13_qpll_event_recorder/qpll1lock$} \
       [phy_primitive_pin_nets GTHE3_COMMON QPLL1LOCK 1]
     k13_connect_recorder_input {.*k13_qpll_event_recorder/qpll1reset$} \
       [phy_primitive_pin_nets GTHE3_COMMON QPLL1RESET 1]
    puts "K13_QPLL_EVENT_RECORDER_CONNECT_PASS"
  }

  create_debug_core u_ila_pipe ila
  # 1024 TS1 = 8192个125 MHz PIPE周期；这里保留更长的GT RX复位/CDR
  # 取证窗口，确认RXRESETDONE不是仅仅晚于上一版131 us采集窗口。
  # K13 的 478-bit PIPE ILA 在 KU040 上不能使用 32768 深度，否则调试
  # 核自身会耗尽 BRAM。允许构建调用方显式覆盖，默认给 K13 采用 4096。
  set ila_pipe_depth [expr {$k13_minimal_diag ? 1024 : ($g11_rx_parser || $g12_ordered_set ? 4096 : ($g10_cfg_complete ? 8192 : ($k13_enable ? 4096 : 32768)))}]
  if {[info exists ::env(K11B2_ILA_PIPE_DEPTH)]} {
    set ila_pipe_depth $::env(K11B2_ILA_PIPE_DEPTH)
  }
  if {![string is integer -strict $ila_pipe_depth] ||
      $ila_pipe_depth < 1024 ||
      ($ila_pipe_depth & ($ila_pipe_depth - 1)) != 0} {
    error "K11B2_ILA_PIPE_DEPTH必须是不小于1024的2次幂"
  }
  set_property C_DATA_DEPTH $ila_pipe_depth [get_debug_cores u_ila_pipe]
  set_property C_TRIGIN_EN false [get_debug_cores u_ila_pipe]
  set_property C_TRIGOUT_EN false [get_debug_cores u_ila_pipe]
  set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_pipe]
  connect_debug_port u_ila_pipe/clk \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_pipe_clk]
  add_ila_probe u_ila_pipe 0 \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_pipe_tlp_trigger]
  if {$k13_minimal_diag} {
    # Keep the historical probe indices stable while replacing the wide
    # packet/TS payload with only the command bundle and sticky recorder.
    add_ila_probe u_ila_pipe 1 \
      [debug_bus_nets {.*dbg_k13_command_bundle.*\[[0-9]+\]$} 64]
    add_ila_probe u_ila_pipe 2 \
      [debug_bus_nets {.*dbg_k13_qpll_event_record.*\[[0-9]+\]$} 176]
    for {set minimal_pad_probe 3} {$minimal_pad_probe <= 18} {incr minimal_pad_probe} {
      add_ila_probe u_ila_pipe $minimal_pad_probe \
        [debug_bus_nets {.*dbg_k13_command_bundle.*\[0\]$} 1]
    }
  } else {
  add_ila_probe u_ila_pipe 1 \
    [debug_bus_nets {.*dbg_pipe_top.*\[[0-9]+\]$} 64]
  add_ila_probe u_ila_pipe 2 \
    [debug_bus_nets {.*dbg_pipe_dll.*\[[0-9]+\]$} 128]
  add_ila_probe u_ila_pipe 3 \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_pipe_link_loss_trigger]
  add_ila_probe u_ila_pipe 4 \
    [debug_bus_nets {.*dbg_ltssm_detail.*\[[0-9]+\]$} 256]
  add_ila_probe u_ila_pipe 5 \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_phy_rxidle_conflict]
  # probe6 位序（由低到高对应列表顺序）：
  # 同步后的PERST#、PERST#上升沿脉冲、PIPE_RST_N、PHY_PHYSTATUS_RST、PHY TX_VALID、PHY TX_ELECIDLE、
  # GT TXRESETDONE、GT POWERGOOD、QPLL1LOCK、PCIe TX sync done、
  # GT 侧 TXELECIDLE 输入、PHY状态复位撤销事件，以及 GT Gen3 rate-change
  # 控制面的 RATEGEN3、QPLL reset/PD、RATEIDLE、USERGEN3RDY、
  # USERRATESTART 和 RXRATE。后几项用于区分“QPLL 被 rate-change
  # 逻辑主动复位但未恢复”与“仅仅是 RX CDR 未锁定”，并还原完整
  # PCIEUSERRATE handshake。
  # Vivado 2021.2 may prune PCIEUSERRATE outputs that are not exported by
  # this generated PHY wrapper. Keep the probe width stable with the compact
  # K13 contract bus; a future wrapper exposing raw pins takes precedence.
  set phy_probe_nets [list \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_perst_n_pipe] \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_perst_rise_pipe] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/pipe_rst_n$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/phy_phystatus_rst$}] \
    [phy_boundary_net_first [list \
      {^u_endpoint/phy_txdata_valid$} \
      {^u_endpoint/u_phy_wrapper/phy_txdata_valid$}]] \
    [phy_boundary_net_first [list \
      {^u_endpoint/phy_txelecidle$} \
      {^u_endpoint/u_phy_wrapper/phy_txelecidle$}]] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/txresetdone_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/gtpowergood_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/qpll1lock_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pciesynctxsyncdone_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/txelecidle_in\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcierategen3_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcierateqpllreset_out\[0\]$}] \
    [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcierateqpllpd_out\[0\]$}] \
    [phy_boundary_net_first [list \
      {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcierateidle_out\[0\]$} \
      {^u_endpoint/g_ila_debug\.dbg_k13_top\[0\]$}]] \
    [phy_boundary_net_first [list \
      {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcieusergen3rdy_out\[0\]$} \
      {^u_endpoint/g_ila_debug\.dbg_k13_top\[1\]$}]] \
    [phy_boundary_net_first [list \
      {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcieuserratestart_out\[0\]$} \
      {^u_endpoint/g_ila_debug\.dbg_k13_top\[2\]$}]] \
    [debug_scalar_net u_endpoint/g_ila_debug/dbg_phystatus_rst_fall_pipe]]
  add_ila_probe u_ila_pipe 6 $phy_probe_nets

  # G3：直接观察GTHE3解码输出，区分“GT本身仍判定Electrical Idle”与
  # “standalone PHY在GT之后屏蔽了有效数据”。probe7从低到高依次为：
  # RXRESETDONE、原始RXELECIDLE、原始RXVALID、原始RXSTATUS[2:0]。
  # 上一轮已确认原始RXDATA/RXCTRL0全程为0，本轮移除这34位，
  # 为接收控制探针释放布线余量。
  set g3_gt_prefix {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/}
  set g3_rx_probe_nets [list \
    [phy_boundary_net [format {%srxresetdone_out\[0\]$} $g3_gt_prefix]] \
    [phy_boundary_net [format {%srxelecidle_out\[0\]$} $g3_gt_prefix]] \
    [phy_boundary_net [format {%srxvalid_out\[0\]$} $g3_gt_prefix]]]
  set g3_rx_probe_nets [concat $g3_rx_probe_nets \
    [phy_boundary_bus [format {%srxstatus_out\[[0-2]\]$} $g3_gt_prefix] 3]]
  add_ila_probe u_ila_pipe 7 $g3_rx_probe_nets

  # G4：采集送入GTHE3的动态RX控制。probe8从低到高依次为：
  # RXCDRHOLD、RXRATE[1:0]、RXPD[1:0]、RXPOLARITY、RX8B10BEN。
  # GTRXRESET/RXUSERRDY来自100 MHz复位域，直接接入250 MHz ILA会形成CDC-1；
  # RXRESETDONE已足够确认其最终复位/ready结果，因此不跨域采集这两位。
  # 这些信号用于验证静态GT属性相同后，接收电源/CDR控制时序是否仍有差异。
  if {$k13_gt_rate_direct_source} {
    # Direct-source A synthesis does not retain these internal control nets;
    # keep probe width/index stable with a diagnostic slice of dbg_k13_top.
    set g4_rx_control_nets [lrange \
      [debug_bus_nets {.*dbg_k13_top.*\[[0-9]+\]$} 64] 0 7]
  } else {
    set g4_rx_control_nets [list \
      [phy_boundary_net [format {%srxcdrhold_in\[0\]$} $g3_gt_prefix]]]
    set g4_rx_control_nets [concat $g4_rx_control_nets \
      [phy_boundary_bus [format {%srxrate_in\[[0-1]\]$} $g3_gt_prefix] 2] \
      [phy_boundary_bus [format {%srxpd_in\[[0-1]\]$} $g3_gt_prefix] 2] \
      [list \
        [phy_boundary_net [format {%srxpolarity_in\[0\]$} $g3_gt_prefix]] \
        [phy_boundary_net [format {%srx8b10ben_in\[0\]$} $g3_gt_prefix]]]]
  }
  add_ila_probe u_ila_pipe 8 $g4_rx_control_nets
  # probe9：Polling.Active中已经完成发送的TS1数量（每个TS1=8个125 MHz pclk）。
  add_ila_probe u_ila_pipe 9 \
    [debug_bus_nets {.*dbg_polling_tx_ts1_count.*\[[0-9]+\]$} 11]
  # G9：低到高依次为RXELECIDLE、RXVALID、TXELECIDLE、TXDETECTRX、
  # AS_MAC_IN_DETECT、PHY_POWERDOWN[1:0]、保留位。
  add_ila_probe u_ila_pipe 10 \
    [debug_bus_nets {.*dbg_g9_control.*\[[0-9]+\]$} 8]
  add_ila_probe u_ila_pipe 11 \
    [debug_scalar_net u_endpoint/u_ltssm_mac/g_ila_debug_ltssm/dbg_g9_active]
  add_ila_probe u_ila_pipe 12 \
    [debug_scalar_net u_endpoint/u_ltssm_mac/g_ila_debug_ltssm/dbg_g9_rxelecidle_low_seen]
  add_ila_probe u_ila_pipe 13 \
    [debug_scalar_net u_endpoint/u_ltssm_mac/g_ila_debug_ltssm/dbg_g9_timeout_seen]
  # G10：CFG_COMPLETE中的TS2计数器和字段快照。
  add_ila_probe u_ila_pipe 14 \
    [debug_bus_nets {.*dbg_g10_counts.*\[[0-9]+\]$} 128]
  add_ila_probe u_ila_pipe 15 \
    [debug_bus_nets {.*dbg_g10_fields.*\[[0-9]+\]$} 64]
  add_ila_probe u_ila_pipe 16 \
    [debug_bus_nets {.*dbg_g10_state.*\[[0-9]+\]$} 32]
  add_ila_probe u_ila_pipe 17 \
    [debug_bus_nets {.*dbg_g11_rx.*\[[0-9]+\]$} 128]
  add_ila_probe u_ila_pipe 18 \
    [debug_bus_nets {.*dbg_g12_tx.*\[[0-9]+\]$} 32]
  }
  if {$k13_minimal_diag} {
    # Keep probe20/21 hardware names stable without retaining the historical
    # 64-bit K13 status payload in the timing-clean artifact.
    add_ila_probe u_ila_pipe 19 \
      [debug_bus_nets {.*dbg_k13_command_bundle.*\[0\]$} 1]
  } else {
    # K13 probe19: Recovery.Speed, RXEQ done/adapt_done, TXELECIDLE and
    # TX/RX first-block boundary evidence. The packed field order is in RTL.
    # The timing-clean minimal artifact carries the required command and
    # completion evidence in probes 1/2/20/21 and does not retain this
    # historical 64-bit packet of redundant status signals.
    add_ila_probe u_ila_pipe 19 \
      [debug_bus_nets {.*dbg_k13_top.*\[[0-9]+\]$} 64]
  }
  if {$k13_gt_primitive_debug} {
    # K13 probe20：直接从实际 GTHE3_COMMON/GTHE3_CHANNEL primitive 取样。
    # 低到高依次为 QPLL1PD、QPLL1RESET、QPLL1LOCKEN、
    # TX/RX PLLCLKSEL、TX/RX RATE、QPLL1参考/反馈时钟丢失、
    # GT PCIEUSERRATEDONE 输入和 PHY reset completion。
    set gt_primitive_probe_nets [list \
      [phy_primitive_pin_nets GTHE3_COMMON QPLL1PD 1] \
      [phy_primitive_pin_nets GTHE3_COMMON QPLL1RESET 1] \
      [phy_primitive_pin_nets GTHE3_COMMON QPLL1LOCKEN 1] \
      [phy_primitive_pin_nets GTHE3_CHANNEL TXPLLCLKSEL 2] \
      [phy_primitive_pin_nets GTHE3_CHANNEL RXPLLCLKSEL 2] \
      [phy_primitive_pin_nets GTHE3_CHANNEL TXRATE 3] \
      [phy_primitive_pin_nets GTHE3_CHANNEL RXRATE 3] \
      [phy_primitive_pin_nets GTHE3_CHANNEL PCIERATEIDLE 1] \
      [phy_primitive_pin_nets GTHE3_CHANNEL PCIERATEQPLLRESET 2] \
      [phy_primitive_pin_nets GTHE3_CHANNEL PCIERATEGEN3 1] \
      [phy_primitive_pin_nets GTHE3_CHANNEL PCIEUSERGEN3RDY 1] \
      [phy_primitive_pin_nets GTHE3_CHANNEL PCIEUSERRATESTART 1] \
      [phy_primitive_pin_nets GTHE3_COMMON QPLL1REFCLKLOST 1] \
      [phy_primitive_pin_nets GTHE3_COMMON QPLL1FBCLKLOST 1] \
      [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcieuserratedone_in\[0\]$}] \
      [phy_boundary_net {^u_endpoint/u_phy_wrapper/u_pcie_phy/inst/Uscale_gt\.us_gt_phy_wrapper/gt_wizard\.gtwizard_top_i/pcie_phy_x1_gen3_gt_i/pcieuserphystatusrst_out\[0\]$}]]
    if {$k13_gt_qpll_prereq_debug} {
      # Optional QPLL1 reference selection for interpreting the loss bits.
      set gt_primitive_probe_nets [concat $gt_primitive_probe_nets \
        [phy_primitive_pin_nets GTHE3_COMMON QPLL1REFCLKSEL 3]]
    }
    if {$k13_gt_rate_done_start_pulse || $k13_gt_rate_done_reset_release_pulse} {
      set gt_primitive_probe_nets [concat $gt_primitive_probe_nets \
        [debug_bus_nets {.*gt_pcieuserratedone_diag.*} 1]]
    }
    set gt_primitive_probe_nets [concat {*}$gt_primitive_probe_nets]
    add_ila_probe u_ila_pipe 20 $gt_primitive_probe_nets
  }
  if {$k13_enable} {
    add_ila_probe u_ila_pipe 21 \
      [debug_bus_nets {.*dbg_k13_qpll_event_record.*\[[0-9]+\]$} 176]
  }
  if {!$ila_pipe_only} {
    create_debug_core u_ila_core ila
    set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_core]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_core]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_core]
    set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_core]
    connect_debug_port u_ila_core/clk \
      [debug_scalar_net u_endpoint/u_protocol_core/g_ila_debug_core/dbg_core_clk]
    add_ila_probe u_ila_core 0 \
      [debug_scalar_net u_endpoint/u_protocol_core/g_ila_debug_core/dbg_core_tlp_trigger]
    add_ila_probe u_ila_core 1 \
      [debug_bus_nets {.*dbg_core_stream.*\[[0-9]+\]$} 128]
    add_ila_probe u_ila_core 2 \
      [debug_bus_nets {.*dbg_core_detail.*\[[0-9]+\]$} 320]
    add_ila_probe u_ila_core 3 \
      [debug_scalar_net u_endpoint/u_protocol_core/g_ila_debug_core/dbg_core_link_loss_trigger]
  }

  puts "K11G4_ILA_INSERT_PASS pipe_width=[expr {$k13_minimal_diag ? 459 : ($k13_enable ? 614 : 478)}] core_width=[expr {$ila_pipe_only ? 0 : 450}] depth=$ila_pipe_depth"
}
set afifo_gray_sync_cells [get_cells -hier -quiet -regexp \
  {.*u_.*afifo/(rgray_cross_reg|wgray_cross_reg|rd_wgray_reg|wr_rgray_reg).*}]
if {[llength $afifo_gray_sync_cells] == 0} { error "K11-B2未找到afifo Gray同步寄存器" }
set_property ASYNC_REG TRUE $afifo_gray_sync_cells
set_property SHREG_EXTRACT NO $afifo_gray_sync_cells
write_checkpoint -force [file join $build_dir k11b2_synth.dcp]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_cdc -details -file [file join $build_dir cdc_synth.rpt]

opt_design
place_design
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
# 路由后对正式与ILA构建统一执行进取物理优化。这不改变RTL，
# 主要收敛MAC TX到GTHE3 TXDATA的跨层长路由；正式构建仍由下方
# WNS/WHS>=0门禁决定是否生成bitstream。
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $build_dir k11b2_routed.dcp]
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
  if {[llength $port_object] != 1} { error "K11-B2顶层端口不存在：$port_name" }
  set actual_pin [get_property PACKAGE_PIN $port_object]
  if {![string equal -nocase $actual_pin $expected_pin]} {
    error "K11-B2管脚错误：$port_name=$actual_pin，期望$expected_pin"
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
set gth_commons  [get_cells -hierarchical -filter {REF_NAME == GTHE3_COMMON}]
if {[llength $gth_channels] != 1} { error "K11-B2 GTHE3_CHANNEL数量错误：[llength $gth_channels]" }
set channel_loc [get_property LOC $gth_channels]
if {![string equal -nocase $channel_loc GTHE3_CHANNEL_X0Y7]} { error "K11-B2 GT Channel LOC错误：$channel_loc" }
if {$g2_gen1_only} {
  if {[llength $gth_commons] > 1} {
    error "G2 Gen1/CPLL GTHE3_COMMON数量错误：[llength $gth_commons]"
  }
  set common_loc [expr {[llength $gth_commons] == 1 ?
                        [get_property LOC $gth_commons] : "NONE_CPLL"}]
} else {
  if {[llength $gth_commons] != 1} { error "K11-B2 GTHE3_COMMON数量错误：[llength $gth_commons]" }
  set common_loc [get_property LOC $gth_commons]
  if {![string equal -nocase $common_loc GTHE3_COMMON_X0Y1]} { error "K11-B2 GT Common LOC错误：$common_loc" }
}

set hard_pcie_count [llength [get_cells -quiet -hierarchical -filter {
  REF_NAME =~ PCIE* || PRIMITIVE_TYPE =~ ADVANCED.PCIE.*
}]]
if {$hard_pcie_count != 0} { error "K11-B2错误实例化PCIe Hard Block：$hard_pcie_count" }

proc require_hierarchy {module_name} {
  set cells [get_cells -quiet -hierarchical -filter "ORIG_REF_NAME == $module_name"]
  if {[llength $cells] == 0} { set cells [get_cells -quiet -hierarchical -filter "REF_NAME == $module_name"] }
  if {[llength $cells] == 0} { error "K11-B2找不到层次：$module_name" }
  return [llength $cells]
}
set mac_count  [require_hierarchy pcie_ltssm_mac_gen1]
set dll_count  [require_hierarchy pcie_dll]
set cfg_count  [require_hierarchy pcie_cfg_space]
set bar_count  [require_hierarchy pcie_bar_axil_master]
set demo_count [require_hierarchy demo_axil_slave]

set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {!$ila_debug && [llength $setup_paths] != 0} { error "K11-B2存在setup负时序" }
if {!$ila_debug && [llength $hold_paths] != 0} { error "K11-B2存在hold负时序" }
if {$k13_minimal_diag &&
    ([llength $setup_paths] != 0 || [llength $hold_paths] != 0)} {
  error "K13_MINIMAL_DIAG要求timing-clean：存在setup或hold负时序"
}
if {$ila_debug && ([llength $setup_paths] != 0 || [llength $hold_paths] != 0)} {
  puts "K11B3_ILA_DIAGNOSTIC_TIMING_ONLY setup_negative=[llength $setup_paths] hold_negative=[llength $hold_paths]"
}
set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] != 1} { error "K11-B2找不到可分析的最大延迟路径" }
set wns [get_property SLACK $worst_path]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set drc_critical [get_drc_violations -quiet -filter {SEVERITY == {Critical Warning}}]
if {[llength $drc_errors] != 0 || [llength $drc_critical] != 0} {
  error "K11-B2 DRC存在Error或Critical Warning"
}
set cdc_fp [open [file join $build_dir cdc_routed.rpt] r]
set cdc_text [read $cdc_fp]
close $cdc_fp
if {[regexp -line {^CDC-[0-9]+[ \t]+Critical[ \t]+[1-9][0-9]*} $cdc_text]} {
  error "K11-B2 CDC存在Critical路径"
}

set bit_name [expr {$g2_gen1_only ? "g2_gen1_cpll_endpoint.bit" :
                     ($k13_enable ?
                      ($ila_debug ? "k13_gen3_endpoint_ila.bit" :
                                    "k13_gen3_endpoint.bit") :
                      ($ila_debug ? "k11b2_gen1_endpoint_ila.bit" :
                                    "k11b2_gen1_endpoint.bit"))}]
write_bitstream -force [file join $build_dir $bit_name]
if {$ila_debug} {
  write_debug_probes -force [file join $build_dir k11b2_gen1_endpoint_ila.ltx]
}
set summary_file [open [file join $build_dir summary.txt] w]
set pass_marker [expr {$g2_gen1_only ? "G2_GEN1_CPLL_IMPL_PASS" :
                        ($k13_enable ?
                         ($ila_debug ? "K13_ILA_IMPL_PASS" : "K13_IMPL_PASS") :
                         ($ila_debug ? "K11B3_ILA_IMPL_PASS" :
                                       "K11B2_IMPL_PASS"))}]
puts $summary_file $pass_marker
puts $summary_file "part=$part_name"
puts $summary_file "top=$top_name"
puts $summary_file "GTHE3_CHANNEL_LOC=$channel_loc"
puts $summary_file "GTHE3_COMMON_LOC=$common_loc"
puts $summary_file "PCIE_HARD_BLOCK_COUNT=$hard_pcie_count"
puts $summary_file "MAC_HIERARCHY_COUNT=$mac_count"
puts $summary_file "DLL_HIERARCHY_COUNT=$dll_count"
puts $summary_file "CFG_HIERARCHY_COUNT=$cfg_count"
puts $summary_file "BAR_HIERARCHY_COUNT=$bar_count"
puts $summary_file "DEMO_HIERARCHY_COUNT=$demo_count"
puts $summary_file "WNS=$wns"
puts $summary_file "ILA_DEBUG=$ila_debug"
puts $summary_file "ILA_PIPE_ONLY=$ila_pipe_only"
puts $summary_file "G2_GEN1_ONLY=$g2_gen1_only"
puts $summary_file "K13_ENABLE=$k13_enable"
puts $summary_file "K13_RXEQ_BOOTSTRAP=$k13_rxeq_bootstrap"
puts $summary_file "K13_RXEQ_TWO_PASS=$k13_rxeq_two_pass"
puts $summary_file "K13_PRE_RATE_TXEQ_ENABLE=$k13_pre_rate_txeq_enable"
puts $summary_file "K13_GOLDEN_RATE_REPLAY=$k13_golden_rate_replay"
puts $summary_file "K13_MINIMAL_DIAG=$k13_minimal_diag"
puts $summary_file "K13_GT_RATE_DONE_TIE_HIGH=$k13_gt_rate_done_tie_high"
puts $summary_file "K13_GT_RATE_DONE_START_PULSE=$k13_gt_rate_done_start_pulse"
puts $summary_file "K13_GT_RATE_DONE_RESET_RELEASE_PULSE=$k13_gt_rate_done_reset_release_pulse"
puts $summary_file "K13_CDR_HOLD_RECOVERY=$k13_cdr_hold_recovery"
puts $summary_file "K13_CDR_HOLD_FORCE_LOW=$k13_cdr_hold_force_low"
puts $summary_file "K13_GT_QPLL_PREREQ_DEBUG=$k13_gt_qpll_prereq_debug"
puts $summary_file "K13_GT_RATE_QPLL_RESET_FORWARD=$k13_gt_rate_qpll_reset_forward"
puts $summary_file "G7_RX_P0_QUIET=$g7_rx_p0_quiet"
puts $summary_file "G8_FAST_DETECT=$g8_fast_detect"
puts $summary_file "PHY_MODULE=$phy_module"
puts $summary_file "TIMING_POLICY=[expr {$k13_minimal_diag ? "WNS_GE_0_REQUIRED_MINIMAL_DIAG" : ($ila_debug ? "DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED" : "WNS_GE_0_REQUIRED")}]"
puts $summary_file "bitstream=[file join $build_dir $bit_name]"
close $summary_file
puts "$pass_marker channel=$channel_loc common=$common_loc K13_ENABLE=$k13_enable WNS=$wns"
