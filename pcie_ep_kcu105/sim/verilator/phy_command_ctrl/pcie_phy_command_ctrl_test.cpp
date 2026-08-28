#include "Vpcie_phy_command_ctrl.h"
#include "verilated.h"
#include <cstdlib>
#include <iostream>

static void require(bool condition, const char *message) {
    if (!condition) {
        std::cerr << "PHY_COMMAND_CTRL_TEST_FAIL " << message << '\n';
        std::exit(1);
    }
}

static void tick(Vpcie_phy_command_ctrl &dut) {
    dut.phy_pclk = 0;
    dut.eval();
    dut.phy_pclk = 1;
    dut.eval();
    dut.phy_pclk = 0;
    dut.eval();
}

static void reset(Vpcie_phy_command_ctrl &dut) {
    dut.pipe_rst_n = 0;
    dut.eval();
    tick(dut);
    dut.pipe_rst_n = 1;
    dut.rate_req_valid = 0;
    dut.rate_req_target = 0;
    dut.rate_abort = 0;
    dut.phy_phystatus = 0;
    dut.eq_req_valid = 0;
    dut.eq_req_kind = 0;
    dut.eq_req_preset = 0;
    dut.eq_req_coeff = 0;
    dut.phy_txeq_fs = 0;
    dut.phy_txeq_lf = 0;
    dut.phy_txeq_new_coeff = 0;
    dut.phy_txeq_done = 0;
    dut.phy_rxeq_preset_sel = 0;
    dut.phy_rxeq_new_txcoeff = 0;
    dut.phy_rxeq_adapt_done = 0;
    dut.phy_rxeq_done = 0;
    dut.eval();
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vpcie_phy_command_ctrl dut;
    dut.phy_pclk = 0;
    dut.pipe_rst_n = 0;
    dut.cmd_profile = 0;
    dut.op_valid = 0;
    dut.op_kind = 0;
    dut.rate_req_valid = 0;
    dut.rate_req_target = 0;
    dut.rate_abort = 0;
    dut.phy_phystatus = 0;
    dut.phy_rxstatus = 0;
    dut.eq_req_valid = 0;
    dut.eq_req_kind = 0;
    dut.eq_req_preset = 0;
    dut.eq_req_coeff = 0;
    dut.phy_txeq_fs = 0;
    dut.phy_txeq_lf = 0;
    dut.phy_txeq_new_coeff = 0;
    dut.phy_txeq_done = 0;
    dut.phy_rxeq_preset_sel = 0;
    dut.phy_rxeq_new_txcoeff = 0;
    dut.phy_rxeq_adapt_done = 0;
    dut.phy_rxeq_done = 0;
    dut.eval();
    require(!dut.op_ready && !dut.op_done && dut.op_result == 0,
            "reset handshake");
    dut.pipe_rst_n = 1;

    const unsigned expected[6] = {
        0b10'0'1'1'0, 0b10'1'1'1'0, 0b00'0'1'0'0,
        0b00'0'1'1'0, 0b00'0'0'0'0, 0b00'0'0'0'0,
    };
    for (unsigned profile = 0; profile < 6; ++profile) {
        dut.cmd_profile = profile;
        dut.eval();
        unsigned bundle = (dut.phy_powerdown << 4) |
                          (dut.phy_txdetectrx << 3) |
                          (dut.phy_txelecidle << 2) |
                          (dut.as_mac_in_detect << 1) |
                          dut.as_cdr_hold_req;
        require(bundle == expected[profile], "profile mapping");
        require(dut.phy_rate == 0 && dut.phy_txeq_ctrl == 0 &&
                dut.phy_txeq_preset == 0 && dut.phy_txeq_coeff == 0 &&
                dut.phy_rxeq_ctrl == 0 && dut.phy_rxeq_txpreset == 0 &&
                !dut.phy_txcompliance && !dut.phy_rxpolarity &&
                dut.phy_txmargin == 0 && !dut.phy_txswing &&
                !dut.phy_txdeemph, "static Gen1 commands");
    }

    dut.op_valid = 1;
    dut.op_kind = 0;
    dut.phy_rxstatus = 3;
    dut.phy_phystatus = 0;
    dut.eval();
    require(!dut.op_done, "early receiver-detect completion");
    dut.phy_phystatus = 1;
    dut.eval();
    require(dut.op_done && dut.op_result == 1, "receiver present");
    dut.phy_phystatus = 0;
    dut.phy_rxstatus = 0;
    dut.eval();
    require(!dut.op_done, "completion follows current PhyStatus");
    dut.phy_phystatus = 1;
    dut.eval();
    require(dut.op_done && dut.op_result == 2, "receiver absent");
    dut.phy_phystatus = 0;
    dut.op_kind = 1;
    dut.eval();
    require(!dut.op_done, "independent P0 completion");
    dut.phy_phystatus = 1;
    dut.eval();
    require(dut.op_done && dut.op_result == 1, "P0 success");

    // K15 keeps the signed K14 Golden release-gap/rate/PhyStatus envelope
    // unchanged.  Equalization presets are issued later by the semantic EQ
    // executor, after the Gen3 rate transaction has completed.
    dut.op_valid = 0;
    dut.phy_phystatus = 0;
    dut.rate_req_valid = 1;
    dut.rate_req_target = 2;
    dut.eval();
    require(dut.rate_req_ready, "Gen3 request ready");
    tick(dut);
    dut.rate_req_valid = 0;
    require(dut.rate_state == 1 && dut.rate_busy && dut.phy_rate == 0,
            "release state");
    require(dut.phy_txelecidle && !dut.as_cdr_hold_req &&
            !dut.as_mac_in_detect && dut.phy_powerdown == 0,
            "Golden rate envelope");
    tick(dut);
    require(dut.rate_state == 2 && dut.phy_rate == 0, "Golden gap start");
    for (int i = 0; i < 3; ++i) {
        tick(dut);
        require(dut.phy_rate == 0, "Golden gap holds Gen1");
    }
    tick(dut);
    require(dut.rate_state == 3 && dut.phy_rate == 2,
            "Golden gap then apply Gen3");
    tick(dut);
    require(dut.rate_state == 4 && dut.active_rate == 0,
            "wait PhyStatus without early commit");
    dut.phy_phystatus = 1;
    tick(dut);
    dut.phy_phystatus = 0;
    require(dut.rate_state == 5 && dut.active_rate == 0,
            "fresh PhyStatus enters Gen3 settle");
    tick(dut);
    tick(dut);
    require(dut.rate_state == 6, "Gen3 settle duration");
    tick(dut);
    require(dut.rate_state == 0 && dut.rate_done &&
            dut.rate_result == 1 && dut.active_rate == 2 && dut.phy_rate == 2,
            "Gen3 semantic completion");
    tick(dut);
    require(!dut.rate_done, "rate_done is one cycle");

    // A second independent Gen3->Gen1 transaction uses the same Golden gap
    // and commits only on a new PhyStatus edge.
    dut.rate_req_valid = 1;
    dut.rate_req_target = 0;
    tick(dut);
    dut.rate_req_valid = 0;
    tick(dut);
    for (int i = 0; i < 4; ++i)
        tick(dut);
    require(dut.rate_state == 3 && dut.phy_rate == 0 &&
            dut.active_rate == 2, "Gen1 command before active commit");
    tick(dut);
    dut.phy_phystatus = 1;
    tick(dut);
    dut.phy_phystatus = 0;
    require(dut.rate_state == 6, "Gen1 completes without Gen3 settle");
    tick(dut);
    require(dut.rate_done && dut.rate_result == 1 &&
            dut.active_rate == 0, "second transaction complete");

    // A stale/high PhyStatus must not complete a new transaction.  Only a
    // low-to-high edge observed in WAIT is accepted.
    reset(dut);
    dut.phy_phystatus = 1;
    tick(dut);
    dut.rate_req_valid = 1;
    dut.rate_req_target = 2;
    tick(dut);
    dut.rate_req_valid = 0;
    tick(dut);
    tick(dut);
    for (int i = 0; i < 5; ++i)
        tick(dut);
    require(dut.rate_state == 4 && !dut.rate_done,
            "early PhyStatus is ignored");
    dut.phy_phystatus = 0;
    tick(dut);
    dut.phy_phystatus = 1;
    tick(dut);
    require(dut.rate_state == 5, "new PhyStatus edge accepted");

    // Abort from an in-flight state returns the exact Gen1 static baseline.
    dut.rate_abort = 1;
    tick(dut);
    dut.rate_abort = 0;
    dut.phy_phystatus = 0;
    require(dut.rate_state == 0 && dut.active_rate == 0 &&
            dut.phy_rate == 0 && dut.rate_done && dut.rate_result == 4,
            "rate abort restores Gen1");

    // Missing PhyStatus reaches a sticky-safe ERROR_HOLD envelope and reports
    // timeout once; abort is the only non-reset return path.
    tick(dut);
    dut.rate_req_valid = 1;
    dut.rate_req_target = 2;
    tick(dut);
    dut.rate_req_valid = 0;
    tick(dut);
    tick(dut);
    for (int i = 0; i < 5; ++i)
        tick(dut);
    for (int i = 0; i < 12 && dut.rate_state != 7; ++i)
        tick(dut);
    require(dut.rate_state == 7 && dut.rate_result == 3 && dut.rate_done &&
            dut.phy_rate == 2 && dut.phy_txelecidle,
            "PhyStatus timeout error hold");
    tick(dut);
    require(dut.rate_state == 7 && !dut.rate_done,
            "timeout result is one cycle");
    dut.rate_abort = 1;
    tick(dut);
    dut.rate_abort = 0;

    // Phase D rejects Gen2/reserved requests without touching raw commands.
    dut.rate_req_valid = 1;
    dut.rate_req_target = 1;
    tick(dut);
    dut.rate_req_valid = 0;
    require(dut.rate_done && dut.rate_result == 2 &&
            dut.rate_state == 0 && dut.phy_rate == 0,
            "illegal target rejected");

    // Semantic EQ remains behind the same raw owner. Check TX coefficient
    // sequencing and RX proposal sampling at the done boundary.
    tick(dut);
    dut.eq_req_valid = 1;
    dut.eq_req_kind = 1;
    dut.eq_req_coeff = 0x12345;
    tick(dut);
    dut.eq_req_valid = 0;
    require(dut.eq_busy && dut.phy_txeq_ctrl == 2 &&
            dut.phy_txeq_coeff == ((0x12345 >> 12) & 0x3f),
            "TX coefficient pre-cursor beat");
    tick(dut);
    require(dut.phy_txeq_coeff == ((0x12345 >> 6) & 0x3f),
            "TX coefficient main-cursor beat");
    tick(dut);
    require(dut.phy_txeq_coeff == (0x12345 & 0x3f),
            "TX coefficient post-cursor beat");
    dut.phy_txeq_done = 1;
    tick(dut);
    dut.phy_txeq_done = 0;
    require(dut.eq_done && dut.eq_result == 1 && !dut.eq_busy &&
            dut.phy_txeq_ctrl == 0, "TX coefficient completion");

    tick(dut);
    dut.eq_req_valid = 1;
    dut.eq_req_kind = 3;
    dut.eq_req_preset = 5;
    tick(dut);
    dut.eq_req_valid = 0;
    require(dut.eq_busy && dut.phy_rxeq_ctrl == 2 &&
            dut.phy_rxeq_txpreset == 5, "RX adapt request");
    dut.phy_rxeq_preset_sel = 1;
    dut.phy_rxeq_new_txcoeff = 7;
    dut.phy_rxeq_done = 1;
    dut.phy_rxeq_adapt_done = 0;
    tick(dut);
    dut.phy_rxeq_done = 0;
    require(dut.eq_done && dut.eq_result == 2 &&
            dut.eq_rsp_preset_sel && dut.eq_rsp_coeff == 7,
            "RX new proposal capture");

    std::cout << "PHY_COMMAND_CTRL_EQUIVALENCE_PASS\n";
    std::cout << "PHY_COMMAND_CTRL_GOLDEN_RATE_PASS\n";
    std::cout << "K15_PHY_EQ_SEMANTIC_PASS\n";
    dut.final();
    return 0;
}
