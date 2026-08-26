# PCIe link repeat validation — 2026-08-26

Each row in `link_results.csv` is one complete cycle:

1. Program the bitstream over JTAG.
2. Reboot the remote PCIe host.
3. Check endpoint `01:00.0`, vendor/device IDs, current Gen1 speed/width, and `LnkSta`.

All 18 program operations and all 18 host reboot cycles returned status 0.

| Image | Result |
|---|---|
| E1 AUTO=0 | 2/3 pass |
| E1 AUTO=1 | 0/3 pass |
| E1 timing AUTO=0 | 3/3 pass |
| E1 timing AUTO=1 | 0/3 pass |
| Golden `fb05cf...` | 0/3 pass |
| K14 baseline | 3/3 pass |

Pass criterion: `01:00.0 Device 1234:e001`, `2.5 GT/s x1`, `Train-`, `DLActive+`.

The board was left programmed with the K14 baseline after validation; its final link check passed.
