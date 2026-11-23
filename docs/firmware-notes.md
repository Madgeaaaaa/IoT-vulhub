# 固件结构分析记录：DIR-815 Rev B1 / V2.02b01

用于论文附录或复现记录。全部结论来自对
`DIR815_revB_FW_V2.02b01.bin`（4,591,760 字节，
sha256 `faaf6c61…6828d638`）的离线解析。

## 1. D-Link 自定义头

```text
0000  5e a3 a4 17 00 00 00 24 00 00 00 00 73 69 67 6e
0010  61 74 75 72 65 3d 77 72 67 6e 64 31 32 5f 64 6c
0020  6f 62 2e 68 61 6e 73 5f 64 69 72 38 31 35 62 00
0030  5e a3 a4 17 00 00 00 24 00 46 10 20 e9 78 16 6f
0040  55 b7 5b 3a 34 ba 2e c9 67 35 21 af 64 65 76 3d
0050  2f 64 65 76 2f 6d 74 64 62 6c 6f 63 6b 2f 32 00
0060  74 79 70 65 3d 66 69 72 6d 77 61 72 65 00 00 00
```

| 偏移 | 内容 |
|---|---|
| 0x00 | 固件头魔数 `5e a3 a4 17` |
| 0x04 | 头长度 `0x24` |
| 0x08 | 保留 |
| 0x0C | `signature=wrgnd12_dlob.hans_dir815b` |
| 0x30 | 又一段魔数 + MD5（`46 10 20 e9 …`） |
| 0x4E | `dev=/dev/mtdblock/2` |
| 0x60 | `type=firmware` |
| 0x70 | 内核 LZMA 流起点（`5d 00 00`） |

`hans_dir815b` 直接点明了型号与硬件版本：**DIR-815 的 B 版**。

## 2. 内核

偏移 0x70 起是 **LZMA-alone** 流，解开后 3,805,904 字节，其中可见：

```text
Linux version 2.6.33.2 (joely@RangeRover) (gcc version 4.3.3 (GCC) )
    #1 Thu Oct 11 14:54:16 CST 2010
MIPS32_R2 32BIT
ralink  rt3052
```

结论：

- 芯片 **Ralink RT3052**（MIPS 24KEc），不是 Rev A1 的 RT3662
- 内核 2.6.33.2，2010 年构建，gcc 4.3.3
- Ralink SDK 的 RT305x 平台固件一律按 **小端（mipsel）** 处理；最终仍以解包后
  `file htdocs/cgibin` 的输出为准

## 3. 根文件系统

偏移 **0x140090** 处是 squashfs 4.0：

| 字段 | 值 |
|---|---|
| magic | `hsqs`（小端） |
| 版本 | 4.0 |
| inode 数 | 1873 |
| block size | 65536 |
| fragments | 84 |
| 压缩算法 | **2 = LZMA** |
| no_ids | 1 |

因此：

- `binwalk` 能识别出 squashfs，但**解包需要 sasquatch**（打过 LZMA 补丁的
  unsquashfs）或 7-Zip
- Ubuntu 自带的 `unsquashfs` 会直接报 `Unsupported compression type 2`
- 文件里几乎没有明文符号（内容全被压缩），所以靠 `strings` 找不到型号/路径，
  必须解包后再看

## 4. 对其他偏移的排除

| 命中 | 偏移 | 判断 |
|---|---|---|
| gzip | 0x116AE5 | 解压失败，是压缩数据内部的偶然命中 |
| jffs2 | 0xBDE3 等 6 处 | 短魔数（2 字节）偶然命中，非真实 JFFS2 |
| ELF | 无 | 内核与用户态程序都在 LZMA 流内部 |

## 5. 复现这段分析的脚本

思路（不依赖 binwalk）：

```python
import lzma, struct
data = open("DIR815_revB_FW_V2.02b01.bin", "rb").read()
kernel = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(data[0x70:])
# 在 kernel 里 grep "Linux version" / "rt3052"
off = 0x140090
print(data[off:off+4], struct.unpack("<IIIIHHHHHH", data[off+4:off+32]))
```

## 6. 对仿真的影响

1. **目标硬件从 A1 改成 B1**：芯片 RT3052，内核 2.6.33.2。
2. **解包链路要能处理 LZMA squashfs**，否则后面全部卡住。
3. **QEMU system（方式 B）基本不可行**：拿到的是 Ralink 板级内核，
   在 QEMU 的 `malta` 机型上起不来；这条路只在能拿到通用 mipsel 内核时才有意义。
   优先用 FirmAE（方式 A）或 qemu-user（方式 C）。
4. `hedwig.cgi` 的溢出属于 D-Link 共用 `cgibin` 代码，B 版大概率仍存在，
   但**必须解包后自己确认**（看 `htdocs/web/hedwig.cgi` 是否存在、`cgibin` 里
   有没有 `hedwigcgi_main`）。
