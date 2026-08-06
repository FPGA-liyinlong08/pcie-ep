#include <verilated.h>
#include "Vk05_fc_manager_native_top.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>

static constexpr std::array<unsigned, 3> H_CAP{32, 32, 8};
static constexpr std::array<unsigned, 3> D_CAP{128, 16, 32};

static uint32_t pack_fc(uint8_t type, uint8_t h, uint16_t d) {
    return static_cast<uint32_t>(type)
        | (static_cast<uint32_t>(h >> 2) << 8)
        | (static_cast<uint32_t>(h & 3) << 22)
        | (static_cast<uint32_t>((d >> 8) & 0xf) << 16)
        | (static_cast<uint32_t>(d & 0xff) << 24);
}

static uint8_t raw_type(uint32_t raw) { return raw & 0xf8; }
static uint8_t raw_h(uint32_t raw) {
    return static_cast<uint8_t>(((raw >> 8) & 0x3f) << 2 | ((raw >> 22) & 3));
}
static uint16_t raw_d(uint32_t raw) {
    return static_cast<uint16_t>(((raw >> 16) & 0xf) << 8 | ((raw >> 24) & 0xff));
}

class Sim {
public:
    Vk05_fc_manager_native_top dut;

    void eval_low() {
        dut.clk = 0;
        dut.eval();
    }

    void tick() {
        dut.clk = 0;
        dut.eval();
        dut.clk = 1;
        dut.eval();
    }

    void clear_events() {
        dut.rx_dllp_valid = 0;
        dut.tx_tlp_consume_valid = 0;
        dut.rx_tlp_consume_valid = 0;
        dut.rx_tlp_release_valid = 0;
    }

    void reset() {
        dut.rst_n = 0;
        dut.link_up = 0;
        dut.tx_dllp_ready = 1;
        dut.rx_dllp_crc_good = 1;
        dut.rx_dllp_error = 0;
        dut.rx_dllp_data = 0;
        dut.tx_tlp_check_type = 0;
        dut.tx_tlp_check_data_credits = 0;
        dut.tx_tlp_consume_type = 0;
        dut.tx_tlp_consume_data_credits = 0;
        dut.rx_tlp_consume_type = 0;
        dut.rx_tlp_consume_data_credits = 0;
        dut.rx_tlp_release_type = 0;
        dut.rx_tlp_release_data_credits = 0;
        clear_events();
        for (int k = 0; k < 4; ++k) tick();
        if (dut.fc_state || dut.dll_active || dut.tx_tlp_credit_available)
            throw std::runtime_error("复位状态错误");
        dut.rst_n = 1;
        tick();
    }

    void rx_fc(uint32_t raw) {
        clear_events();
        dut.rx_dllp_data = raw;
        dut.rx_dllp_valid = 1;
        dut.rx_dllp_crc_good = 1;
        dut.rx_dllp_error = 0;
        tick();
        dut.rx_dllp_valid = 0;
    }
};

static uint64_t env_u64(const char* name, uint64_t fallback) {
    const char* value = std::getenv(name);
    return value ? std::strtoull(value, nullptr, 0) : fallback;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const uint64_t seed = env_u64("K05_RANDOM_SEED", 20260806);
    const uint64_t event_count = env_u64("K05_NATIVE_EVENTS", 1000000);
    std::mt19937_64 rng(seed);
    Sim sim;
    sim.reset();

    sim.dut.link_up = 1;
    sim.tick();
    sim.tick();
    if (sim.dut.fc_state != 1 || sim.dut.dll_active)
        throw std::runtime_error("未进入 FC_INIT1");

    std::array<uint8_t, 3> h_limit{200, 180, 160};
    std::array<uint16_t, 3> d_limit{3000, 2500, 2000};
    std::array<uint8_t, 3> h_consumed{0, 0, 0};
    std::array<uint16_t, 3> d_consumed{0, 0, 0};
    const std::array<uint8_t, 3> init1_type{0x40, 0x50, 0x60};
    const std::array<uint8_t, 3> update_type{0x80, 0x90, 0xa0};

    for (unsigned t = 0; t < 3; ++t)
        sim.rx_fc(pack_fc(init1_type[t], h_limit[t], d_limit[t]));
    if (sim.dut.fc_state != 2)
        throw std::runtime_error("未进入 FC_INIT2");
    sim.rx_fc(pack_fc(0xc0, h_limit[0], d_limit[0]));
    if (sim.dut.fc_state != 3 || !sim.dut.dll_active)
        throw std::runtime_error("未进入 FC_ACTIVE");

    std::array<std::deque<unsigned>, 3> packets;
    std::array<unsigned, 3> local_h{0, 0, 0};
    std::array<unsigned, 3> local_d{0, 0, 0};
    std::array<uint8_t, 3> local_h_alloc{32, 32, 8};
    std::array<uint16_t, 3> local_d_alloc{128, 16, 32};
    uint32_t expected_errors = 0;
    uint64_t tx_consumes = 0;
    uint64_t remote_updates = 0;
    uint64_t local_consumes = 0;
    uint64_t local_releases = 0;

    sim.dut.tx_dllp_ready = 0;

    auto compare = [&]() {
        const std::array<unsigned, 3> got_h{
            sim.dut.tx_ph_available, sim.dut.tx_nph_available,
            sim.dut.tx_cplh_available};
        const std::array<unsigned, 3> got_d{
            sim.dut.tx_pd_available, sim.dut.tx_npd_available,
            sim.dut.tx_cpld_available};
        const std::array<unsigned, 3> got_lh{
            sim.dut.rx_ph_occupied, sim.dut.rx_nph_occupied,
            sim.dut.rx_cplh_occupied};
        const std::array<unsigned, 3> got_ld{
            sim.dut.rx_pd_occupied, sim.dut.rx_npd_occupied,
            sim.dut.rx_cpld_occupied};
        for (unsigned t = 0; t < 3; ++t) {
            const unsigned expected_h = static_cast<uint8_t>(h_limit[t] - h_consumed[t]);
            const unsigned expected_d = static_cast<uint16_t>(d_limit[t] - d_consumed[t]) & 0xfff;
            if (got_h[t] != expected_h || got_d[t] != expected_d ||
                    got_lh[t] != local_h[t] || got_ld[t] != local_d[t]) {
                throw std::runtime_error("信用 Scoreboard 不一致 event=" +
                    std::to_string(tx_consumes + remote_updates + local_consumes + local_releases));
            }
        }
        if (sim.dut.fc_protocol_error_count != expected_errors)
            throw std::runtime_error("协议错误计数不一致");
    };

    for (uint64_t event = 0; event < event_count; ++event) {
        sim.clear_events();
        const unsigned action = rng() % 100;
        if (action < 30) {
            // 远端发布新的累计 limit；available 保持在半范围以内并周期性促成回绕。
            const unsigned t = rng() % 3;
            const unsigned h_grant = 1 + rng() % 100;
            const unsigned d_grant = 1 + rng() % 500;
            h_limit[t] = static_cast<uint8_t>(h_consumed[t] + h_grant);
            d_limit[t] = static_cast<uint16_t>(d_consumed[t] + d_grant) & 0xfff;
            sim.dut.rx_dllp_data = pack_fc(update_type[t], h_limit[t], d_limit[t]);
            sim.dut.rx_dllp_valid = 1;
            sim.dut.rx_dllp_crc_good = 1;
            sim.dut.rx_dllp_error = 0;
            ++remote_updates;
        } else if (action < 60) {
            const unsigned t = rng() % 3;
            const unsigned h_avail = static_cast<uint8_t>(h_limit[t] - h_consumed[t]);
            const unsigned d_avail = static_cast<uint16_t>(d_limit[t] - d_consumed[t]) & 0xfff;
            const bool make_invalid = (event % 10007) == 0;
            unsigned data = d_avail ? rng() % (std::min<unsigned>(d_avail, 8) + 1) : 0;
            sim.dut.tx_tlp_check_type = t;
            sim.dut.tx_tlp_check_data_credits = data;
            sim.eval_low();
            const bool available = h_avail != 0 && d_avail >= data;
            if (static_cast<bool>(sim.dut.tx_tlp_credit_available) != available)
                throw std::runtime_error("组合发送许可错误");
            sim.dut.tx_tlp_consume_valid = 1;
            sim.dut.tx_tlp_consume_type = make_invalid ? 3 : t;
            sim.dut.tx_tlp_consume_data_credits = data;
            if (make_invalid || !available) {
                ++expected_errors;
            } else {
                h_consumed[t] = static_cast<uint8_t>(h_consumed[t] + 1);
                d_consumed[t] = static_cast<uint16_t>(d_consumed[t] + data) & 0xfff;
                ++tx_consumes;
            }
        } else {
            unsigned consume_t = rng() % 3;
            unsigned release_t = rng() % 3;
            bool do_consume = action < 85;
            bool do_release = action >= 75;

            unsigned consume_d = 0;
            if (do_consume) {
                if (local_h[consume_t] >= H_CAP[consume_t]) {
                    do_consume = false;
                } else {
                    const unsigned room = D_CAP[consume_t] - local_d[consume_t];
                    consume_d = rng() % (std::min<unsigned>(room, 4) + 1);
                }
            }
            if (do_release && packets[release_t].empty())
                do_release = false;

            // 相同类型同拍时，先释放一个旧Packet，再加入新Packet。
            unsigned release_d = 0;
            if (do_release) {
                release_d = packets[release_t].front();
                packets[release_t].pop_front();
                --local_h[release_t];
                local_d[release_t] -= release_d;
                local_h_alloc[release_t] = static_cast<uint8_t>(local_h_alloc[release_t] + 1);
                local_d_alloc[release_t] = static_cast<uint16_t>(local_d_alloc[release_t] + release_d) & 0xfff;
                sim.dut.rx_tlp_release_valid = 1;
                sim.dut.rx_tlp_release_type = release_t;
                sim.dut.rx_tlp_release_data_credits = release_d;
                ++local_releases;
            }
            if (do_consume) {
                packets[consume_t].push_back(consume_d);
                ++local_h[consume_t];
                local_d[consume_t] += consume_d;
                sim.dut.rx_tlp_consume_valid = 1;
                sim.dut.rx_tlp_consume_type = consume_t;
                sim.dut.rx_tlp_consume_data_credits = consume_d;
                ++local_consumes;
            }
        }

        sim.tick();
        compare();
    }

    // 停止信用事件并放开 TX；最终必须观察到三类最新累计 UpdateFC。
    sim.clear_events();
    sim.dut.tx_dllp_ready = 1;
    std::array<bool, 3> latest_seen{false, false, false};
    for (unsigned cycle = 0; cycle < 1000; ++cycle) {
        sim.eval_low();
        if (sim.dut.tx_dllp_valid) {
            const uint32_t raw = sim.dut.tx_dllp_data;
            for (unsigned t = 0; t < 3; ++t) {
                if (raw_type(raw) == update_type[t] && raw_h(raw) == local_h_alloc[t] &&
                        raw_d(raw) == local_d_alloc[t])
                    latest_seen[t] = true;
            }
        }
        sim.tick();
        if (latest_seen[0] && latest_seen[1] && latest_seen[2])
            break;
    }
    if (!(latest_seen[0] && latest_seen[1] && latest_seen[2]))
        throw std::runtime_error("未观察到三类最新累计 UpdateFC");

    std::cout << "K05_NATIVE_PASS"
              << " events=" << event_count
              << " tx_consumes=" << tx_consumes
              << " remote_updates=" << remote_updates
              << " local_consumes=" << local_consumes
              << " local_releases=" << local_releases
              << " protocol_errors=" << expected_errors
              << " seed=" << seed << std::endl;
    return 0;
}
