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

static void pulse_ts(Vk15_eq_idle_test_top &d) {
    d.ts1_valid = 1; tick(d); d.ts1_valid = 0; tick(d);
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
    d.idle_enable = 0; d.training_enable = 0;
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
    d.ts_eq_control = 1; d.ts_eq_data = 0x8a0c28;

    enter_phase(d, 2);
    require(d.operation_state == 0, "phase2 waits for partner TS");
    pulse_ts(d);
    require(d.operation_state == 1, "phase2 RX adapt request");
    require(d.eq_req_preset == 8, "phase2 preset decodes EQ_DATA[23:20]");
    d.eq_done = 1; d.eq_result = 2; d.eq_rsp_preset_sel = 1;
    d.eq_rsp_coeff = 7; tick(d); d.eq_done = 0; d.eq_result = 0; tick(d);
    require(d.tx_eq_control == 0x22, "phase2 proposal response");
    pulse_ts(d);
    require(d.operation_state == 1, "phase2 retry");
    d.eq_done = 1; d.eq_result = 1; tick(d);
    d.eq_done = 0; d.eq_result = 0;
    require(d.phase_done, "phase2 done");

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
    require(d.training_start_block, "TS starts after initial SKP");
    require(d.training_sync_header == 0x1, "TS ordered-set header");
    require((d.training_data & 0xff) == 0x1e, "TS1 follows initial SKP");
    tick(d); // TS word 1
    tick(d); // TS word 2
    tick(d); // TS word 3 carries the running-DC-balance substitution
    const unsigned ts_tail = d.training_data;
    require(((ts_tail >> 16) == 0x0820) ||
            ((ts_tail >> 16) == 0xf7df) ||
            ((ts_tail >> 24) == 0x08) ||
            ((ts_tail >> 24) == 0xf7),
            "TS tail running-DC-balance substitution");
    tick(d); // complete one TS block so the idle path inherits its LFSR
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
