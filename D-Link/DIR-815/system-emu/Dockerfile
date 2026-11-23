# QEMU system 模式镜像(手动全系统)
#
# 只装 qemu + 建镜像工具,内核/initrd 由使用者提供(放 images/)
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-system-mips \
        qemu-system-arm \
        e2fsprogs \
        iproute2 \
        net-tools \
        file \
        ca-certificates \
        bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /env

ENTRYPOINT ["/env/run.sh"]
