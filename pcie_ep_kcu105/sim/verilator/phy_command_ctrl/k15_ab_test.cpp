#include "Vk15_ab_test_top.h"
#include "verilated.h"
#include <cstdlib>
#include <iostream>

static void fail(const char *message) {
    std::cerr << "K15_PHY_AB_FAIL " << message << '\n';
    std::exit(1);
}

static void tick(Vk15_ab_test_top &dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.clk = 0;
    dut.eval();
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vk15_ab_test_top dut;
    dut.clk = 0;
    dut.rst_n = 0;
    dut.rate_req_valid = 0;
    dut.rate_req_target = 2;
    dut.phy_phystatus = 0;
    dut.eval();
    tick(dut);
    dut.rst_n = 1;

    const bool expect_cdr = dut.variant_cdr_hold;
    const bool expect_txeq = dut.variant_prerate_txeq;
    const bool expect_query = dut.variant_prerate_query;
    const unsigned dwell = dut.variant_dwell;
    if (expect_cdr && dut.rate_busy && !dut.as_cdr_hold_req)
        fail("CDR hold is asserted outside the rate envelope");

    dut.rate_req_valid = 1;
    dut.eval();
    tick(dut);
    dut.rate_req_valid = 0;

    bool saw_prerate = false;
    bool saw_txeq = false;
    bool saw_clear = false;
    bool saw_query = false;
    bool saw_query_clear = false;
    unsigned prerate_cycles = 0;
    bool saw_gen3 = false;
    for (unsigned cycle = 0; cycle < 100; ++cycle) {
        dut.eval();
        if (dut.rate_busy && dut.as_cdr_hold_req != expect_cdr)
            fail("CDR hold variant changed during the rate envelope");
        if (dut.rate_state == 8) {
            saw_prerate = true;
            ++prerate_cycles;
            if (dut.phy_txeq_ctrl == 1) {
                saw_txeq = true;
                if (dut.phy_txeq_preset != 7)
                    fail("pre-rate TXEQ did not use qualified EQ TS2 preset");
            } else if (dut.phy_txeq_ctrl != 0) {
                fail("unexpected pre-rate TXEQ command");
            }
        } else if (dut.rate_state == 9) {
            saw_clear = true;
            if (dut.phy_txeq_ctrl != 0 || dut.phy_rate != 0)
                fail("TXEQ clear cycle is not Gen1 and inactive");
        } else if (dut.rate_state == 10) {
            saw_query = true;
            if (dut.phy_txeq_ctrl != 3 || dut.phy_rate != 0)
                fail("canonical coefficient Query command missing");
        } else if (dut.rate_state == 11) {
            saw_query_clear = true;
            if (dut.phy_txeq_ctrl != 0 || dut.phy_rate != 0)
                fail("Query clear cycle is not Gen1 and inactive");
        }
        if (dut.phy_rate == 2) {
            if (dut.phy_txeq_ctrl != 0)
                fail("PHY_RATE changed before TXEQ was cleared");
            saw_gen3 = true;
            break;
        }
        tick(dut);
    }
    if (!saw_gen3)
        fail("Gen3 rate was not applied");
    if (dwell != 0 && (!saw_prerate || prerate_cycles != dwell || !saw_clear))
        fail("pre-rate dwell/clear envelope length mismatch");
    if (saw_txeq != expect_txeq)
        fail("pre-rate TXEQ presence does not match variant");
    if (saw_query != expect_query || saw_query_clear != expect_query)
        fail("pre-rate Query/clear presence does not match variant");
    if (dut.prerate_query_valid != expect_query)
        fail("sticky Query valid does not match variant");
    if (expect_query && dut.prerate_query_coeff != 0x3941)
        fail("Query coefficient field capture mismatch");

    while (dut.rate_state != 4)
        tick(dut);
    dut.phy_phystatus = 1;
    tick(dut);
    dut.phy_phystatus = 0;
    for (unsigned cycle = 0; cycle < 20 && !dut.rate_done; ++cycle)
        tick(dut);
    if (!dut.rate_done || dut.rate_result != 1)
        fail("Gen3 PhyStatus completion missing");

    std::cout << "K15_PHY_AB_PASS cdr=" << (expect_cdr ? 1 : 0)
              << " txeq=" << (expect_txeq ? 1 : 0)
              << " query=" << (expect_query ? 1 : 0)
              << " dwell=" << dwell
              << " prerate_cycles=" << prerate_cycles << '\n';
    dut.final();
    return 0;
}
