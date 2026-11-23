#!/usr/bin/env bash
# boot-full.sh —— 用 QEMU system 模式把固件跑起来（不需要 Docker / 不需要 root）
#
# 做法:
#   1. 取一个能在 -M malta 上启动的 mipsel 内核(archive.debian.org 的 4kc-malta)
#   2. 把 squashfs-root 打成 initramfs,并塞一个自定义 /init
#   3. 启动 qemu-system-mipsel,用 slirp 把宿主 8080 转发到 guest 80
#
# 用法:
#   ROOTFS=~/work/dir815/squashfs-root ./tools/boot-full.sh build   # 只准备
#   ROOTFS=~/work/dir815/squashfs-root ./tools/boot-full.sh run     # 启动(前台)
#   ROOTFS=... ./tools/boot-full.sh run &  # 后台,然后 curl 127.0.0.1:8080
set -euo pipefail

ROOTFS="${ROOTFS:-./squashfs-root}"
SYS="${SYS:-$HOME/work/sys}"
ARCH="${ARCH:-mipsel}"
KERNEL_DEB_URL="${KERNEL_DEB_URL:-https://archive.debian.org/debian/pool/main/l/linux/linux-image-5.10.0-32-4kc-malta_5.10.223-1_mipsel.deb}"
KVER="${KVER:-5.10.0-32-4kc-malta}"
SIGN_DEFAULT="wrgnd12_dlob.hans_dir815b"

KROOT="$SYS/kroot"
QROOT="$SYS/qroot"
CROOT="$SYS/croot"
INITRD="$SYS/initrd.gz"
QEMU_SYS="$QROOT/usr/bin/qemu-system-$ARCH"

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }

# 免 root 取 deb 并解包到指定目录
fetch_deb() {
    local dest="$1"; shift
    mkdir -p "$dest/debs"
    ( cd "$dest/debs" && for p in "$@"; do
        ls "${p}"_*.deb >/dev/null 2>&1 || apt-get download "$p" >/dev/null 2>&1 || true
      done )
    for d in "$dest"/debs/*.deb; do [ -e "$d" ] && dpkg-deb -x "$d" "$dest" 2>/dev/null || true; done
}

prepare() {
    ROOTFS="$(cd "$ROOTFS" && pwd)"
    [ -d "$ROOTFS" ] || die "rootfs 不存在"
    mkdir -p "$SYS"

    if [ ! -f "$KROOT/boot/vmlinuz-$KVER" ]; then
        say "下载内核 $KVER"
        mkdir -p "$SYS/kdeb"
        ( cd "$SYS/kdeb" && curl -sL -o kernel.deb "$KERNEL_DEB_URL" && dpkg-deb -x kernel.deb "$KROOT" )
    fi
    say "内核: $KROOT/boot/vmlinuz-$KVER"

    if [ ! -x "$QEMU_SYS" ]; then
        say "取 qemu-system-$ARCH(含依赖库)"
        fetch_deb "$QROOT" qemu-system-mips qemu-system-data libslirp0 libfdt1 \
            libpixman-1-0 libglib2.0-0t64 libpmem1 libnuma1 librdmacm1t64 \
            libibverbs1 liburing2 libaio1t64 libndctl6 libdaxctl1 \
            libnl-route-3-200 libnl-3-200
    fi
    [ -x "$QEMU_SYS" ] || die "qemu-system 没取到"

    if [ ! -x "$CROOT/usr/bin/cpio" ]; then
        say "取 cpio"
        fetch_deb "$CROOT" cpio
    fi

    # 网络驱动模块(8139cp 才能驱动 qemu 的 rtl8139)
    local KM="$ROOTFS/lib/modules/$KVER"
    if [ ! -f "$KM/kernel/drivers/net/ethernet/realtek/8139cp.ko" ]; then
        say "拷网络驱动模块"
        mkdir -p "$KM/kernel/drivers/net/ethernet/realtek"
        cp "$KROOT/lib/modules/$KVER/kernel/drivers/net/mii.ko" \
           "$KM/kernel/drivers/net/" 2>/dev/null || true
        cp "$KROOT/lib/modules/$KVER/kernel/drivers/net/ethernet/realtek/8139cp.ko" \
           "$KM/kernel/drivers/net/ethernet/realtek/" 2>/dev/null || true
    fi

    local SIGN
    SIGN="$(tr -d '\r\n' < "$ROOTFS/etc/config/image_sign" 2>/dev/null || echo "$SIGN_DEFAULT")"

    say "写 /init(image_sign=$SIGN)"
    cat > "$ROOTFS/init" <<EOF
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /var/run /var/tmp /tmp /runtime
rm -f /var/run/xmldb_sock
M=/lib/modules/$KVER/kernel/drivers/net
insmod \$M/mii.ko 2>/dev/null
insmod \$M/ethernet/realtek/8139cp.ko 2>/dev/null
sleep 1
ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up
route add default gw 10.0.2.2 2>/dev/null
echo INIT-XMLDB
/usr/sbin/xmldb -n $SIGN &
sleep 2
/usr/sbin/xmldbc -s /runtime/device/modelname DIR-815
/usr/sbin/xmldbc -s /runtime/device/firmwareversion 2.02b01
/usr/sbin/xmldbc -s /runtime/services/http/server:1/mode HTTP
/usr/sbin/xmldbc -s /runtime/services/http/server:1/inf LAN-1
/usr/sbin/xmldbc -s /runtime/services/http/server:1/ifname eth0
/usr/sbin/xmldbc -s /runtime/services/http/server:1/af inet
/usr/sbin/xmldbc -s /runtime/services/http/server:1/ipaddr 10.0.2.15
/usr/sbin/xmldbc -s /runtime/services/http/server:1/port 80
/usr/sbin/xmldbc -s /runtime/services/http/server:1/hnap 1
/usr/sbin/xmldbc -s /runtime/services/http/server:1/widget 0
/usr/sbin/xmldbc -P /etc/services/HTTP/httpcfg.php > /var/run/httpd.conf
echo INIT-HTTPD
/sbin/httpd -f /var/run/httpd.conf
sleep 2
echo INIT-READY
exec /bin/sh
EOF
    chmod +x "$ROOTFS/init"

    say "打 initramfs"
    rm -f "$ROOTFS/var/run/xmldb_sock" "$INITRD"
    ( cd "$ROOTFS" && find . -print0 \
        | "$CROOT/usr/bin/cpio" --null -o -H newc 2>/dev/null \
        | gzip -1 > "$INITRD" )
    ls -lh "$INITRD"
}

run() {
    export LD_LIBRARY_PATH="$QROOT/usr/lib/x86_64-linux-gnu:$QROOT/lib/x86_64-linux-gnu"
    say "启动 QEMU(宿主 8080 -> guest 80,Ctrl-A X 退出)"
    exec "$QEMU_SYS" -M malta -m 256 \
        -kernel "$KROOT/boot/vmlinuz-$KVER" \
        -initrd "$INITRD" \
        -append "console=ttyS0 rdinit=/init panic=1" \
        -netdev "user,id=n0,hostfwd=tcp::8080-:80" \
        -device "rtl8139,netdev=n0,romfile=" \
        -vga none -nographic
}

case "${1:-run}" in
    build) prepare ;;
    run)   [ -f "$INITRD" ] || prepare; run ;;
    *)     die "用法: $0 [build|run]" ;;
esac
