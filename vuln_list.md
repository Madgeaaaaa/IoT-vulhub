# 漏洞环境列表

`*EXP*` 表示环境内提供了可运行的验证脚本；未标注表示仅有环境说明。

## D-Link

- **已验证** | [DIR-815（Rev B1 / RT3052）固件仿真环境](./D-Link/DIR-815)
  - 固件 `DIR815_revB_FW_V2.02b01.bin`，squashfs 4.0 + LZMA，mipsel / uClibc
  - `/hedwig.cgi` Cookie 栈溢出：**Cookie ≥ 1038 字节触发 SIGSEGV**
  - 复现记录：[docs/repro.md](./docs/repro.md)

## TODO

- [ ] DIR-815 补齐 FirmAE 启动截图与 ROP 利用链
- [ ] 补充 DIR-859 CVE-2019-17621（对照 Vu1nT0tal/IoT-vulhub 的实现）
- [ ] 补充一个 ARM 架构目标，验证 armel 分支脚本
