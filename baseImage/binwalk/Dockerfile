FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        binwalk \
        squashfs-tools \
        cpio \
        file \
        unzip \
        p7zip-full \
        lzma \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

ENTRYPOINT ["binwalk"]
