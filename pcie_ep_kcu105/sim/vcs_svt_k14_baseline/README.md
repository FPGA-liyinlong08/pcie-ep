# K14 Golden (5095e7c) Synopsys SVT RP comparison

This flow replaces the Xilinx Root Port only. It compiles the Endpoint RTL
from commit `5095e7c4e8b23c356e11e1915c065f1ace88f92d`, keeps the standalone
KCU105 PCIe PHY, and connects lane 0 of the Synopsys SVT x4 8G wrapper while
restricting the configured link width to x1.

Run:

```bash
make k14-golden-svt-vcs
```

The gate follows the hardware-backed K14 Golden boundary: SVT must initiate a
speed/equalization request, the Endpoint must accept the partner request, and
the standalone PHY must reach Gen3 rate, QPLL lock, and fresh PhyStatus for two
reset epochs. It does not claim EQ Phase 0-3, Recovery.Idle, or Gen3 L0.

The original Xilinx RP baseline and its board are not modified.
