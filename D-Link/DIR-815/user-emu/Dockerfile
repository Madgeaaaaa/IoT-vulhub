# QEMU user 模式镜像:只跑单个二进制,不需要内核
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-user-static \
        gdb-multiarch \
        file \
        python3 \
        bash \
        less \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /env

ENTRYPOINT ["/env/run.sh"]
