# FirmAE 全系统仿真镜像
#
# 说明:
#   - apt 依赖在这里一次装齐(等价于 FirmAE 的 install.sh 前半段)
#   - download.sh 拉的是预编译的 qemu / binwalk 二进制,约 2-3 GB
#   - 若 download.sh 失败(网络),进容器手动执行: cd /opt/FirmAE && ./install.sh
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git sudo wget curl ca-certificates \
        python3 python3-pip python3-psutil python3-netifaces \
        binwalk squashfs-tools qemu-system-mips qemu-system-arm qemu-user-static \
        net-tools iproute2 iptables iputils-ping bridge-utils uml-utilities \
        cpio unzip bc file gcc libc6-i386 lib32z1 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/pr0cf5/FirmAE /opt/FirmAE \
    || (echo "clone FirmAE 失败,请配置代理后重建" && exit 1)

WORKDIR /opt/FirmAE

RUN ./download.sh

# 便捷入口:直接在容器里跑 firmae-run 即可
COPY run.sh /usr/local/bin/firmae-run
RUN chmod +x /usr/local/bin/firmae-run

CMD ["/bin/bash"]
