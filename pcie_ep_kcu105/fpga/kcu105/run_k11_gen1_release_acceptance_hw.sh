#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
remote_host="${PCIE_REMOTE_HOST:-192.168.11.126}"
remote_user="${PCIE_REMOTE_USER:-wx}"
remote_port="${PCIE_REMOTE_PORT:-22}"
cycles="${1:-3}"
mmio_per_cycle="${2:-5}"

if [[ ! "${cycles}" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "${mmio_per_cycle}" =~ ^[1-9][0-9]*$ ]]; then
    echo "错误：cycles和mmio_per_cycle必须为正整数" >&2
    exit 2
fi

ssh_cmd=(ssh -p "${remote_port}" -o BatchMode=yes -o ConnectTimeout=5
         "${remote_user}@${remote_host}")

cd "${project_dir}"
for ((cycle = 1; cycle <= cycles; cycle++)); do
    echo "K11_GEN1_ACCEPTANCE_CYCLE_BEGIN cycle=${cycle}"
    ./scripts/remote_pcie_host.sh cycle

    "${ssh_cmd[@]}" "ROUND=${cycle} MMIO_COUNT=${mmio_per_cycle} bash -s" <<'REMOTE'
set -euo pipefail

dev=/sys/bus/pci/devices/0000:01:00.0
error_pattern='PCIe Bus Error|BadTLP|BadDLLP|Rollover|Replay Timer Timeout'

test -e "${dev}/vendor"
test "$(cat "${dev}/vendor")" = 0x1234
test "$(cat "${dev}/device")" = 0xe001
test "$(cat "${dev}/current_link_speed")" = '2.5 GT/s PCIe'
test "$(cat "${dev}/current_link_width")" = 1
test "$(stat -c %s "${dev}/resource0")" = 4096
sudo -n lspci -s 01:00.0 -vv | sed -n '/LnkSta:/,+1p' | grep -q 'DLActive+'

aer_before=$(sudo -n journalctl -k -b --no-pager 2>/dev/null |
             grep -Ec "${error_pattern}" || true)
sudo -n setpci -s 01:00.0 COMMAND=0006
test "$(sudo -n setpci -s 01:00.0 COMMAND)" = 0006

printf 'K11_GEN1_ACCEPTANCE_LINK cycle=%s device=1234:e001 speed=%s width=%s bar0_bytes=%s command=%s aer_before=%s\n' \
    "${ROUND}" "$(cat "${dev}/current_link_speed")" \
    "$(cat "${dev}/current_link_width")" \
    "$(stat -c %s "${dev}/resource0")" \
    "$(sudo -n setpci -s 01:00.0 COMMAND)" "${aer_before}"

for ((test_index = 1; test_index <= MMIO_COUNT; test_index++)); do
    set +e
    output=$(sudo -n /usr/local/sbin/pci_bar_mmap_test 2>&1)
    status=$?
    set -e
    printf 'K11_GEN1_ACCEPTANCE_MMIO cycle=%s test=%s status=%s %s\n' \
        "${ROUND}" "${test_index}" "${status}" "${output//$'\n'/ }"
    test "${status}" -eq 0
    grep -q 'BAR_MMAP_PASS' <<<"${output}"
    grep -q 'signature=50434945' <<<"${output}"
    grep -q 'scratch=a5c37e19' <<<"${output}"
    grep -q 'ur=00000000 ca=00000000 axi=00000000' <<<"${output}"
done

aer_after=$(sudo -n journalctl -k -b --no-pager 2>/dev/null |
            grep -Ec "${error_pattern}" || true)
test "${aer_after}" = "${aer_before}"

aer_status=$(sudo -n lspci -s 00:01.0 -vvv |
             sed -n '/Advanced Error Reporting/,+15p' |
             grep -E 'UESta:|CESta:|RootSta:')
if grep -Eq '(DLP|SDES|TLP|FCP|CmpltTO|CmpltAbrt|UnxCmplt|RxOF|MalfTLP|ECRC|UnsupReq|ACSViol|RxErr|BadTLP|BadDLLP|Rollover|Timeout|AdvNonFatalErr|CERcvd|UERcvd)[+]' \
   <<<"${aer_status}"; then
    printf '%s\n' "${aer_status}" >&2
    echo "错误：Root Port AER状态非零" >&2
    exit 1
fi

printf 'K11_GEN1_ACCEPTANCE_CYCLE_PASS cycle=%s mmio=%s aer_new=0\n' \
    "${ROUND}" "${MMIO_COUNT}"
REMOTE
done

echo "K11_GEN1_RELEASE_ACCEPTANCE_PASS cycles=${cycles} mmio=$((cycles * mmio_per_cycle))"
