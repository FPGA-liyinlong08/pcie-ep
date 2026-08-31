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

VCS_ROOT=${VCS_ROOT:-${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}}
VIVADO_ROOT=${VIVADO_ROOT:-/home/Xilinx/Vivado/2021.2}
LICENSE_SERVER=${VCS_LICENSE_SERVER:-27000@wx-linux}

if [[ -n "${XILINX_VCS_SIMLIB:-}" ]]; then
  SIMLIB_DIR="${XILINX_VCS_SIMLIB}"
elif [[ -n "${VIVADO_SIMLIB:-}" ]]; then
  SIMLIB_DIR="${VIVADO_SIMLIB}"
elif [[ -f /home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs/synopsys_sim.setup ]]; then
  SIMLIB_DIR=/home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs
else
  echo "ERROR: Vivado VCS simlib not found; set XILINX_VCS_SIMLIB or VIVADO_SIMLIB" >&2
  exit 66
fi

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
  rm -f vlogan.log elaborate.log simulate.log waveform.log pcie_training.vcd
  mkdir -p "$BUILD_DIR/vcs_lib/xil_defaultlib"
fi

SETUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pcie3_rp_vcs_setup.XXXXXX")
SETUP_FILE="$SETUP_DIR/synopsys_sim.setup"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
  "$BUILD_DIR/vcs_lib/xil_defaultlib" "$BUILD_DIR/vcs_lib/xil_defaultlib" \
  "$SIMLIB_DIR" > "$SETUP_FILE"
export SYNOPSYS_SIM_SETUP="$SETUP_FILE"
echo "[VCS] simlib=$SIMLIB_DIR setup=$SETUP_FILE"

# The installed Bash predates mapfile -d.  These generated directories have
# no whitespace in file names, and Bash glob expansion is lexically ordered,
# so arrays keep the same deterministic source ordering without Bash 4.4.
GT_FILES=("$GT_STATIC_DIR"/gtwizard_ultrascale_v1_7*.v)
IP_SIM_FILES=("$IP_SIM_DIR"/*.v)
IP_SOURCE_FILES=("$IP_SOURCE_DIR"/*.v)
TB_FILES=("$IMPORT_DIR"/*.v)

echo "[VCS] compiling XPM and PCIe/testbench sources"
vlogan -full64 -sverilog +v2k -v2k_generate +define+XILINX_SIM +incdir+"$IMPORT_DIR" -work xil_defaultlib \
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
