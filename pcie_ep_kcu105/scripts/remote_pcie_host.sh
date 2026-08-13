#!/usr/bin/env bash
set -euo pipefail

# Remote Linux Root Port helper for KCU105 PCIe tests.
# Defaults can be overridden with PCIE_REMOTE_HOST, PCIE_REMOTE_USER,
# PCIE_REMOTE_PORT, PCIE_REMOTE_BDF and the timeout variables below.

remote_host="${PCIE_REMOTE_HOST:-192.168.11.126}"
remote_user="${PCIE_REMOTE_USER:-wx}"
remote_port="${PCIE_REMOTE_PORT:-22}"
remote_bdf="${PCIE_REMOTE_BDF:-01:00.0}"
ssh_connect_timeout="${PCIE_SSH_CONNECT_TIMEOUT:-5}"
reboot_timeout="${PCIE_SSH_REBOOT_TIMEOUT:-180}"
poll_interval="${PCIE_SSH_POLL_INTERVAL:-2}"

usage() {
    cat <<'EOF'
用法：remote_pcie_host.sh [选项] <check|reboot|wait|lspci|cycle>

动作：
  check   检查 SSH、主机名和 PCIe 设备
  reboot  通过 sudo -n reboot 重启远端主机
  wait    等待远端 SSH 恢复
  lspci   读取 PCIe BDF 的详细状态
  cycle   reboot 后等待 SSH 恢复并读取 lspci

选项：
  --host HOST       远端 IP/主机名
  --user USER       SSH 用户
  --port PORT       SSH 端口，默认 22
  --bdf BDF         PCIe 设备 BDF，默认 01:00.0
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
        --timeout) reboot_timeout="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        check|reboot|wait|lspci|cycle) action="$1"; shift; break ;;
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

target="${remote_user}@${remote_host}"
ssh_cmd=(ssh -p "$remote_port" -o BatchMode=yes -o ConnectTimeout="$ssh_connect_timeout" "$target")

ssh_run() {
    "${ssh_cmd[@]}" "$@"
}

check_ssh() {
    ssh_run 'printf "host="; hostname; printf "user="; id -un; printf "kernel="; uname -r'
}

read_lspci() {
    ssh_run "if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then sudo -n lspci -s '$remote_bdf' -vvv; else lspci -s '$remote_bdf' -vvv; fi"
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
    if ssh_run 'sudo -n reboot'; then
        echo "REMOTE_REBOOT_SENT host=$target"
    else
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
    lspci)
        read_lspci
        ;;
    cycle)
        reboot_remote
        wait_for_ssh 1
        read_lspci
        ;;
esac
