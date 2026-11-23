#!/usr/bin/env bash
# 容器内便捷入口,包装 FirmAE 的 run.sh
# 用法: firmae-run            -> 用环境变量 BRAND / FW / MODE
#       firmae-run -d         -> 调试模式
set -euo pipefail

BRAND="${BRAND:-dlink}"
MODE="${MODE:-r}"

# 允许第一个参数覆盖模式(r/d/c)
if [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; then
    MODE="${1#-}"
    shift
fi

if [ -z "${FW:-}" ] || [ ! -f "${FW:-}" ]; then
    FW="$(ls /firmware/*.bin /firmware/*.chk 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${FW:-}" ] || [ ! -f "$FW" ]; then
    echo "[x] 找不到固件。请把固件放到 D-Link/DIR-815/firmware/ 并设置 FW" >&2
    exit 1
fi

echo "[*] FirmAE mode=-$MODE brand=$BRAND firmware=$FW"
cd /opt/FirmAE
exec ./run.sh "-$MODE" "$BRAND" "$FW"
