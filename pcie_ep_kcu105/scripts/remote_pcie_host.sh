#!/usr/bin/env bash
set -euo pipefail

# Remote Linux Root Port helper for KCU105 PCIe tests.
# Defaults can be overridden with PCIE_REMOTE_HOST, PCIE_REMOTE_USER,
# PCIE_REMOTE_PORT, PCIE_REMOTE_BDF and the timeout variables below.

remote_host="${PCIE_REMOTE_HOST:-192.168.11.126}"
remote_user="${PCIE_REMOTE_USER:-wx}"
remote_port="${PCIE_REMOTE_PORT:-22}"
remote_bdf="${PCIE_REMOTE_BDF:-01:00.0}"
remote_rp_bdf="${PCIE_REMOTE_RP_BDF:-00:01.0}"
ssh_connect_timeout="${PCIE_SSH_CONNECT_TIMEOUT:-5}"
reboot_timeout="${PCIE_SSH_REBOOT_TIMEOUT:-180}"
poll_interval="${PCIE_SSH_POLL_INTERVAL:-2}"

usage() {
    cat <<'EOF'
用法：remote_pcie_host.sh [选项] <check|reboot|wait|wait-reboot|lspci|cycle|retrain-gen3|retrain-gen3-rp-only|retrain-gen3-d4>

动作：
  check   检查 SSH、主机名和 PCIe 设备
  reboot  通过 sudo -n reboot 重启远端主机
  wait    等待远端 SSH 恢复
  wait-reboot  等待 SSH 先断开再恢复（reboot 后使用）
  lspci   读取 PCIe BDF 的详细状态
  cycle   reboot 后等待 SSH 恢复并读取 lspci
  retrain-gen3  retrain-gen3-rp-only 的兼容别名
  retrain-gen3-rp-only  仅由 Root Port 设置 8 GT/s 并发起 Retrain Link
  retrain-gen3-d4  严格复现历史 D4：Endpoint Retrain 后再由 Root Port 请求 Gen3

选项：
  --host HOST       远端 IP/主机名
  --user USER       SSH 用户
  --port PORT       SSH 端口，默认 22
  --bdf BDF         PCIe 设备 BDF，默认 01:00.0
  --rp-bdf BDF      Endpoint 的上游 Root Port BDF，默认 00:01.0
  --timeout SEC     SSH 恢复等待时间，默认 180
  -h, --help        显示帮助

也可以使用环境变量 PCIE_REMOTE_HOST、PCIE_REMOTE_USER、PCIE_REMOTE_BDF 等覆盖默认值。
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) remote_host="$2"; shift 2 ;;
        --user) remote_user="$2"; shift 2 ;;
        --port) remote_port="$2"; shift 2 ;;
        --bdf) remote_bdf="$2"; shift 2 ;;
        --rp-bdf) remote_rp_bdf="$2"; shift 2 ;;
        --timeout) reboot_timeout="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        check|reboot|wait|wait-reboot|lspci|cycle|retrain-gen3|retrain-gen3-rp-only|retrain-gen3-d4) action="$1"; shift; break ;;
        *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "${action:-}" || $# -ne 0 ]]; then
    usage >&2
    exit 2
fi
if [[ ! "$remote_bdf" =~ ^[0-9a-fA-F:.]+$ ]]; then
    echo "错误：非法 PCIe BDF：$remote_bdf" >&2
    exit 2
fi
if [[ ! "$remote_rp_bdf" =~ ^[0-9a-fA-F:.]+$ ]]; then
    echo "错误：非法 Root Port BDF：$remote_rp_bdf" >&2
    exit 2
fi

target="${remote_user}@${remote_host}"
ssh_cmd=(ssh -p "$remote_port" -o BatchMode=yes -o ConnectTimeout="$ssh_connect_timeout" "$target")

ssh_run() {
    "${ssh_cmd[@]}" "$@"
}

check_ssh() {
    ssh_run 'printf "host="; hostname; printf "user="; id -un; printf "kernel="; uname -r'
}

read_lspci() {
    ssh_run "sudo -n lspci -s '$remote_bdf' -vvv 2>/dev/null || lspci -s '$remote_bdf' -vvv"
}

retrain_gen3_rp_only() {
    # PCIe capability offsets: Link Control is +0x10 and Link Control 2 is
    # +0x30.  Normalize and retrain from the Root Port only so this remains a
    # Root-Port-directed experiment; do not set the endpoint Retrain Link bit.
    ssh_run "set -e; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+30.w=0001:000f; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+10.w=0020:0020; \
        stable=0; \
        for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
            speed=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_speed 2>/dev/null || echo unavailable); \
            width=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_width 2>/dev/null || echo unavailable); \
            link=\$(sudo -n lspci -s '$remote_bdf' -vv 2>/dev/null | sed -n '/LnkSta:/,+1p'); \
            if [ \"\$speed\" = '2.5 GT/s PCIe' ] && [ \"\$width\" = '1' ] && \
               printf '%s' \"\$link\" | grep -q 'DLActive+'; then \
                stable=\$((stable + 1)); \
            else \
                stable=0; \
            fi; \
            if [ \"\$stable\" -ge 3 ]; then break; fi; \
            sleep 0.2; \
        done; \
        if [ \"\$stable\" -lt 3 ]; then \
            echo 'REMOTE_GEN1_NORMALIZE_FAIL' >&2; exit 1; \
        fi; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+30.w=0003:000f; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+10.w=0020:0020; \
        root_port_lnkctl=\$(sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+10.w); \
        root_port_lnkctl2=\$(sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+30.w); \
        printf 'ROOT_PORT_LNKCTL=%s\\n' \"\$root_port_lnkctl\"; \
        printf 'ROOT_PORT_LNKCTL2=%s\\n' \"\$root_port_lnkctl2\"; \
        root_port_lnkctl2_dec=\$(printf '%d' \"0x\$root_port_lnkctl2\"); \
        if [ \$((root_port_lnkctl2_dec & 15)) -ne 3 ]; then \
            printf 'ROOT_PORT_GEN3_REQUEST_READBACK_FAIL value=%s\\n' \"\$root_port_lnkctl2\" >&2; exit 1; \
        fi; \
        printf 'ROOT_PORT_GEN3_REQUEST_READBACK_PASS value=%s\\n' \"\$root_port_lnkctl2\"; \
        for n in 1 2 3 4 5 6 7 8 9 10; do \
            speed=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_speed 2>/dev/null || echo unavailable); \
            width=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_width 2>/dev/null || echo unavailable); \
            printf 'REMOTE_RETRAIN_POLL=%s speed=%s width=%s\\n' \"\$n\" \"\$speed\" \"\$width\"; \
            sleep 0.2; \
        done; \
        sudo -n lspci -s '$remote_rp_bdf' -vv; \
        sudo -n lspci -s '$remote_bdf' -vv | sed -n '/LnkCtl2:/,/LnkSta2:/p'"
}

retrain_gen3_d4() {
    # Strict historical D4 order:
    #   Gen1 normalize -> 3 stable samples -> Endpoint Retrain bit ->
    #   Root Port Target Link Speed=Gen3 + Retrain.
    # K08 reset/default Target Link Speed is already Gen3; the historical
    # sequence intentionally does not write Endpoint Link Control 2 here.
    # The endpoint write is intentional here; this is an A/B test and must not
    # be silently replaced by the newer Root-Port-only procedure.
    ssh_run "set -e; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+30.w=0001:000f; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+10.w=0020:0020; \
        stable=0; \
        for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
            speed=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_speed 2>/dev/null || echo unavailable); \
            width=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_width 2>/dev/null || echo unavailable); \
            link=\$(sudo -n lspci -s '$remote_bdf' -vv 2>/dev/null | sed -n '/LnkSta:/,+1p'); \
            if [ \"\$speed\" = '2.5 GT/s PCIe' ] && [ \"\$width\" = '1' ] && \
               printf '%s' \"\$link\" | grep -q 'DLActive+'; then \
                stable=\$((stable + 1)); \
            else \
                stable=0; \
            fi; \
            printf 'D4_GEN1_STABLE_POLL=%s stable=%s speed=%s width=%s\n' \"\$n\" \"\$stable\" \"\$speed\" \"\$width\"; \
            if [ \"\$stable\" -ge 3 ]; then break; fi; \
            sleep 0.2; \
        done; \
        if [ \"\$stable\" -lt 3 ]; then \
            echo 'D4_GEN1_NORMALIZE_FAIL' >&2; exit 1; \
        fi; \
        sudo -n setpci -s '$remote_bdf' CAP_EXP+10.w=0020:0020; \
        printf 'D4_ENDPOINT_RETRAIN_WRITE_PASS bdf=%s\n' '$remote_bdf'; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+30.w=0003:000f; \
        sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+10.w=0020:0020; \
        root_port_lnkctl=\$(sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+10.w); \
        root_port_lnkctl2=\$(sudo -n setpci -s '$remote_rp_bdf' CAP_EXP+30.w); \
        printf 'D4_ROOT_PORT_LNKCTL=%s\n' \"\$root_port_lnkctl\"; \
        printf 'D4_ROOT_PORT_LNKCTL2=%s\n' \"\$root_port_lnkctl2\"; \
        root_port_lnkctl2_dec=\$(printf '%d' \"0x\$root_port_lnkctl2\"); \
        if [ \$((root_port_lnkctl2_dec & 15)) -ne 3 ]; then \
            echo 'D4_ROOT_PORT_GEN3_REQUEST_READBACK_FAIL' >&2; exit 1; \
        fi; \
        printf 'D4_ROOT_PORT_GEN3_REQUEST_READBACK_PASS value=%s\n' \"\$root_port_lnkctl2\"; \
        for n in 1 2 3 4 5 6 7 8 9 10; do \
            speed=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_speed 2>/dev/null || echo unavailable); \
            width=\$(cat /sys/bus/pci/devices/0000:$remote_bdf/current_link_width 2>/dev/null || echo unavailable); \
            printf 'D4_RETRAIN_POLL=%s speed=%s width=%s\n' \"\$n\" \"\$speed\" \"\$width\"; \
            sleep 0.2; \
        done; \
        sudo -n lspci -s '$remote_rp_bdf' -vv; \
        sudo -n lspci -s '$remote_bdf' -vv | sed -n '/LnkCtl2:/,/LnkSta2:/p'"
}

wait_for_ssh() {
    local require_down="${1:-0}"
    local saw_down=0
    local deadline
    deadline=$((SECONDS + reboot_timeout))
    while (( SECONDS < deadline )); do
        if ssh_run 'true' >/dev/null 2>&1; then
            if [[ "$require_down" == "0" || "$saw_down" == "1" ]]; then
                echo "REMOTE_SSH_READY host=$target elapsed=$SECONDS"
                return 0
            fi
        else
            saw_down=1
        fi
        sleep "$poll_interval"
    done
    echo "错误：等待 SSH 恢复超时（${reboot_timeout}s）：$target" >&2
    return 1
}

reboot_remote() {
    local reboot_output reboot_status
    set +e
    reboot_output="$(ssh_run 'sudo -n reboot' 2>&1)"
    reboot_status=$?
    set -e

    # reboot通常会在远端接受命令后主动关闭SSH，ssh因此返回非零。
    # 仅在明确看到连接因远端关闭而断开时视为已发送，不能吞掉
    # sudo密码不足、认证失败或其他真正的执行错误。
    if [[ "$reboot_status" -eq 0 ]] ||
       grep -Eq 'closed by remote host|Connection to .* closed' <<<"$reboot_output"; then
        echo "REMOTE_REBOOT_SENT host=$target"
    else
        if [[ -n "$reboot_output" ]]; then
            printf '%s\n' "$reboot_output" >&2
        fi
        cat >&2 <<EOF
远端 sudo reboot 失败。当前脚本不会交互式保存或传递密码。
请人工执行：ssh $target 'sudo reboot'
或者为该用户配置受限的 NOPASSWD reboot 权限后重试。
EOF
        return 1
    fi
}

case "$action" in
    check)
        check_ssh
        read_lspci
        ;;
    reboot)
        reboot_remote
        ;;
    wait)
        wait_for_ssh
        ;;
    wait-reboot)
        wait_for_ssh 1
        ;;
    lspci)
        read_lspci
        ;;
    cycle)
        reboot_remote
        wait_for_ssh 1
        read_lspci
        ;;
    retrain-gen3|retrain-gen3-rp-only)
        retrain_gen3_rp_only
        ;;
    retrain-gen3-d4)
        retrain_gen3_d4
        ;;
esac
