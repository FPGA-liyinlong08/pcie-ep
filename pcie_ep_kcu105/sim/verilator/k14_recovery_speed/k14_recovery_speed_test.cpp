#include <cassert>
#include <cstdint>
#include <iostream>

#include "Vk14_recovery_speed_test_top.h"
#include "verilated.h"

static void tick(Vk14_recovery_speed_test_top &dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.clk = 0;
    dut.eval();
}

static void reset(Vk14_recovery_speed_test_top &dut) {
    dut.rst_n = 0;
    dut.retrain_valid = 0;
    dut.retrain_target = 0;
    dut.retrain_rearm = 0;
    dut.retrain_accept_enable = 1;
    dut.ltssm_speed_ready = 0;
    dut.phy_phystatus = 0;
    dut.peer_speed_ok = 0;
    dut.reinitialize_gen1 = 0;
    tick(dut);
    tick(dut);
    dut.rst_n = 1;
    tick(dut);
    assert(dut.speed_state == 0);
    assert(dut.rate_state == 0);
    assert(dut.active_rate == 0);
    assert(dut.phy_rate == 0);
    assert(!dut.retrain_pending);
    assert(dut.retrain_armed);
}

static void start_gen3(Vk14_recovery_speed_test_top &dut) {
    dut.retrain_target = 2;
    dut.retrain_valid = 1;
    tick(dut);
    assert(dut.retrain_pending);
    assert(!dut.retrain_accept);
    dut.retrain_valid = 0;
    tick(dut);
    assert(dut.retrain_accept);
    assert(dut.speed_state == 1);
    assert(dut.traffic_quiesce);
    tick(dut);
    assert(!dut.retrain_pending);
    assert(!dut.retrain_armed);
    dut.ltssm_speed_ready = 1;
    tick(dut);
    assert(dut.speed_state == 2);
    tick(dut);
    dut.ltssm_speed_ready = 0;
    assert(dut.speed_state == 3);
    // K15 performs the mandatory TX preset/clear transaction before entering
    // the unchanged K14 Golden release state.
    for (int cycle = 0; cycle < 8 && dut.rate_state != 1; ++cycle)
        tick(dut);
    assert(dut.rate_state == 1);
}

static void test_partner_pending_handshake(
    Vk14_recovery_speed_test_top &dut
) {
    reset(dut);
    dut.retrain_accept_enable = 0;
    dut.retrain_target = 2;
    dut.retrain_valid = 1;
    tick(dut);
    dut.retrain_valid = 0;
    assert(dut.retrain_pending);
    assert(dut.retrain_armed);

    for (int cycle = 0; cycle < 4; ++cycle) {
        tick(dut);
        assert(dut.retrain_pending);
        assert(!dut.retrain_accept);
        assert(dut.speed_state == 0);
    }

    // Repeated copies of the same semantic request do not create a second
    // transaction while the first request is pending.
    dut.retrain_valid = 1;
    tick(dut);
    dut.retrain_valid = 0;
    assert(dut.retrain_pending);

    dut.retrain_accept_enable = 1;
    tick(dut);
    assert(dut.retrain_accept);
    assert(dut.speed_state == 1);
    tick(dut);
    assert(!dut.retrain_pending);
    assert(!dut.retrain_armed);

    for (int copy = 0; copy < 3; ++copy) {
        dut.retrain_valid = 1;
        tick(dut);
        dut.retrain_valid = 0;
        tick(dut);
        assert(!dut.retrain_pending);
        assert(!dut.retrain_armed);
    }
}

static void test_reset_clears_and_rearms_partner_request(
    Vk14_recovery_speed_test_top &dut
) {
    reset(dut);
    dut.retrain_accept_enable = 0;
    dut.retrain_target = 2;
    dut.retrain_valid = 1;
    tick(dut);
    dut.retrain_valid = 0;
    assert(dut.retrain_pending);

    dut.rst_n = 0;
    tick(dut);
    assert(!dut.retrain_pending);
    assert(dut.retrain_armed);
    dut.rst_n = 1;
    dut.retrain_accept_enable = 1;
    tick(dut);

    start_gen3(dut);
}

static void assert_golden_envelope(
    const Vk14_recovery_speed_test_top &dut
) {
    assert(dut.phy_powerdown == 0);
    assert(dut.phy_txelecidle == 1);
    assert(dut.phy_txdetectrx == 0);
    assert(dut.as_mac_in_detect == 0);
    assert(dut.as_cdr_hold_req == 0);
}

static void test_happy_path(Vk14_recovery_speed_test_top &dut) {
    reset(dut);
    start_gen3(dut);

    int gap_cycles = 0;
    while (dut.rate_state != 3) {
        assert_golden_envelope(dut);
        assert(dut.phy_rate == 0);
        if (dut.rate_state == 2) ++gap_cycles;
        tick(dut);
    }
    assert(gap_cycles == 4);
    assert_golden_envelope(dut);
    assert(dut.phy_rate == 2);

    tick(dut);
    assert(dut.rate_state == 4);
    dut.phy_phystatus = 1;
    tick(dut);
    dut.phy_phystatus = 0;
    assert(dut.rate_state == 5);
    assert_golden_envelope(dut);

    bool completed = false;
    for (int cycle = 0; cycle < 8; ++cycle) {
        tick(dut);
        if (dut.rate_done && dut.rate_result == 1) {
            completed = true;
            break;
        }
    }
    assert(completed);
    assert(dut.rate_state == 0);
    assert(dut.active_rate == 2);
    assert(dut.phy_rate == 2);
    // The semantic coordinator consumes the controller's registered done
    // pulse on the following clock edge.
    tick(dut);
    assert(dut.speed_state == 4);

    dut.peer_speed_ok = 1;
    tick(dut);
    dut.peer_speed_ok = 0;
    assert(dut.speed_state == 0);
    assert(dut.negotiated_speed == 2);
    assert(!dut.traffic_quiesce);
}

static void reach_rate_state(
    Vk14_recovery_speed_test_top &dut, uint8_t target_state
) {
    reset(dut);
    start_gen3(dut);
    for (int cycle = 0; cycle < 32 && dut.rate_state != target_state; ++cycle) {
        if (dut.rate_state == 4 && target_state >= 5) {
            dut.phy_phystatus = 1;
        }
        tick(dut);
        dut.phy_phystatus = 0;
    }
    assert(dut.rate_state == target_state);
}

static void test_reinitialize_aborts_every_substate(
    Vk14_recovery_speed_test_top &dut
) {
    for (uint8_t state = 1; state <= 5; ++state) {
        reach_rate_state(dut, state);
        dut.reinitialize_gen1 = 1;
        tick(dut);
        assert(dut.rate_state == 0);
        assert(dut.speed_state == 0);
        assert(dut.active_rate == 0);
        assert(dut.phy_rate == 0);
        assert(dut.rate_done);
        assert(dut.rate_result == 4);
        dut.reinitialize_gen1 = 0;
        tick(dut);
        assert(!dut.rate_done);
    }
}

static void test_stale_phystatus_times_out_to_fallback(
    Vk14_recovery_speed_test_top &dut
) {
    reset(dut);
    dut.phy_phystatus = 1;
    tick(dut);
    start_gen3(dut);
    bool failed = false;
    for (int cycle = 0; cycle < 32; ++cycle) {
        tick(dut);
        if (dut.rate_done && dut.rate_result == 3) {
            failed = true;
            break;
        }
    }
    assert(failed);
    tick(dut);
    assert(dut.active_rate == 0);
    assert(dut.phy_rate == 0);
    assert(dut.fallback_taken);
    dut.phy_phystatus = 0;
}

static void test_peer_timeout_falls_back_without_retrigger(
    Vk14_recovery_speed_test_top &dut
) {
    reset(dut);
    start_gen3(dut);

    while (dut.rate_state != 3) tick(dut);
    tick(dut);
    assert(dut.rate_state == 4);
    assert(dut.phy_rate == 2);
    dut.phy_phystatus = 1;
    tick(dut);
    dut.phy_phystatus = 0;

    bool gen3_done = false;
    for (int cycle = 0; cycle < 16; ++cycle) {
        tick(dut);
        if (dut.rate_done && dut.rate_result == 1) {
            gen3_done = true;
            break;
        }
    }
    assert(gen3_done);
    assert(dut.active_rate == 2);
    tick(dut);
    assert(dut.speed_state == 4);

    // No peer completion is provided.  The semantic timeout must request a
    // Recovery.Speed rendezvous, then a real Gen1 PHY transaction, and
    // consume a fresh fallback PhyStatus edge.  The rate request must not run
    // ahead of the LTSSM as rate_done is a one-cycle pulse.
    bool fallback_speed_rendezvous = false;
    bool fallback_phystatus_sent = false;
    bool fallback_complete = false;
    for (int cycle = 0; cycle < 160; ++cycle) {
        if (!fallback_speed_rendezvous && dut.speed_state == 5) {
            assert(dut.rate_state == 0);
            assert(dut.phy_rate == 2);
            dut.ltssm_speed_ready = 1;
            fallback_speed_rendezvous = true;
        }
        if (!fallback_phystatus_sent && dut.rate_state == 4 &&
            dut.phy_rate == 0) {
            dut.phy_phystatus = 1;
            fallback_phystatus_sent = true;
        }
        tick(dut);
        if (fallback_speed_rendezvous && dut.speed_state == 6)
            dut.ltssm_speed_ready = 0;
        dut.phy_phystatus = 0;
        if (fallback_phystatus_sent && dut.active_rate == 0 &&
            dut.speed_state == 0) {
            fallback_complete = true;
            break;
        }
    }
    assert(fallback_speed_rendezvous);
    assert(fallback_phystatus_sent);
    assert(fallback_complete);
    assert(dut.fallback_taken);
    assert(dut.phy_rate == 0);
    assert(!dut.retrain_pending);
    assert(!dut.retrain_armed);

    // Copies of the already-consumed request cannot start a second excursion.
    for (int copy = 0; copy < 3; ++copy) {
        dut.retrain_valid = 1;
        tick(dut);
        dut.retrain_valid = 0;
        tick(dut);
        assert(!dut.retrain_pending);
        assert(dut.speed_state == 0);
        assert(dut.active_rate == 0);
        assert(dut.phy_rate == 0);
    }

    // A protocol epoch boundary explicitly re-arms reception of a genuinely
    // new partner request.
    dut.retrain_rearm = 1;
    tick(dut);
    dut.retrain_rearm = 0;
    assert(dut.retrain_armed);
    dut.retrain_valid = 1;
    tick(dut);
    dut.retrain_valid = 0;
    assert(dut.retrain_pending);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vk14_recovery_speed_test_top dut;
    test_partner_pending_handshake(dut);
    std::cout << "K14_PARTNER_PENDING_ACCEPT_PASS\n";
    test_reset_clears_and_rearms_partner_request(dut);
    std::cout << "K14_PARTNER_RESET_REARM_PASS\n";
    test_happy_path(dut);
    std::cout << "K14_GEN3_RATE_SUCCESS_PASS\n";
    test_reinitialize_aborts_every_substate(dut);
    std::cout << "K14_REINITIALIZE_ABORT_PASS\n";
    test_stale_phystatus_times_out_to_fallback(dut);
    std::cout << "K14_STALE_PHYSTATUS_FALLBACK_PASS\n";
    test_peer_timeout_falls_back_without_retrigger(dut);
    std::cout << "K14_PEER_TIMEOUT_GEN1_FALLBACK_PASS\n";
    std::cout << "K14_RECOVERY_SPEED_SEMANTIC_PASS\n";
    dut.final();
    return 0;
}
