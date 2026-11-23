# 最小 binwalk 解包镜像

本仓库的固件解包统一在这个容器里做，避免主机装一堆 squashfs/cramfs 依赖。

```bash
cd baseImage/binwalk
docker build -t iot-vulhub/binwalk .

# 用法
docker run --rm -v "$PWD/../../D-Link/DIR-815/firmware:/firmware" \
  iot-vulhub/binwalk -Me /firmware/DIR815A1_FW103b01.bin
```

产物在固件同级的 `_*.extracted/` 目录里，注意解析出来的 rootfs 可能是
`squashfs-root`、`cramfs-root`、`romfs` 等不同名字，`init_env.sh` 会一并去找。

## 注意：LZMA 压缩的 squashfs 解不开

Ubuntu 的 `binwalk` + `unsquashfs` **只支持 gzip/lzo/xz/zstd**，遇到
`squashfs 4.0 + LZMA`（D-Link 老固件很常见）会报 `Unsupported compression type 2`，
`-Me` 只识别不提取。

对策（详见 `D-Link/DIR-815/README.md` 的 4.2 节）：

1. 用各环境里的 `tools/unpack.sh`，它会退化成 `dd` + `7z`
2. 自己编译 `sasquatch`（打过 LZMA 补丁的 unsquashfs）
3. 用 FirmAE 镜像里自带的 `binaries/binwalk`
