#!/usr/bin/env bash
# init_env.sh - 初始化 DIR-815 仿真环境
#   1) 找固件  2) 找 rootfs  3) 探测架构  4) 生成 .env  5) 软链 squashfs-root
# 用法: ./init_env.sh [mips|mipsel|arm|armel|x86_64]
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------- 1. 固件 ----------------
FW=""
for cand in firmware/*.bin firmware/*.zip firmware/*.img firmware/*.chk; do
    if [ -e "$cand" ]; then FW="$cand"; break; fi
done

if [ -n "$FW" ]; then
    say "固件: $FW ($(du -h "$FW" | cut -f1))"
else
    warn "firmware/ 下没有固件(见 firmware/README.md),跳过固件检查"
fi

# ---------------- 2. rootfs ----------------
ROOTFS="$(find . -maxdepth 4 -type d \
            \( -name 'squashfs-root' -o -name 'cramfs-root' -o -name 'romfs' \) \
          2>/dev/null | head -n 1 || true)"

if [ -z "$ROOTFS" ]; then
    warn "没找到解包后的根文件系统,先解包:"
    cat <<EOF
    cd ../../baseImage/binwalk && docker build -t iot-vulhub/binwalk .
    cd -
    docker run --rm -v "\$PWD/firmware:/firmware" iot-vulhub/binwalk \\
      -Me /firmware/$(basename "${FW:-<firmware.bin>}" 2>/dev/null || echo '<firmware.bin>')
EOF
    exit 2
fi
say "rootfs: ${ROOTFS#./}"

# ---------------- 3. 架构 ----------------
detect_arch() {
    local bin="$1" info
    info="$(file -b "$bin" 2>/dev/null || true)"
    case "$info" in
        *MIPS*) case "$info" in *LSB*) echo mipsel ;; *) echo mips ;; esac ;;
        *ARM*)  case "$info" in *LSB*) echo armel  ;; *) echo arm  ;; esac ;;
        *"Intel 80386"*|*x86-64*) echo x86_64 ;;
        *) echo unknown ;;
    esac
}

ARCH="${1:-}"
if [ -z "$ARCH" ]; then
    for cand in \
        "$ROOTFS/htdocs/cgibin" \
        "$ROOTFS/bin/busybox" \
        "$ROOTFS/usr/bin/busybox" \
        "$ROOTFS/bin/sh"
    do
        [ -f "$cand" ] || continue
        ARCH="$(detect_arch "$cand")"
        if [ "$ARCH" != "unknown" ]; then
            say "架构探测: $ARCH  (来自 ${cand#"$ROOTFS"})"
            break
        fi
    done
fi

if [ -z "$ARCH" ] || [ "$ARCH" = "unknown" ]; then
    ARCH="mipsel"
    warn "架构探测失败,先按 mipsel 处理;不对就手动指定: ./init_env.sh mips"
fi

# ---------------- 4. .env ----------------
cat > .env <<EOF
# 由 init_env.sh 自动生成,不要提交
ARCH=$ARCH
FW=$FW
ROOTFS=${ROOTFS#./}
EOF
say "已写入 .env (ARCH=$ARCH)"

# ---------------- 5. 软链 ----------------
ln -sfn "${ROOTFS#./}" squashfs-root
say "已创建软链 squashfs-root -> ${ROOTFS#./}"

# ---------------- 6. 提示 ----------------
if [ -f "$ROOTFS/htdocs/web/hedwig.cgi" ]; then
    say "已确认 hedwig.cgi 存在,可进入验证阶段"
else
    warn "没找到 htdocs/web/hedwig.cgi,该固件可能不是预期版本"
fi

if ! ls system-emu/images/* >/dev/null 2>&1; then
    warn "system-emu/images/ 为空;要用方式 B 需自行放入同架构内核(KERNEL 指向它)"
fi

cat <<EOF

下一步:
  A. FirmAE(推荐)   docker compose -f docker-compose-firmae.yml run --rm firmae
  B. 手动全系统      KERNEL=/env/images/<内核> docker compose -f docker-compose-system.yml up --build
  C. 单二进制调试    docker compose -f docker-compose-user.yml run --rm user-emu

EOF
