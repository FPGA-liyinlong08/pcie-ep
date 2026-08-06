#include <verilated.h>
#include "Vk06_dll_replay_native_top.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <vector>

static uint64_t sim_time = 0;
double sc_time_stamp() { return static_cast<double>(sim_time); }

static uint32_t crc32_ref(const std::vector<uint8_t>& bytes) {
    uint32_t crc = 0xffffffffu;
    for (uint8_t byte : bytes) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320u : 0u);
    }
    return ~crc;
}

static void append_dw(std::vector<uint8_t>& bytes, uint32_t value) {
    for (int k = 0; k < 4; ++k)
        bytes.push_back(static_cast<uint8_t>(value >> (8*k)));
}

struct Harness {
    Vk06_dll_replay_native_top dut;
    std::vector<uint8_t> wire;
    bool frame_done = false;

    void cycle() {
        dut.clk = 0;
        dut.eval();
        bool transfer = dut.mac_valid && dut.mac_ready;
        uint16_t data = dut.mac_data;
        uint8_t keep = dut.mac_keep;
        bool sop = dut.mac_sop;
        bool eop = dut.mac_eop;
        dut.clk = 1;
        dut.eval();
        ++sim_time;
        if (transfer) {
            if (sop) {
                if (!wire.empty()) throw std::runtime_error("nested MAC SOP");
            } else if (wire.empty()) {
                throw std::runtime_error("MAC data without SOP");
            }
            if (keep & 1) wire.push_back(data & 0xff);
            if (keep & 2) wire.push_back((data >> 8) & 0xff);
            if (eop) frame_done = true;
        }
    }

    void reset() {
        dut.rst_n = 0;
        dut.dll_active = 0;
        dut.enqueue_valid = 0;
        dut.mac_ready = 1;
        dut.ack_valid = 0;
        dut.ack_is_nak = 0;
        dut.ack_seq = 0;
        for (int k = 0; k < 5; ++k) cycle();
        dut.rst_n = 1;
        dut.dll_active = 1;
        for (int k = 0; k < 4; ++k) cycle();
    }

    void enqueue(uint32_t dw0, uint32_t dw1, uint32_t dw2) {
        dut.packet_dw0 = dw0;
        dut.packet_dw1 = dw1;
        dut.packet_dw2 = dw2;
        dut.enqueue_valid = 1;
        do { cycle(); } while (!dut.enqueue_ready);
        dut.enqueue_valid = 0;
    }

    std::vector<uint8_t> collect_frame(uint64_t timeout=512) {
        wire.clear();
        frame_done = false;
        while (!frame_done && timeout--) cycle();
        if (!frame_done) throw std::runtime_error("MAC frame timeout");
        auto result = wire;
        wire.clear();
        frame_done = false;
        return result;
    }

    void ack(uint16_t seq, bool nak=false) {
        dut.ack_seq = seq & 0xfff;
        dut.ack_is_nak = nak;
        dut.ack_valid = 1;
        cycle();
        dut.ack_valid = 0;
        cycle();
    }
};

static void check_frame(const std::vector<uint8_t>& wire, uint16_t seq,
                        uint32_t dw0, uint32_t dw1, uint32_t dw2) {
    if (wire.size() != 18) throw std::runtime_error("wire length mismatch");
    std::vector<uint8_t> protected_bytes;
    protected_bytes.push_back((seq >> 8) & 0x0f);
    protected_bytes.push_back(seq & 0xff);
    append_dw(protected_bytes, dw0);
    append_dw(protected_bytes, dw1);
    append_dw(protected_bytes, dw2);
    uint32_t crc = crc32_ref(protected_bytes);
    append_dw(protected_bytes, crc);
    if (wire != protected_bytes) {
        std::ostringstream ss;
        ss << "wire mismatch seq=0x" << std::hex << seq;
        throw std::runtime_error(ss.str());
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    uint64_t events = 1048576;
    if (const char* value = std::getenv("K06_NATIVE_EVENTS"))
        events = std::strtoull(value, nullptr, 0);
    if (events < 4096) {
        std::cerr << "K06_NATIVE_EVENTS must be >=4096\n";
        return 2;
    }

    try {
        Harness h;
        h.reset();
        uint64_t nak_replays = 0;
        for (uint64_t index = 0; index < events; ++index) {
            uint16_t seq = index & 0xfff;
            uint32_t dw0 = 0x01000000u;
            uint32_t dw1 = static_cast<uint32_t>(index);
            uint32_t dw2 = static_cast<uint32_t>((index * 0x9e3779b1u) ^ 0xa5a55a5au);
            h.enqueue(dw0, dw1, dw2);
            auto first = h.collect_frame();
            check_frame(first, seq, dw0, dw1, dw2);

            if ((index % 4093) == 17) {
                h.ack((seq - 1) & 0xfff, true);
                auto replay = h.collect_frame();
                if (replay != first) throw std::runtime_error("NAK replay differs");
                ++nak_replays;
            }

            h.ack(seq, false);
            unsigned wait = 32;
            while (h.dut.replay_occupancy && wait--) h.cycle();
            if (h.dut.replay_occupancy)
                throw std::runtime_error("ACK did not release replay entry");
            if (h.dut.next_tx_seq != ((index + 1) & 0xfff))
                throw std::runtime_error("next_tx_seq mismatch");
            if (h.dut.last_acked_seq != seq)
                throw std::runtime_error("last_acked_seq mismatch");
        }

        if (h.dut.tx_tlp_count != static_cast<uint32_t>(events))
            throw std::runtime_error("tx_tlp_count mismatch");
        if (h.dut.replay_count != static_cast<uint32_t>(nak_replays))
            throw std::runtime_error("replay_count mismatch");
        if (h.dut.ack_error_count || h.dut.buffer_error_count)
            throw std::runtime_error("unexpected error counter");

        std::cout << "K06_NATIVE_PASS events=" << events
                  << " nak_replays=" << nak_replays
                  << " sequence_wraps=" << (events / 4096)
                  << " final_seq=" << h.dut.next_tx_seq << "\n";
    } catch (const std::exception& e) {
        std::cerr << "K06_NATIVE_FAIL " << e.what() << "\n";
        return 1;
    }
    return 0;
}
