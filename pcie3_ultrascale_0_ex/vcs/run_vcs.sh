#!/usr/bin/env bash
set -Eeuo pipefail

# VCS flow for the Vivado PCIe Gen3 example testbench.
# The Vivado-exported VCS script compiles only the IP itself; this flow adds
# the board/RP/EP example sources and uses board as the simulation top.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEMO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$SCRIPT_DIR/build}
TESTNAME=${TESTNAME:-pio_writeReadBack_test0}
WAVEFORM=${WAVEFORM:-0}
TRACE_LTSSM=${TRACE_LTSSM:-0}

VCS_ROOT=${VCS_ROOT:-/home/synopsys/vcs-mx/O-2018.09-SP2}
VIVADO_ROOT=${VIVADO_ROOT:-/home/Xilinx/Vivado/2021.2}
SIMLIB_DIR=${XILINX_VCS_SIMLIB:-/home/wx/Documents/vcs_compile_simlib}
LICENSE_SERVER=${VCS_LICENSE_SERVER:-27000@wx-linux}

export VCS_HOME="$VCS_ROOT"
export VCS_ARCH_OVERRIDE=${VCS_ARCH_OVERRIDE:-linux}
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-$LICENSE_SERVER}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":$LICENSE_SERVER:"* ]]; then
  export LM_LICENSE_FILE="$LICENSE_SERVER${LM_LICENSE_FILE:+:$LM_LICENSE_FILE}"
fi
export PATH="$VCS_HOME/bin:$PATH"

if [[ ! -x "$VCS_HOME/bin/vcs" || ! -x "$VCS_HOME/linux64/bin/vcs1" ]]; then
  echo "ERROR: VCS installation not found under $VCS_HOME" >&2
  exit 1
fi

IP_DIR="$DEMO_DIR/pcie3_ultrascale_0_ex.gen/sources_1/ip/pcie3_ultrascale_0"
GT_STATIC_DIR="$IP_DIR/ip_0/hdl"
IP_SIM_DIR="$IP_DIR/ip_0/sim"
IP_SOURCE_DIR="$IP_DIR/source"
IP_TOP_SIM="$IP_DIR/sim/pcie3_ultrascale_0.v"
IMPORT_DIR="$DEMO_DIR/imports"
XPM_CDC="$VIVADO_ROOT/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv"
GLBL="$VIVADO_ROOT/data/verilog/src/glbl.v"

for required in "$GT_STATIC_DIR" "$IP_SIM_DIR" "$IP_SOURCE_DIR" "$IP_TOP_SIM" "$IMPORT_DIR" "$XPM_CDC" "$GLBL" "$SIMLIB_DIR/synopsys_sim.setup"; do
  [[ -e "$required" ]] || { echo "ERROR: missing simulation input: $required" >&2; exit 1; }
done

mkdir -p "$BUILD_DIR/vcs_lib/xil_defaultlib"
cd "$BUILD_DIR"

if [[ "${1:-}" == "clean" ]]; then
  rm -rf "$BUILD_DIR/vcs_lib" csrc board_simv board_simv.daidir ucli.key 64
  rm -f vlogan.log elaborate.log simulate.log waveform.log pcie_training.vcd synopsys_sim.setup
  mkdir -p "$BUILD_DIR/vcs_lib/xil_defaultlib"
fi

cat > synopsys_sim.setup <<'EOF'
xil_defaultlib : ./vcs_lib/xil_defaultlib
WORK          : xil_defaultlib
EOF
printf 'OTHERS = %s/synopsys_sim.setup\n' "$SIMLIB_DIR" >> synopsys_sim.setup

mapfile -d '' GT_FILES < <(find "$GT_STATIC_DIR" \
  -maxdepth 1 -type f -name 'gtwizard_ultrascale_v1_7*.v' -print0 | sort -z)
mapfile -d '' IP_SIM_FILES < <(find "$IP_SIM_DIR" -maxdepth 1 -type f -name '*.v' -print0 | sort -z)
mapfile -d '' IP_SOURCE_FILES < <(find "$IP_SOURCE_DIR" -maxdepth 1 -type f -name '*.v' -print0 | sort -z)
mapfile -d '' TB_FILES < <(find "$IMPORT_DIR" -maxdepth 1 -type f -name '*.v' -print0 | sort -z)

echo "[VCS] compiling XPM and PCIe/testbench sources"
vlogan -full64 -sverilog +v2k +define+XILINX_SIM +incdir+"$IMPORT_DIR" -work xil_defaultlib \
  "$DEMO_DIR/../pcie_ep_kcu105/rtl/phy/pcie_gen3_scrambler32.sv" \
  "$DEMO_DIR/../pcie_ep_kcu105/rtl/phy/pcie_gen3_os_rx.sv" \
  "$XPM_CDC" "${GT_FILES[@]}" "${IP_SIM_FILES[@]}" "$IP_TOP_SIM" \
  "${IP_SOURCE_FILES[@]}" "${TB_FILES[@]}" "$GLBL" 2>&1 | tee vlogan.log

echo "[VCS] elaborating board + glbl"
vcs -full64 -t ps -debug_acc+pp+dmptf -licqueue \
  -Lsecureip -Lunisims_ver -Lxpm \
  -LDFLAGS "-Wl,--no-as-needed" -Mdir="$BUILD_DIR/csrc" \
  -l elaborate.log -o board_simv xil_defaultlib.board xil_defaultlib.glbl

echo "[VCS] running TESTNAME=$TESTNAME"
SIM_ARGS=(+TESTNAME="$TESTNAME")
if [[ "$WAVEFORM" == "1" ]]; then
  SIM_ARGS+=(+DUMP_WAVEFORM +TRACE_LTSSM)
elif [[ "$TRACE_LTSSM" == "1" ]]; then
  SIM_ARGS+=(+TRACE_LTSSM)
fi
./board_simv -licqueue -l simulate.log "${SIM_ARGS[@]}"

echo "[VCS] completed; log: $BUILD_DIR/simulate.log"
