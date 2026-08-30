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

static void enter_phase(Vk15_eq_idle_test_top &d, unsigned phase) {
    d.phase_valid = 0; tick(d);
    d.phase = phase; d.phase_valid = 1; tick(d); tick(d);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vk15_eq_idle_test_top d;
    d.clk = 0; d.rst_n = 0; d.phase_valid = 0; d.phase = 0;
    d.ts1_valid = 0; d.ts2_valid = 0; d.ts_eq_control = 1;
    d.ts_eq_data = 0x8a0c28; d.tx_ts_complete = 0;
    d.eq_req_ready = 1; d.eq_busy = 0; d.eq_done = 0;
    d.eq_result = 0; d.eq_rsp_preset_sel = 0; d.eq_rsp_coeff = 0;
    d.idle_enable = 0; d.training_enable = 0; d.training_mode = 1;
    tick(d); tick(d); d.rst_n = 1; tick(d);

    enter_phase(d, 0);
    require(d.tx_eq_control == 0x20, "phase0 response");
    for (int i = 0; i < 8; ++i) pulse_ts(d);
    require(d.phase_done, "phase0 done");

    enter_phase(d, 1);
    for (int i = 0; i < 8; ++i) pulse_ts(d);
    require(d.tx_eq_control == 0x21, "phase1 ready response");
    for (int i = 0; i < 8; ++i) {
        d.tx_ts_complete = 1; tick(d); d.tx_ts_complete = 0; tick(d);
    }
    require(!d.phase_done, "phase1 waits for peer exit");
    d.ts_eq_control = 0x02; d.ts_eq_data = 0;
    d.ts1_valid = 1; tick(d);
    require(d.phase_done, "phase1 done");
    d.ts1_valid = 0; tick(d);
    // Phase 2 is identified by EC=10 in Symbol 6.  A stale Phase-1 TS1
    // and a TS2 must not launch RX Adapt.
    d.ts_eq_control = 0x01; d.ts_eq_data = 0x8a0c28;
    enter_phase(d, 2);
    require(d.tx_eq_control == 0x22, "phase2 response carries EC=10");
    require((d.tx_eq_control & 0x3) == 0x2, "phase2 EC field");
    require(d.operation_state == 0, "phase2 waits for partner TS1");
    pulse_ts(d);
    require(d.operation_state == 0, "phase2 rejects EC=01");
    require(!d.eq_req_valid, "phase2 does not request RX adapt for EC=01");
    d.ts_eq_control = 0xba;  // Use Preset=1, Transmitter Preset=7, EC=2.
    pulse_ts(d, true);
    require(d.operation_state == 0, "phase2 ignores TS2");
    pulse_ts(d);
    require(d.operation_state == 1, "phase2 RX adapt request");
    require(d.eq_req_preset == 7, "phase2 decodes Symbol6 transmitter preset");
    d.eq_done = 1; d.eq_result = 2; d.eq_rsp_preset_sel = 1;
    d.eq_rsp_coeff = 6; tick(d); d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.tx_eq_control == 0xb2, "phase2 preset proposal in Symbol6");
    require(d.tx_eq_data == 0x000c28, "preset proposal keeps Symbol7-9 tuple");
    d.ts_eq_control = 0xaa;  // Partner still reflects P5, not requested P6.
    pulse_ts(d);
    require(d.operation_state == 2, "phase2 waits for matching preset");
    d.ts_eq_control = 0xb2;
    pulse_ts(d, true);
    require(d.operation_state == 2, "phase2 does not accept matching TS2");
    pulse_ts(d);
    require(d.operation_state == 1, "phase2 retries after matching TS1");
    require(d.eq_req_preset == 6, "phase2 retry keeps requested preset");
    d.eq_done = 1; d.eq_result = 1; tick(d);
    d.eq_done = 0; d.eq_result = 0;
    require(d.phase_done, "phase2 done after adapted request");

    // Coefficient proposals use Symbol7/8/9 fields, in pre/main/post order.
    enter_phase(d, 2);
    d.ts_eq_control = 0x9a;  // Use Preset=1, Transmitter Preset=3, EC=2.
    pulse_ts(d);
    d.eq_done = 1; d.eq_result = 2; d.eq_rsp_preset_sel = 0;
    d.eq_rsp_coeff = (0x12 << 12) | (0x21 << 6) | 0x05;
    tick(d); d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.tx_eq_control == 0x02, "phase2 coefficient proposal EC=10");
    require(d.tx_eq_data == 0x052112, "phase2 coefficient Symbol7-9 packing");
    d.ts_eq_control = 0x02; d.ts_eq_data = 0x052112;
    pulse_ts(d);
    require(d.operation_state == 1, "phase2 coefficient proposal reflected");
    d.eq_done = 1; d.eq_result = 1; tick(d);
    d.eq_done = 0; d.eq_result = 0;
    require(d.phase_done, "phase2 coefficient adaptation done");

    enter_phase(d, 3);
    require(d.operation_state == 3, "phase3 TX preset");
    d.eq_done = 1; d.eq_result = 1; tick(d);
    d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.operation_state == 4, "phase3 TX query");
    d.eq_done = 1; d.eq_result = 1; d.eq_rsp_coeff = 0x12345; tick(d);
    d.eq_done = 0; d.eq_result = 0;
    require(d.phase_done, "phase3 done");
    std::cout << "K15_EQ_PHASES_DIRECTED_PASS\n";

    d.phase_valid = 0;
    d.rst_n = 0; d.idle_enable = 0; d.training_enable = 0; tick(d); tick(d);
    d.rst_n = 1; d.training_enable = 1; d.eval();
    for (int i = 0; i < 4; ++i) {
        require(d.training_valid, "training prefix valid");
        require(d.training_data == 0xff00ff00, "training starts with EIEOS");
        require(d.training_start_block == (i == 0), "EIEOS block boundary");
        require(d.training_sync_header == (i == 0 ? 0x1 : 0x0),
                "EIEOS sync header follows block boundary");
        tick(d);
    }
    for (int i = 0; i < 4; ++i) {
        require(d.training_valid, "SKP prefix valid");
        require(d.training_data == (i == 3 ? 0xbcbf9de1 : 0xaaaaaaaa),
                "official EIEOS-to-SKP prefix");
        require(d.training_start_block == (i == 0), "SKP block boundary");
        require(d.training_sync_header == (i == 0 ? 0x1 : 0x0),
                "SKP sync header follows block boundary");
        tick(d);
    }
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
    std::cout << "K15_EQ_EIEOS_SKP_TS_PASS\n";
    d.final();
    return 0;
}
