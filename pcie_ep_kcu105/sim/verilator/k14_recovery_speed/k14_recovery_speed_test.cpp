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
}

static void start_gen3(Vk14_recovery_speed_test_top &dut) {
    dut.retrain_target = 2;
    dut.retrain_valid = 1;
    tick(dut);
    assert(dut.retrain_accept);
    dut.retrain_valid = 0;
    assert(dut.speed_state == 1);
    assert(dut.traffic_quiesce);
    dut.ltssm_speed_ready = 1;
    tick(dut);
    assert(dut.speed_state == 2);
    tick(dut);
    dut.ltssm_speed_ready = 0;
    assert(dut.speed_state == 3);
    assert(dut.rate_state == 1);
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

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vk14_recovery_speed_test_top dut;
    test_happy_path(dut);
    test_reinitialize_aborts_every_substate(dut);
    test_stale_phystatus_times_out_to_fallback(dut);
    std::cout << "K14_RECOVERY_SPEED_SEMANTIC_PASS\n";
    dut.final();
    return 0;
}
