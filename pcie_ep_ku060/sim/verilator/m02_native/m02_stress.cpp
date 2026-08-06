#include <array>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "Vpcie_async_pkt_fifo.h"
#include "verilated.h"

struct Beat {
    std::array<uint32_t, 4> data{};
    uint16_t keep = 0;
    uint8_t sop = 0;
    uint8_t eop = 0;
    uint8_t error = 0;
};

class XorShift64 {
public:
    explicit XorShift64(uint64_t seed) : state_(seed ? seed : 1) {}

    uint64_t next() {
        uint64_t value = state_;
        value ^= value << 13;
        value ^= value >> 7;
        value ^= value << 17;
        state_ = value;
        return value;
    }

    uint32_t range(uint32_t limit) {
        return static_cast<uint32_t>(next() % limit);
    }

private:
    uint64_t state_;
};

struct Options {
    uint64_t packets = 1000000;
    uint64_t seed = 20260806;
    uint64_t s_period_ticks = 80;
    uint64_t m_period_ticks = 20;
    uint64_t m_phase_ticks = 0;
    std::string name = "unnamed";
};

uint64_t parse_u64(const char* text) {
    return std::stoull(text);
}

Options parse_options(int argc, char** argv) {
    Options options;
    for (int index = 1; index < argc; ++index) {
        const std::string arg = argv[index];
        if (index + 1 >= argc)
            throw std::runtime_error("参数缺少值: " + arg);
        const std::string value = argv[++index];
        if (arg == "--packets") options.packets = parse_u64(value.c_str());
        else if (arg == "--seed") options.seed = parse_u64(value.c_str());
        else if (arg == "--s-period") options.s_period_ticks = parse_u64(value.c_str());
        else if (arg == "--m-period") options.m_period_ticks = parse_u64(value.c_str());
        else if (arg == "--m-phase") options.m_phase_ticks = parse_u64(value.c_str());
        else if (arg == "--name") options.name = value;
        else throw std::runtime_error("未知参数: " + arg);
    }
    if ((options.s_period_ticks < 2) || (options.m_period_ticks < 2)
            || (options.s_period_ticks & 1) || (options.m_period_ticks & 1))
        throw std::runtime_error("时钟周期必须是大于等于 2 的偶数 Tick");
    return options;
}

uint32_t packet_length(uint64_t packet_index, XorShift64& rng) {
    static constexpr std::array<uint32_t, 8> boundaries = {1, 2, 3, 31, 32, 257, 511, 512};
    if ((packet_index % 100003) < boundaries.size())
        return boundaries[packet_index % boundaries.size()];
    const uint32_t selector = rng.range(1000);
    if (selector < 930)
        return 1 + rng.range(8);
    return 9 + rng.range(56);
}

Beat make_beat(uint64_t packet_index, uint32_t beat_index, uint32_t length, XorShift64& rng) {
    Beat beat;
    for (auto& word : beat.data)
        word = static_cast<uint32_t>(rng.next());
    beat.sop = (beat_index == 0);
    beat.eop = (beat_index + 1 == length);
    const uint32_t valid_bytes = beat.eop ? (1 + rng.range(16)) : 16;
    beat.keep = valid_bytes == 16 ? 0xffffu : static_cast<uint16_t>((1u << valid_bytes) - 1u);
    beat.error = static_cast<uint8_t>((packet_index + beat_index + rng.range(16)) & 0xfu);
    return beat;
}

void drive_source(Vpcie_async_pkt_fifo* dut, const Beat& beat, bool valid) {
    dut->s_valid = valid;
    for (int word = 0; word < 4; ++word)
        dut->s_data[word] = beat.data[word];
    dut->s_keep = beat.keep;
    dut->s_sop = beat.sop;
    dut->s_eop = beat.eop;
    dut->s_error = beat.error;
}

Beat sample_sink(const Vpcie_async_pkt_fifo* dut) {
    Beat beat;
    for (int word = 0; word < 4; ++word)
        beat.data[word] = dut->m_data[word];
    beat.keep = dut->m_keep;
    beat.sop = dut->m_sop;
    beat.eop = dut->m_eop;
    beat.error = dut->m_error;
    return beat;
}

bool equal_beat(const Beat& lhs, const Beat& rhs) {
    return lhs.data == rhs.data && lhs.keep == rhs.keep && lhs.sop == rhs.sop
        && lhs.eop == rhs.eop && lhs.error == rhs.error;
}

int main(int argc, char** argv) {
    try {
        const Options options = parse_options(argc, argv);
        VerilatedContext context;
        context.commandArgs(argc, argv);
        Vpcie_async_pkt_fifo dut(&context);
        XorShift64 source_rng(options.seed ^ 0x5a5aa5a55a5aa5a5ULL);
        XorShift64 sink_rng(options.seed ^ 0xc3c33c3cc3c33c3cULL);

        dut.s_clk = 0;
        dut.m_clk = 0;
        dut.s_rst_n = 0;
        dut.m_rst_n = 0;
        dut.flush = 0;
        dut.m_ready = 0;
        Beat idle_beat;
        drive_source(&dut, idle_beat, false);
        dut.eval();

        const uint64_t s_half = options.s_period_ticks / 2;
        const uint64_t m_half = options.m_period_ticks / 2;
        uint64_t next_s_edge = s_half;
        uint64_t next_m_edge = options.m_phase_ticks + m_half;
        uint64_t now = 0;
        const uint64_t reset_release_time = options.m_phase_ticks
            + 10 * std::max(options.s_period_ticks, options.m_period_ticks);
        const uint64_t traffic_start_time = reset_release_time
            + 8 * std::max(options.s_period_ticks, options.m_period_ticks);
        bool reset_released = false;

        uint64_t generated_packets = 0;
        uint64_t committed_packets = 0;
        uint64_t received_packets = 0;
        uint32_t current_length = 0;
        uint32_t current_beat_index = 0;
        bool source_pending = false;
        Beat source_beat;
        std::vector<Beat> uncommitted;
        uncommitted.reserve(512);
        std::deque<Beat> expected;

        uint64_t edge_events = 0;
        const uint64_t max_edge_events = options.packets * 400 + 1000000;

        while (received_packets < options.packets) {
            now = std::min(next_s_edge, next_m_edge);
            context.time(now);

            if (!reset_released && now >= reset_release_time) {
                dut.s_rst_n = 1;
                dut.m_rst_n = 1;
                reset_released = true;
                dut.eval();
            }

            const bool s_event = next_s_edge == now;
            const bool m_event = next_m_edge == now;
            const bool s_rising = s_event && !dut.s_clk;
            const bool m_rising = m_event && !dut.m_clk;

            const bool source_handshake = s_rising && dut.s_valid && dut.s_ready;
            const bool sink_visible = m_rising && dut.m_valid;
            const bool sink_handshake = sink_visible && dut.m_ready;
            Beat sink_beat;
            if (sink_visible)
                sink_beat = sample_sink(&dut);

            if (s_event) {
                dut.s_clk = !dut.s_clk;
                next_s_edge += s_half;
            }
            if (m_event) {
                dut.m_clk = !dut.m_clk;
                next_m_edge += m_half;
            }
            dut.eval();

            if (source_handshake) {
                uncommitted.push_back(source_beat);
                source_pending = false;
                ++current_beat_index;
                if (source_beat.eop) {
                    for (const auto& beat : uncommitted)
                        expected.push_back(beat);
                    uncommitted.clear();
                    ++committed_packets;
                    ++generated_packets;
                    current_length = 0;
                    current_beat_index = 0;
                }
            }

            if (sink_visible && expected.empty())
                throw std::runtime_error("EOP Commit 前读侧出现 m_valid");
            if (sink_handshake) {
                const Beat expected_beat = expected.front();
                expected.pop_front();
                if (!equal_beat(sink_beat, expected_beat))
                    throw std::runtime_error("数据 Scoreboard 不一致，Packet="
                        + std::to_string(received_packets));
                if (sink_beat.eop)
                    ++received_packets;
            }

            if (reset_released && now >= traffic_start_time) {
                if (s_event && !dut.s_clk && !source_pending
                        && generated_packets < options.packets) {
                    if (source_rng.range(100) < 90) {
                        if (current_length == 0)
                            current_length = packet_length(generated_packets, source_rng);
                        source_beat = make_beat(generated_packets, current_beat_index,
                                                current_length, source_rng);
                        source_pending = true;
                        drive_source(&dut, source_beat, true);
                    } else {
                        drive_source(&dut, idle_beat, false);
                    }
                    dut.eval();
                } else if (s_event && !dut.s_clk && source_pending) {
                    drive_source(&dut, source_beat, true);
                    dut.eval();
                } else if (s_event && !dut.s_clk && generated_packets >= options.packets) {
                    drive_source(&dut, idle_beat, false);
                    dut.eval();
                }

                if (m_event && !dut.m_clk) {
                    dut.m_ready = sink_rng.range(100) < 75;
                    dut.eval();
                }
            }

            if (dut.s_packet_count > 512 || dut.m_packet_count > 512)
                throw std::runtime_error("Packet Count 超过 FIFO 深度");
            if (dut.s_overflow)
                throw std::runtime_error("正常压力测试出现 s_overflow");
            if (dut.m_underflow)
                throw std::runtime_error("正常压力测试出现 m_underflow");

            if (++edge_events > max_edge_events)
                throw std::runtime_error("压力测试超时/死锁");
        }

        if ((committed_packets != options.packets) || !expected.empty() || !uncommitted.empty())
            throw std::runtime_error("结束时 Scoreboard 或 Packet 计数未清空");

        dut.final();
        std::cout << "M02_NATIVE_PASS name=" << options.name
                  << " packets=" << options.packets
                  << " committed=" << committed_packets
                  << " received=" << received_packets
                  << " edge_events=" << edge_events
                  << " seed=" << options.seed << std::endl;
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "M02_NATIVE_FAIL " << error.what() << std::endl;
        return EXIT_FAILURE;
    }
}

