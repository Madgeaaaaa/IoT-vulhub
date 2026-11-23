#!/usr/bin/env bash
# 方式 B:QEMU system 手动全系统仿真
#   把 squashfs-root 打包成 rootfs.ext4,配合自备内核启动
set -euo pipefail

ARCH="${ARCH:-mipsel}"
ROOTFS="${ROOTFS:-/env/squashfs-root}"
IMAGES="${IMAGES:-/env/images}"
IMGDIR="${IMGDIR:-/env/work}"
IMG="$IMGDIR/rootfs.ext4"
MACHINE="${MACHINE:-malta}"
MODE="${MODE:-run}"

QEMU="qemu-system-${ARCH}"
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "[x] 没有 $QEMU,检查 ARCH=$ARCH 是否正确" >&2
    ls /usr/bin/qemu-system-* >&2 || true
    exit 1
}

[ -d "$ROOTFS" ] || { echo "[x] rootfs 不存在: $ROOTFS(先跑 init_env.sh)" >&2; exit 1; }

mkdir -p "$IMGDIR"

# ---------- 1. 生成磁盘镜像 ----------
if [ ! -f "$IMG" ]; then
    MB=$(( $(du -sm "$ROOTFS" | cut -f1) + 96 ))
    echo "[*] 生成 $IMG (${MB}M) <- $ROOTFS"
    truncate -s "${MB}M" "$IMG"
    mkfs.ext4 -q -F -d "$ROOTFS" "$IMG"
else
    echo "[*] 复用已有 $IMG"
fi

# ---------- 2. 找内核 ----------
if [ -z "${KERNEL:-}" ] || [ ! -f "${KERNEL:-}" ]; then
    KERNEL="$(ls "$IMAGES"/vmlinux* "$IMAGES"/*Image "$IMAGES"/zImage* 2>/dev/null | head -n 1 || true)"
fi
[ -n "${KERNEL:-}" ] && [ -f "$KERNEL" ] || {
    echo "[x] 没有内核。把与固件同架构的内核放到 $IMAGES/,或设置 KERNEL=" >&2
    echo "    ls $IMAGES" >&2
    exit 1
}
echo "[*] 内核: $KERNEL"

EXTRA=()
if [ -n "${INITRD:-}" ] && [ -f "${INITRD:-}" ]; then
    EXTRA+=(-initrd "$INITRD")
fi
if [ "$MODE" = "gdb" ]; then
    EXTRA+=(-gdb tcp::6666 -S)
    echo "[*] gdb 监听 6666(暂停等连接)"
fi

# ---------- 3. 启动 ----------
echo "[*] $QEMU -M $MACHINE  (Web: http://127.0.0.1:8888/ , ssh: 2222)"
exec "$QEMU" \
    -M "$MACHINE" \
    -kernel "$KERNEL" \
    "${EXTRA[@]}" \
    -drive "file=$IMG,format=raw,if=ide" \
    -append "${APPEND:-root=/dev/sda rw console=ttyS0}" \
    -netdev "user,id=n0,hostfwd=tcp::8888-:80,hostfwd=tcp::2222-:22" \
    -device "rtl8139,netdev=n0" \
    -nographic
