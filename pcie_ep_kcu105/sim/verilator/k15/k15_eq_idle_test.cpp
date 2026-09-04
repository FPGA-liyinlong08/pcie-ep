#include "Vk15_eq_idle_test_top.h"
#include "verilated.h"
#include <cstdlib>
#include <iostream>

static void require(bool ok, const char *msg) {
    if (!ok) {
        std::cerr << "K15_DIRECTED_FAIL " << msg << '\n';
        std::exit(1);
    }
}

static void tick(Vk15_eq_idle_test_top &d) {
    d.clk = 0; d.eval();
    d.clk = 1; d.eval();
    d.clk = 0; d.eval();
}

static void pulse_ts(Vk15_eq_idle_test_top &d, bool ts2 = false) {
    d.ts1_valid = ts2 ? 0 : 1;
    d.ts2_valid = ts2 ? 1 : 0;
    tick(d);
    d.ts1_valid = 0; d.ts2_valid = 0;
    tick(d);
}

static unsigned eq_data(unsigned control, unsigned pre, unsigned main,
                        unsigned post, bool reject = false) {
    unsigned s7 = pre & 0x3f;
    unsigned s8 = main & 0x3f;
    unsigned s9 = ((reject ? 1u : 0u) << 6) | (post & 0x3f);
    unsigned bits = control ^ s7 ^ s8 ^ s9;
    bits ^= bits >> 4; bits ^= bits >> 2; bits ^= bits >> 1;
    s9 |= (bits & 1u) << 7;
    return (s9 << 16) | (s8 << 8) | s7;
}

static void set_tuple(Vk15_eq_idle_test_top &d, unsigned control,
                      unsigned pre, unsigned main, unsigned post,
                      bool reject = false) {
    d.ts_eq_control = control;
    d.ts_eq_data = eq_data(control, pre, main, post, reject);
}

static void enter_phase(Vk15_eq_idle_test_top &d, unsigned phase) {
    // The LTSSM holds eq_phase_valid high across phase changes
    // (0x28 -> 0x29 -> 0x2a -> 0x2b); only leaving Equalization drops it.
    d.phase = phase; d.phase_valid = 1; tick(d); tick(d);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vk15_eq_idle_test_top d;
    d.clk = 0; d.rst_n = 0; d.phase_valid = 0; d.phase = 0;
    d.ts1_valid = 0; d.ts2_valid = 0;
    set_tuple(d, 1, 40, 12, 0); d.tx_ts_complete = 0;
    d.eq_req_ready = 1; d.eq_busy = 0; d.eq_done = 0;
    d.eq_result = 0; d.eq_rsp_preset_sel = 0; d.eq_rsp_coeff = 0;
    d.initial_preset_valid = 1; d.initial_preset = 10;
    d.initial_coeff_valid = 0; d.initial_coeff = 0;
    d.idle_enable = 0; d.idle_l0_active = 0;
    d.training_enable = 0; d.training_mode = 1;
    tick(d); tick(d); d.rst_n = 1; tick(d);

    enter_phase(d, 0);
    require(d.tx_eq_control == 0x50, "phase0 sends EC00 with P10");
    require((d.tx_eq_data & 0x3f) == 0,
            "phase0 P10 fallback pre-cursor field");
    require(((d.tx_eq_data >> 8) & 0x3f) == 27,
            "phase0 P10 fallback main-cursor field");
    require(((d.tx_eq_data >> 16) & 0x3f) == 13,
            "phase0 P10 fallback post-cursor field");

    d.phase_valid = 0; d.rst_n = 0; tick(d); tick(d);
    d.initial_preset = 4;
    d.initial_coeff_valid = 1; d.initial_coeff = 0x00a00;
    d.rst_n = 1; tick(d);
    enter_phase(d, 0);
    require(d.tx_eq_control == 0x20, "phase0 sends EC00 with P4");
    require((d.tx_eq_data & 0x3f) == 0,
            "phase0 queried pre-cursor field");
    require(((d.tx_eq_data >> 8) & 0x3f) == 40,
            "phase0 queried main-cursor field");
    require(((d.tx_eq_data >> 16) & 0x3f) == 0,
            "phase0 queried post-cursor field");
    require(((d.tx_eq_data >> 22) & 1) == 0,
            "phase0 queried fields are not Reject");
    require((__builtin_parity(d.tx_eq_control) ^
             __builtin_parity(d.tx_eq_data)) == 0,
            "phase0 Symbols 6-9 even parity");
    set_tuple(d, 0x21, 40, 12, 0);
    pulse_ts(d); require(d.operation_state != 6,
                         "phase0 one EC01 insufficient");
    set_tuple(d, 0x29, 40, 12, 0);
    pulse_ts(d); require(d.operation_state != 6,
                         "phase0 tuple change resets count");
    set_tuple(d, 0x21, 40, 12, 0);
    pulse_ts(d); pulse_ts(d);
    require(d.operation_state == 6, "phase0 two exact EC01");

    // Phase 1 (spec 4.2.6.4.2.2.2): a pure announcement.  The partner's
    // EC=01 stream advertises ITS OWN transmitter (preset field = its own
    // TX preset), so nothing is applied at Phase-1 entry or during the
    // phase.
    enter_phase(d, 1);
    require(d.tx_eq_control == 0x21, "phase1 announces EC01 with our P4");
    require((d.tx_eq_data & 0x3f) == 40, "phase1 advertises FS");
    require(((d.tx_eq_data >> 8) & 0x3f) == 12, "phase1 advertises LF");
    // Two identical partner EC=01 TS1s (its own advertisement): no PHY
    // command is ever issued in Phase 1.
    set_tuple(d, 0x39, 0, 40, 0);
    pulse_ts(d); pulse_ts(d);
    require(d.eq_req_valid == 0 && d.operation_state == 0,
            "phase1 never applies the partner advertisement");
    // The downstream moves to its Phase 2: an EC=10 pair carrying its
    // transmitter settings ends Phase 1 and is handed to Phase 2 as the
    // maintain-reflection seed.
    set_tuple(d, 0x3a, 0, 35, 5);
    pulse_ts(d); require(d.operation_state != 6,
                         "phase1 one partner EC10 insufficient");
    pulse_ts(d);
    require(d.operation_state == 6,
            "phase1 exits on partner EC10 pair (partner started Phase 2)");
    std::cout << "K15_EQ_PHASE1_EC10_EXIT_PASS\n";

    // Phase 2 (spec 4.2.6.4.2.2.3): every EC=10 TS1 we transmit is a
    // request targeting the DOWNSTREAM transmitter.  The first request
    // reflects the advertisement received in the EC=10 pair that ended
    // Phase 1 ("maintain current settings"): Use Preset, preset field and
    // coefficient fields are all echoed, so the stream content is
    // identical to the partner's P7 advertisement tuple (0x3a).
    enter_phase(d, 2);
    require(d.tx_eq_control == 0x3a,
            "phase2 first request reflects the partner advertisement");
    require(d.tx_eq_data == eq_data(0x3a, 0, 35, 5),
            "phase2 maintain request echoes the partner coefficients");
    require(d.operation_state == 1, "phase2 issues first RX adapt");
    d.eq_done = 1; d.eq_result = 2; d.eq_rsp_preset_sel = 1;
    d.eq_rsp_coeff = 6; tick(d); d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.tx_eq_control == 0xb2, "phase2 sends preset proposal");
    // The downstream applies the preset-6 request to its own transmitter
    // and advertises EC=10 with Use Preset=0, the applied preset number
    // (6) in the preset field, and its transmitter coefficients (SVT VIP
    // ground truth) -- the preset field match accepts it, Reject=0.
    set_tuple(d, 0x32, 0, 36, 12);
    pulse_ts(d); require(d.operation_state == 2,
                         "phase2 one advertisement insufficient");
    pulse_ts(d); tick(d);
    require(d.operation_state == 1, "phase2 re-adapts after acceptance");
    require(d.eq_req_preset == 6, "phase2 retry adapts to accepted P6");
    require(d.tx_eq_control == 0xb2,
            "phase2 retry keeps requesting the accepted P6");
    require(d.tx_eq_data == eq_data(0xb2, 0, 40, 0),
            "phase2 retry does not revert to the old P7 tuple");
    d.eq_done = 1; d.eq_result = 1; tick(d);
    d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.operation_state == 6, "phase2 concludes on RX success");
    require((d.tx_eq_control & 3) == 3,
            "phase2 close streams EC11 (moves the downstream to Phase 3)");
    require(((d.tx_eq_control >> 3) & 0xf) == 4,
            "phase2 close reports our TX preset P4");

    // Phase 3 (spec 4.2.6.4.2.2.4): we transmit EC=11 and APPLY the
    // downstream's EC=11 requests to our own transmitter.  The base stream
    // carries our current settings (P4, queried coefficients 0/40/0).
    enter_phase(d, 3);
    require((d.tx_eq_control & 3) == 3, "phase3 base streams EC11");
    require(d.tx_eq_control == 0x23,
            "phase3 base reports our TX preset P4");
    require(d.tx_eq_data == eq_data(0x23, 0, 40, 0),
            "phase3 base carries our transmitter coefficients");
    // The downstream's first request reflects our EC=11 base stream (a
    // maintain request) -- identical content to our own stream, so it must
    // not be re-applied.
    set_tuple(d, 0x23, 0, 40, 0);
    pulse_ts(d); pulse_ts(d); tick(d);
    require(d.eq_req_valid == 0 && d.operation_state == 0,
            "phase3 maintain echo is not re-applied");
    // Preset request: EC=11, Use Preset=1, preset 6 (control 0xb3).
    set_tuple(d, 0xb3, 0, 40, 0);
    pulse_ts(d); require(d.eq_req_valid == 0,
                         "phase3 one request insufficient");
    d.ts1_valid = 1; tick(d); d.ts1_valid = 0;
    require(d.eq_req_valid == 1 && d.eq_req_kind == 0 &&
            d.eq_req_preset == 6,
            "phase3 applies EC11 preset request");
    tick(d);
    require(d.operation_state == 3, "phase3 preset apply in flight");
    d.eq_done = 1; d.eq_result = 1; tick(d);
    d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.operation_state == 5, "phase3 reflects applied preset");
    require(d.tx_eq_control == 0x33,
            "reflection carries applied preset P6 with EC11");
    require(d.tx_eq_data == eq_data(0x33, 5, 35, 0),
            "reflection carries P6 transmitter coefficients");
    // Illegal preset request: EC=11 with reserved preset 11 (0xdb) is
    // reflected with Reject=1 and never reaches the PHY.
    set_tuple(d, 0xdb, 0, 40, 0);
    pulse_ts(d); pulse_ts(d); tick(d);
    require(d.operation_state == 5 && ((d.tx_eq_data >> 22) & 1),
            "phase3 rejects reserved preset without PHY command");
    require(d.tx_eq_control == 0xdb,
            "rejection reflects the requested preset with EC11");
    // Legal coefficient request: EC=11, Use Preset=0, 0/28/12
    // (sum=FS=40, C0-|C-1|-|C+1|=16 >= LF=12).
    set_tuple(d, 0x03, 0, 28, 12);
    pulse_ts(d); require(d.eq_req_valid == 0,
                         "phase3 one coeff request insufficient");
    d.ts1_valid = 1; tick(d); d.ts1_valid = 0;
    require(d.eq_req_valid == 1 && d.eq_req_kind == 1 &&
            d.eq_req_coeff == ((0u << 12) | (28u << 6) | 12u),
            "phase3 applies EC11 coefficient request");
    tick(d);
    require(d.operation_state == 3, "phase3 coeff apply in flight");
    d.eq_done = 1; d.eq_result = 1;
    d.eq_rsp_coeff = (4u << 12) | (36u << 6); tick(d);
    d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.operation_state == 5, "phase3 reflects applied coefficients");
    require(d.tx_eq_control == 0x33,
            "coeff reflection keeps the last preset field (P6)");
    require(d.tx_eq_data == eq_data(0x33, 4, 36, 0),
            "coeff reflection carries the applied coefficients");
    // The downstream ends the equalization procedure with an EC=00 pair.
    set_tuple(d, 0x20, 0, 40, 0);
    pulse_ts(d); require(d.operation_state != 6,
                         "phase3 one EC00 insufficient");
    pulse_ts(d); require(d.operation_state == 6,
                         "phase3 exits on partner EC00 pair");
    std::cout << "K15_EQ_PHASES_DIRECTED_PASS\n";

    // A Phase-2 proposal answered with Reject=1 is a deterministic failure
    // and must not launch another RX adaptation.  (Fresh reset: Phase 2 is
    // entered without a partner advertisement, so the request stream is
    // seeded with a maintain request for the partner's advertised preset.)
    d.phase_valid = 0; d.rst_n = 0; tick(d); tick(d); d.rst_n = 1; tick(d);
    enter_phase(d, 2);
    require(d.operation_state == 1, "reject: phase2 issues first adapt");
    d.eq_done = 1; d.eq_result = 2; d.eq_rsp_preset_sel = 1;
    d.eq_rsp_coeff = 6; tick(d); d.eq_done = 0; d.eq_result = 0; tick(d);
    set_tuple(d, 0x32, 0, 36, 12, true);
    pulse_ts(d); pulse_ts(d);
    require(d.operation_state == 7,
            "phase2 Reject=1 fails instead of retrying proposal");
    std::cout << "K15_EQ_REJECT_FALLBACK_PASS\n";

    // Skip exit (spec 4.2.6.4.2.2.2): a downstream that does not want to
    // execute Phase 2/3 goes straight to Recovery.RcvrLock and streams
    // EC=00 TS1s.  The upstream needs EIGHT consecutive EC=00 TS1s (a
    // stray EC=00 announcement must not end Phase 1), and the exit raises
    // phase1_exit_skip so the LTSSM goes to RcvrLock instead of Phase 2.
    d.phase_valid = 0; d.rst_n = 0; tick(d); tick(d); d.rst_n = 1; tick(d);
    enter_phase(d, 1);
    // A single EC=00 TS1 followed by the partner's EC=01 advertisement
    // must not trip the skip path.
    set_tuple(d, 0x20, 0, 40, 0);
    pulse_ts(d);
    set_tuple(d, 0x21, 40, 12, 0);
    pulse_ts(d);
    require(d.operation_state != 6,
            "phase1 stray EC00 then EC01 keeps Phase 1 alive");
    set_tuple(d, 0x20, 0, 40, 0);
    pulse_ts(d); pulse_ts(d); pulse_ts(d);
    require(d.operation_state != 6 && d.phase1_exit_skip == 0,
            "phase1 three EC00 insufficient for the skip exit");
    for (int i = 0; i < 5; ++i) pulse_ts(d);
    require(d.operation_state == 6,
            "phase1 exits on eight consecutive EC00 TS1s");
    require(d.phase1_exit_skip == 1,
            "skip exit raises phase1_exit_skip");
    std::cout << "K15_EQ_PHASE1_SKIP_EXIT_PASS\n";
    d.phase_valid = 0;

    d.phase_valid = 0;
    d.rst_n = 0; d.idle_enable = 0; d.idle_l0_active = 0;
    d.training_enable = 0; tick(d); tick(d);
    d.rst_n = 1; d.training_enable = 1; d.eval();
    for (int i = 0; i < 4; ++i) {
        require(d.training_valid, "training prefix valid");
        require(d.training_data == 0xff00ff00, "training starts with EIEOS");
        require(d.training_start_block == (i == 0), "EIEOS block boundary");
        require(d.training_sync_header == (i == 0 ? 0x1 : 0x0),
                "EIEOS sync header follows block boundary");
        tick(d);
    }
    // pcie_gen3_os_tx (as verified against the Xilinx RP and the SVT VIP in
    // 2252e15) does not emit an SKP OS immediately after EIEOS: the explicit
    // 16-symbol SKP OS replaces the 8th block of the 16-block run once every
    // SKP_PERIOD+1 cadence periods, and the GT secureip substitutes real SKPs
    // in the valid gaps.  The periodic-SKP loop below covers it.  The TS1
    // stream therefore starts directly after the EIEOS re-seed.
    // First four Phase-0 TS1 blocks captured at the passing Xilinx hard-IP
    // Endpoint's lane-0 GT input.  Exact comparison catches both scrambler
    // continuity and the Symbol 14/15 running-DC substitution decision.
    const unsigned xilinx_phase0_ts[16] = {
        0x6794221e, 0xcef8c65d, 0x8b3fea78, 0x4d89054e,
        0xf9c6b91e, 0xab94b0ad, 0x1d86912d, 0x39082304,
        0xfcb7901e, 0x5e9a45ee, 0x099d6b18, 0x9abf1766,
        0x7176de1e, 0x57f19dcd, 0xeb3c7fe5, 0x082e0630
    };
    for (int i = 0; i < 16; ++i) {
        require(d.training_data == xilinx_phase0_ts[i],
                "Phase0 TS differs from Xilinx golden");
        require(d.training_start_block == ((i & 3) == 0),
                "Phase0 TS block boundary");
        require(d.training_sync_header == (((i & 3) == 0) ? 0x1 : 0x0),
                "Phase0 TS sync header");
        tick(d);
    }
    int periodic_skp_started = 0;
    int periodic_skp_completed = 0;
    int blocks_since_skp = 0;
    int skp_word = -1;
    for (int i = 0; i < 3200 && periodic_skp_completed < 2; ++i) {
        if (d.training_start_block && d.training_data == 0xaaaaaaaa) {
            if (periodic_skp_started > 0)
                require(blocks_since_skp <= 375,
                        "periodic SKP interval exceeds 375 blocks");
            ++periodic_skp_started;
            blocks_since_skp = 0;
            skp_word = 0;
        } else {
            if (d.training_start_block && periodic_skp_started > 0)
                ++blocks_since_skp;
            if (skp_word >= 0)
                ++skp_word;
        }
        if (skp_word >= 0 && skp_word < 3) {
            require(d.training_data == 0xaaaaaaaa,
                    "periodic SKP prefix malformed");
        } else if (skp_word == 3) {
            require((d.training_data & 0xff) == 0xe1,
                    "periodic SKP_END identifier");
            require(d.training_data != 0xbcbf9de1,
                    "periodic SKP_END must carry live LFSR state");
            ++periodic_skp_completed;
            skp_word = -1;
        } else if (skp_word >= 0) {
            ++skp_word;
        }
        tick(d);
        require(!d.idle_malformed,
                "dynamic periodic SKP rejected by receiver");
    }
    require(periodic_skp_completed == 2,
            "periodic dynamic SKP did not recur");
    std::cout << "K15_DYNAMIC_SKP_END_PASS recurring=2\n";
    d.training_enable = 0;
    d.idle_enable = 1;
    int idle_pulses = 0;
    for (int i = 0; i < 80; ++i) {
        tick(d);
        require(!d.idle_malformed, "idle stream malformed");
        if (d.idle_valid) ++idle_pulses;
    }
    require(idle_pulses >= 8, "idle block loopback");
    std::cout << "K15_GEN3_IDLE_STREAM_PASS blocks=" << idle_pulses << '\n';

    // Entering L0 discards the Recovery.Idle cadence phase and schedules the
    // first gap after the current block plus two complete 128b blocks.  This
    // targets 12 valid beats here (11-12 in the integrated design depending on
    // the exact LTSSM transition beat), safely below the observed no-gap
    // overflow point.  Thereafter normal 64-valid/1-gap duty resumes.  Reset
    // the source so the counts are independent of the
    // preceding long SKP test.
    d.rst_n = 0; d.idle_enable = 0; d.idle_l0_active = 0;
    tick(d); tick(d);
    d.rst_n = 1; d.idle_enable = 1;
    int recovery_gaps = 0;
    while (recovery_gaps == 0) {
        tick(d);
        if (!d.idle_data_valid) ++recovery_gaps;
    }
    d.idle_l0_active = 1;
    int valid_since_l0 = 0;
    int first_l0_gap_at = -1;
    for (int i = 0; i < 160 && first_l0_gap_at < 0; ++i) {
        tick(d);
        if (d.idle_data_valid)
            ++valid_since_l0;
        else
            first_l0_gap_at = valid_since_l0;
    }
    require(first_l0_gap_at == 12,
            "L0 rephase must place the first gap after three blocks");
    std::cout << "K15_L0_TX_PREWARM_PASS valid_beats="
              << first_l0_gap_at << '\n';

    // Count actual transmitted block starts, including blocks that coincide
    // with a rate-gap decision.  This catches the former counter bug where
    // every 16th completed Idle Data Block was omitted and the first SKP OS
    // arrived after a receiver's 375-block deadline.
    d.rst_n = 0; d.idle_enable = 0; d.idle_l0_active = 0;
    tick(d); tick(d);
    d.rst_n = 1; d.idle_enable = 1;
    d.eval();
    bool idle_data_started = false;
    for (int i = 0; i < 16 && !idle_data_started; ++i) {
        tick(d);
        idle_data_started = d.idle_start_block &&
                            d.idle_sync_header == 0x2;
    }
    require(idle_data_started, "L0 idle data stream did not start");
    d.idle_l0_active = 1;
    int l0_blocks_to_skp = 0;
    bool idle_skp_seen = false;
    for (int i = 0; i < 1800 && !idle_skp_seen; ++i) {
        if (d.idle_start_block) {
            if (d.idle_sync_header == 0x1 &&
                d.idle_data == 0xaaaaaaaa)
                idle_skp_seen = true;
            else
                ++l0_blocks_to_skp;
        }
        tick(d);
    }
    require(idle_skp_seen, "L0 periodic SKP was not transmitted");
    require(l0_blocks_to_skp <= 375,
            "L0 first SKP interval exceeds 375 blocks");
    std::cout << "K15_L0_SKP_INTERVAL_PASS blocks="
              << l0_blocks_to_skp << '\n';
    std::cout << "K15_EQ_EIEOS_SKP_TS_PASS\n";
    d.final();
    return 0;
}
