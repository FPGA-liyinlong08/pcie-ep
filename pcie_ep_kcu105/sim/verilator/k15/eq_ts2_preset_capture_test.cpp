#include "Vpcie_eq_ts2_preset_capture.h"
#include "verilated.h"

#include <cstdio>

static void tick(Vpcie_eq_ts2_preset_capture &dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

static bool expect(bool condition, const char *message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        return false;
    }
    return true;
}

static void candidate(Vpcie_eq_ts2_preset_capture &dut, unsigned preset,
                      unsigned tuple_tag = 0) {
    dut.candidate_valid = 1;
    dut.sequence_break = 0;
    dut.preset_candidate = preset & 0xfu;
    const unsigned symbol6 = 0x80u | ((preset & 0xfu) << 3);
    dut.signature = (static_cast<unsigned long long>(tuple_tag) << 40) |
                    symbol6;
    tick(dut);
    dut.candidate_valid = 0;
}

static void break_sequence(Vpcie_eq_ts2_preset_capture &dut,
                           unsigned symbol6) {
    dut.candidate_valid = 0;
    dut.sequence_break = 1;
    dut.preset_candidate = (symbol6 >> 3) & 0xfu;
    dut.signature = symbol6;
    tick(dut);
    dut.sequence_break = 0;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vpcie_eq_ts2_preset_capture dut;
    dut.rst_n = 0;
    dut.clear = 0;
    dut.candidate_valid = 0;
    dut.sequence_break = 0;
    dut.preset_candidate = 0;
    dut.signature = 0;
    tick(dut);
    dut.rst_n = 1;
    tick(dut);

    bool ok = true;
    for (int i = 0; i < 7; ++i)
        candidate(dut, 4);
    ok &= expect(!dut.preset_valid, "seven EQ TS2s must not qualify");
    ok &= expect(dut.consecutive_count == 7,
                 "seven EQ TS2s must leave count at seven");
    candidate(dut, 4);
    ok &= expect(dut.preset_valid && dut.preset == 4,
                 "eighth identical EQ TS2 must qualify P4");

    // A reserved/malformed tuple is presented by the LTSSM as a break.  It
    // invalidates the old qualification so the command layer uses fallback.
    break_sequence(dut, 0x80u | (11u << 3));
    ok &= expect(!dut.preset_valid && dut.consecutive_count == 0,
                 "reserved preset must invalidate the qualified sequence");

    for (int i = 0; i < 4; ++i)
        candidate(dut, 7);
    candidate(dut, 7, 1);
    ok &= expect(!dut.preset_valid && dut.consecutive_count == 1,
                 "non-Symbol6 tuple change must restart the count");
    for (int i = 0; i < 3; ++i)
        candidate(dut, 7, 1);
    candidate(dut, 10);
    ok &= expect(!dut.preset_valid && dut.consecutive_count == 1,
                 "tuple change must restart the consecutive count");
    for (int i = 0; i < 7; ++i)
        candidate(dut, 10);
    ok &= expect(dut.preset_valid && dut.preset == 10,
                 "latest eight-identical sequence must replace with P10");

    dut.clear = 1;
    tick(dut);
    dut.clear = 0;
    ok &= expect(!dut.preset_valid && dut.preset == 4,
                 "clear must restore invalid P4 fallback state");

    if (!ok)
        return 1;
    std::puts("K15_EQ_TS2_PRESET_CAPTURE_PASS");
    return 0;
}
