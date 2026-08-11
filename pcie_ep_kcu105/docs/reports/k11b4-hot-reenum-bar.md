# K11-B4 热切换重新枚举与 BAR0 实测

日期：2026-08-12

## 目的

确认 XDMA Gen3 x1 建链后热下载 Standalone，Linux 删除旧 endpoint、重新扫描后，是否能够实际访问 Standalone 的 4 KiB BAR0。

## 操作序列

1. 冷启动加载官方 `fpga/kcu105/xdma_x1_demo/build/xdma_x1_demo.bit`，远端主机重启后确认 Root Port `Speed 8GT/s, Width x1, DLActive+`。
2. 在主机保持运行时热下载 `build_k11b2/impl/k11b2_gen1_endpoint.bit`。
3. 读取旧节点确认配置空间已变为 `e0011234`，然后执行：
   `echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove; echo 1 > /sys/bus/pci/rescan`。
4. 重新枚举结果为 `01:00.0 Device [1234:e001]`，BAR0 为 `0x82800000`、大小 4 KiB，链路 `2.5GT/s x1, DLActive+`。
5. 重新枚举后 Linux 默认 `Command=0000`，先写 `04.w=0006` 开启 Memory Space 与 Bus Master，再用 `mmap()` 访问 `/sys/bus/pci/devices/0000:01:00.0/resource0`。

## 实测结果

```text
0006
BAR_MMAP signature=50434945 version=00010000 link=00000a01 before=00000000 scratch=a5c37e19 ur=00000000 ca=00000000 axi=00000000
BAR_MMAP_PASS
BAR0
82800000
AER
00000000
```

- `0x000` 签名读回 `0x50434945`（PCIE）。
- `0x004` 版本读回 `0x00010000`。
- `0x040` scratch 写入并读回 `0xa5c37e19`。
- BAR 未完成、Completer Abort、AXI 错误计数均为 0；Root Port AER 状态为 0。

注意：直接对 `resource0` 使用 `read(2)`/`dd` 返回 `EIO`，这是 sysfs PCI resource 文件不提供普通 read 的接口限制；用真实 `mmap()` MMIO 访问后通过。

测试程序：`tools/pci_bar_mmap_test.c`。
