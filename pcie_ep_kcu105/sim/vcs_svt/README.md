# K15 Synopsys SVT Gen3 x1 Root Complex comparison

This flow is independent of `sim/vcs/k11b_serial_board.sv`. It replaces only
the Root Complex with Synopsys SVT PCIe VIP and keeps the production standalone
PHY plus soft Endpoint unchanged.

O-2018.09 has no native x1 8G device-group SerDes wrapper. The flow uses the
x4 8G wrapper, configures maximum/supported/expected width to x1, connects lane
0, and holds the remaining receive lanes silent.

Run from `pcie_ep_kcu105`:

```bash
make k15-svt-vcs
```

The K14 comparison uses the same independent SVT board and can be run with:

```bash
make k14-svt-vcs
```

Its gate follows the K14 contract rather than the K15 strict-EQ contract: it
requires initial Gen1 x1 L0, an SVT-initiated equalization/rate request,
Endpoint partner acceptance, Gen3 PHY rate/PhyStatus, the expected timeout
fallback, Gen1 PHY rate/PhyStatus, and stable Gen1 x1 L0 recovery for two reset
epochs.

The strict pass marker requires two reset epochs, 8.0 GT/s x1 L0, Endpoint
partner-request acceptance, Gen3 PHY rate/PhyStatus, Equalization phases 0-3,
Recovery.Idle, and no speed timeout, fallback, or EQ failure. No Xilinx RP
source, configuration write, software retrain, forced TS, or forced LTSSM state
is used.

`rtl/vendor/wb2axip/afifo.v` is the upstream ZipCPU WB2AXIP asynchronous FIFO,
kept with its Apache-2.0 notice so this flow has no `/home/wx/Documents/AXI`
dependency.
