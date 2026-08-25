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

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vpcie_phy_command_ctrl dut;
    dut.phy_pclk = 0;
    dut.pipe_rst_n = 0;
    dut.cmd_profile = 0;
    dut.op_valid = 0;
    dut.op_kind = 0;
    dut.phy_phystatus = 0;
    dut.phy_rxstatus = 0;
    dut.eval();
    require(!dut.op_ready && !dut.op_done && dut.op_result == 0,
            "reset handshake");
    dut.pipe_rst_n = 1;

    const unsigned expected[6] = {
        0b10'0'1'1'0, 0b10'1'1'1'0, 0b00'0'1'0'0,
        0b00'0'1'1'0, 0b00'0'0'0'0, 0b00'0'0'0'1,
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

    std::cout << "PHY_COMMAND_CTRL_EQUIVALENCE_PASS\n";
    dut.final();
    return 0;
}
