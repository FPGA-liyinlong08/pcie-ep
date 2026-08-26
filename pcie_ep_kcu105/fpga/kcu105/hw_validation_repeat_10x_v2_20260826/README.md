# Fixed-bit link repeat validation — 2026-08-26 (complete RP capture)

No synthesis or implementation was run. The same E1 AUTO=0 bit (`4be7f4b1...`) and the same K14 baseline bit (`27596864...`) were each programmed ten times. Every iteration performed JTAG programming, remote host reboot, SSH recovery, and immediate link capture.

Each `link_logs/*.txt` contains:

- Root Port `LnkCap`, `LnkCtl`, `LnkSta` plus the following `Train`/`DLActive` line, `LnkCtl2`, and `LnkSta2`
- Raw `CAP_EXP+12.w`
- Endpoint status or absence
- PCIe topology
- Root Port and Endpoint sysfs speed/width

Results:

| Image | Result |
|---|---|
| E1 AUTO=0 | 4/10 pass, 6/10 fail |
| K14 baseline | 10/10 pass |

E1 AUTO=0 failure raw statuses were `d011`, `5811`, `d811`, and `1801`; all had `DLActive-`. Passing E1 and all K14 runs had `Train-`, `DLActive+`, and endpoint `1234:e001` present. ILA/sticky status was not armed in this round; these files are the complete host-side captures.

The board was left programmed with K14 baseline; the final run passed Gen1 x1 enumeration.
