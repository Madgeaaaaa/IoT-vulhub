# 固件说明

固件本体**不入库**（体积大、版权归厂商）。本目录只保留说明与校验值。

## 目录里应该有哪个文件

| 文件名 | 版本 | 硬件 | 大小 | 状态 |
|---|---|---|---|---|
| `DIR815_revB_FW_V2.02b01.bin` | V2.02b01 | Rev B1（Ralink RT3052） | 4,591,760 B | **本环境默认目标** |
| `DIR815A1_FW103b01.bin` | 1.03 | Rev A1（Ralink RT3662） | ~3.5 MB | 可选，另一条硬件路线 |

> **Rev A1 和 Rev B1 的固件互不通用**——芯片、内核版本、`cgibin` 都可能不同。
> 你手上的是 Rev B，所以下文的默认值都按 B 写。

## 校验值（Rev B / V2.02b01，已实测）

```bash
sha256sum firmware/DIR815_revB_FW_V2.02b01.bin
# faaf6c614e615d25be93706195a33b059a23a26192c620d01ef09ede6828d638
```

| 文件 | 大小 | sha256 |
|---|---|---|
| DIR815_revB_FW_V2.02b01.bin | 4,591,760 | `faaf6c614e615d25be93706195a33b059a23a26192c620d01ef09ede6828d638` |

## 已确认的固件特征

| 项目 | 值 | 怎么来的 |
|---|---|---|
| 头部标记 | `signature=wrgnd12_dlob.hans_dir815b` | 偏移 0x0C 的 ASCII |
| 分区目标 | `dev=/dev/mtdblock/2`,`type=firmware` | 偏移 0x4E 起 |
| 内核 | Linux 2.6.33.2,gcc 4.3.3,编译于 2010-10-11 | LZMA 解压 @0x70 后取 `Linux version` |
| CPU | MIPS32_R2,Ralink **RT3052** | 内核镜像里的机器名 |
| 根文件系统 | squashfs 4.0,**LZMA** 压缩,64 KB 块,1873 inode | 偏移 0x140090 的 superblock |

完整的分析过程见 [`docs/firmware-notes.md`](../../docs/firmware-notes.md)。

> 因为 squashfs 是 **LZMA** 而不是 gzip，标准的 `unsquashfs` 解不开（会报
> `Unsupported compression type 2`），必须用 sasquatch 或 7z。见
> [`../README.md`](../README.md) 的解包一节。

## 获取方式

D-Link 已停止老型号的官方下载，常见来源：

1. D-Link 区域支持站（`support.dlink.ru`、`ftp.dlink.by`）的 `/pub/Router/DIR-815/Firmware/`
2. 互联网档案馆的 D-Link 支持页快照
3. 二手设备自带的光盘 / 升级包

## 合法性

仅用于本地仿真研究。不要二次分发固件，不要把仿真环境暴露到公网。
