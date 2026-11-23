#!/usr/bin/env bash
# unpack.sh - 解包 DIR-815 固件
#
# 本固件的 rootfs 是 squashfs 4.0 + LZMA 压缩, 标准 unsquashfs 不支持,
# 所以按 binwalk -> dd+7z -> 报错提示 的顺序尝试。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say()  { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

FW="${1:-}"
if [ -z "$FW" ]; then
    for cand in firmware/*.bin; do
        [ -e "$cand" ] && { FW="$cand"; break; }
    done
fi
[ -n "$FW" ] && [ -f "$FW" ] || die "没找到固件,把 bin 放进 firmware/ 或作为第一个参数传入"
say "固件: $FW"

if [ -d squashfs-root ]; then
    say "squashfs-root 已存在,跳过(要重解包先 rm -rf squashfs-root)"
    exit 0
fi

# ---------- 1. binwalk ----------
if command -v binwalk >/dev/null 2>&1; then
    say "尝试 binwalk -Me ..."
    binwalk -Me "$FW" >/dev/null 2>&1 || warn "binwalk 退出码非 0(可能只是没解出 squashfs)"
    found="$(find . -maxdepth 4 -type d -name 'squashfs-root' | head -n 1 || true)"
    if [ -n "$found" ]; then
        ln -sfn "${found#./}" squashfs-root
        say "解包成功: ${found#./}"
        exit 0
    fi
    warn "binwalk 没能解出 squashfs(LZMA 需要 sasquatch)"
else
    warn "没有 binwalk,跳到 dd + 7z"
fi

# ---------- 2. dd + 7z ----------
OFF="$(binwalk "$FW" 2>/dev/null | awk '/Squashfs filesystem/{print $1; exit}' || true)"
if [ -z "$OFF" ]; then
    OFF="$(python3 - "$FW" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
i = d.find(b"hsqs")
print(i if i >= 0 else "")
PY
)"
fi
[ -n "$OFF" ] || die "文件里没找到 squashfs 魔数,固件可能不是完整镜像"

say "squashfs 偏移: $OFF"
dd if="$FW" of=root.sqsh bs=1 skip="$OFF" status=none
say "已切出 root.sqsh ($(du -h root.sqsh | cut -f1))"

if command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1; then
    SEVEN="$(command -v 7z || command -v 7za)"
    say "尝试 $SEVEN x root.sqsh ..."
    "$SEVEN" x -y root.sqsh -orootfs >/dev/null 2>&1 || true
    if [ -d rootfs ]; then
        ln -sfn rootfs squashfs-root
        say "解包成功: rootfs/(已软链为 squashfs-root)"
        exit 0
    fi
    warn "7z 解包失败(版本太老不支持 LZMA squashfs?)"
else
    warn "没有 7z"
fi

# ---------- 3. 提示 ----------
die "两条路都失败。可选:
  1) 装 sasquatch:  git clone https://github.com/devttys0/sasquatch && cd sasquatch && ./build.sh
  2) 用 FirmAE 自带的 binwalk:  docker run --rm -v \"\$PWD/firmware:/firmware\" iot-vulhub/dir815-firmae \\
       /opt/FirmAE/binaries/binwalk -Me /firmware/\$(basename \"$FW\")
  3) 用 binwalk 容器 + p7zip: 见 README 4.2"
