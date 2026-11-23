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
