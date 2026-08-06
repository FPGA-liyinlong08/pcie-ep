#include <verilated.h>
#include "Vk04_crc_test_top.h"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

struct Beat {
    uint32_t data;
    uint8_t keep;
};

static uint16_t crc16_raw(const std::vector<uint8_t>& bytes) {
    uint16_t crc = 0xffff;
    for (uint8_t byte : bytes) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc & 1) ? static_cast<uint16_t>((crc >> 1) ^ 0xd008) :
                              static_cast<uint16_t>(crc >> 1);
    }
    return crc;
}

static uint32_t crc32_raw(const std::vector<uint8_t>& bytes) {
    uint32_t crc = 0xffffffffu;
    for (uint8_t byte : bytes) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc & 1) ? (crc >> 1) ^ 0xedb88320u : crc >> 1;
    }
    return crc;
}

static std::vector<Beat> make_beats(const std::vector<uint8_t>& bytes) {
    std::vector<Beat> beats;
    for (std::size_t offset = 0; offset < bytes.size(); offset += 4) {
        Beat beat{0, 0};
        for (unsigned lane = 0; lane < 4 && offset + lane < bytes.size(); ++lane) {
            beat.data |= static_cast<uint32_t>(bytes[offset + lane]) << (lane * 8);
            beat.keep |= static_cast<uint8_t>(1u << lane);
        }
        beats.push_back(beat);
    }
    return beats;
}

class Simulation {
public:
    Vk04_crc_test_top dut;
    uint64_t total_bytes = 0;

    void tick() {
        dut.clk = 0;
        dut.eval();
        dut.clk = 1;
        dut.eval();
    }

    void reset() {
        dut.rst_n = 0;
        dut.valid = 0;
        dut.start = 0;
        dut.last = 0;
        dut.keep = 0;
        for (int cycle = 0; cycle < 4; ++cycle)
            tick();
        if (dut.ready16 || dut.ready32 || dut.busy16 || dut.busy32)
            throw std::runtime_error("复位安全值错误");
        dut.rst_n = 1;
        tick();
        if (!dut.ready16 || !dut.ready32)
            throw std::runtime_error("复位释放后 ready 未置位");
    }

    void send(const std::vector<Beat>& beats, const std::vector<uint8_t>& bytes,
              bool expect_match16 = false, bool expect_match32 = false,
              bool require_no_match16 = false, bool require_no_match32 = false) {
        if (beats.empty() || bytes.empty())
            throw std::runtime_error("禁止空向量");

        for (std::size_t index = 0; index < beats.size(); ++index) {
            dut.start = index == 0;
            dut.data = beats[index].data;
            dut.keep = beats[index].keep;
            dut.last = index + 1 == beats.size();
            dut.valid = 1;
            if (!dut.ready16 || !dut.ready32)
                throw std::runtime_error("DUT 非预期反压");
            tick();
        }
        dut.valid = 0;
        dut.start = 0;
        dut.last = 0;
        dut.keep = 0;

        const uint16_t expected16 = static_cast<uint16_t>(~crc16_raw(bytes));
        const uint32_t expected32 = ~crc32_raw(bytes);
        if (!dut.crc_valid16 || !dut.crc_valid32)
            throw std::runtime_error("末拍后缺少 crc_valid");
        if (dut.crc_result16 != expected16 || dut.crc_result32 != expected32) {
            throw std::runtime_error(
                "CRC mismatch bytes=" + std::to_string(bytes.size()) +
                " got16=" + std::to_string(dut.crc_result16) +
                " expected16=" + std::to_string(expected16) +
                " got32=" + std::to_string(dut.crc_result32) +
                " expected32=" + std::to_string(expected32));
        }
        if (expect_match16 && !dut.crc_match16)
            throw std::runtime_error("CRC16 正确 residue 未 match");
        if (expect_match32 && !dut.crc_match32)
            throw std::runtime_error("CRC32 正确 residue 未 match");
        if (require_no_match16 && dut.crc_match16)
            throw std::runtime_error("CRC16 单 bit 错误未检出");
        if (require_no_match32 && dut.crc_match32)
            throw std::runtime_error("CRC32 单 bit 错误未检出");
        if (dut.protocol_error16 || dut.protocol_error32)
            throw std::runtime_error("合法向量产生 protocol_error");

        total_bytes += bytes.size();
    }
};

static uint64_t env_u64(const char* name, uint64_t fallback) {
    const char* value = std::getenv(name);
    return value ? std::strtoull(value, nullptr, 0) : fallback;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const uint64_t seed = env_u64("K04_RANDOM_SEED", 20260806);
    const uint64_t base_packets = env_u64("K04_NATIVE_BASE_PACKETS", 500000);
    std::mt19937_64 rng(seed);
    Simulation sim;
    sim.reset();

    const std::vector<std::size_t> boundary_lengths = {
        1, 2, 3, 4, 15, 16, 17, 127, 128, 129, 255, 256,
        511, 512, 1024, 2048, 4096
    };
    uint64_t residue_vectors = 0;
    uint64_t error_vectors = 0;

    for (uint64_t packet = 0; packet < base_packets; ++packet) {
        std::size_t length = 1 + (rng() % 64);
        if (packet < boundary_lengths.size() || packet % 4093 == 0)
            length = boundary_lengths[packet % boundary_lengths.size()];

        std::vector<uint8_t> bytes(length);
        for (uint8_t& byte : bytes)
            byte = static_cast<uint8_t>(rng());

        // 周期性使用全部 15 种末拍 keep，包括稀疏 mask。
        std::vector<Beat> beats;
        std::vector<uint8_t> protected_bytes;
        if (packet % 31 == 0) {
            const uint8_t final_keep = static_cast<uint8_t>(1 + (packet % 15));
            const std::size_t prefix_bytes = (length / 4) * 4;
            protected_bytes.assign(bytes.begin(), bytes.begin() + prefix_bytes);
            beats = make_beats(protected_bytes);
            Beat last_beat{0, final_keep};
            for (unsigned lane = 0; lane < 4; ++lane) {
                const uint8_t value = static_cast<uint8_t>(rng());
                last_beat.data |= static_cast<uint32_t>(value) << (lane * 8);
                if (final_keep & (1u << lane))
                    protected_bytes.push_back(value);
            }
            beats.push_back(last_beat);
        } else {
            protected_bytes = bytes;
            beats = make_beats(protected_bytes);
        }
        sim.send(beats, protected_bytes);

        // 每五个基础 Packet 增加一个 residue 向量和对应单 bit 错误向量。
        if (packet % 5 == 0) {
            std::vector<uint8_t> with_crc = bytes;
            const bool use_crc16 = ((packet / 5) & 1) == 0;
            if (use_crc16) {
                const uint16_t crc = static_cast<uint16_t>(~crc16_raw(bytes));
                with_crc.push_back(static_cast<uint8_t>(crc));
                with_crc.push_back(static_cast<uint8_t>(crc >> 8));
                sim.send(make_beats(with_crc), with_crc, true, false);
            } else {
                const uint32_t crc = ~crc32_raw(bytes);
                for (unsigned byte = 0; byte < 4; ++byte)
                    with_crc.push_back(static_cast<uint8_t>(crc >> (byte * 8)));
                sim.send(make_beats(with_crc), with_crc, false, true);
            }
            ++residue_vectors;

            const std::size_t bit_position = rng() % (with_crc.size() * 8);
            with_crc[bit_position / 8] ^= static_cast<uint8_t>(1u << (bit_position % 8));
            if (use_crc16)
                sim.send(make_beats(with_crc), with_crc, false, false, true, false);
            else
                sim.send(make_beats(with_crc), with_crc, false, false, false, true);
            ++error_vectors;
        }
    }

    const uint64_t algorithm_vectors = base_packets * 2;
    std::cout << "K04_NATIVE_PASS"
              << " algorithm_vectors=" << algorithm_vectors
              << " residue_vectors=" << residue_vectors
              << " single_bit_error_vectors=" << error_vectors
              << " total_bytes=" << sim.total_bytes
              << " seed=" << seed << std::endl;
    return 0;
}
