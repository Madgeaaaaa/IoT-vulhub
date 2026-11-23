# 全系统仿真：把 DIR-815 固件真正跑起来

目标：让固件里的 `httpd` 真的对外提供 HTTP 服务，从而能在**完整链路**上测漏洞
（尤其是需要 `$_POST` 的 `getcfg.php`）。

## 0. 两条路线对比（都试过了）

| | chroot + qemu-user | QEMU system（本文主方案） |
|---|---|---|
| 启动时间 | **~5 秒** | ~16 秒 |
| 需要内核 | ❌ 不需要 | ✅ Debian 4kc-malta |
| 需要 Docker | ❌ | ❌ |
| 需要 root | 需要 userns 造"假 root"(`unshare -rmnp`) | ❌（initramfs 里天然是 root） |
| init 序列 / 内核模块 | ❌ 没有 | ✅ |
| httpd 监听 + HTTP 响应 | ✅ **已验证** | ✅ 已验证 |
| PHP（phpcgi） | ❌ 500 | ❌ 500 |
| 脚本 | [`tools/run-chroot.sh`](../D-Link/DIR-815/tools/run-chroot.sh) | [`tools/boot-full.sh`](../D-Link/DIR-815/tools/boot-full.sh) |

**关键结论：两条路线卡在同一个地方——`phpcgi`。**
换成 chroot 不会解决问题，它只是启动更快、更轻。

chroot 路线的两个坑：

1. **`httpd` 的 `Interface` 指令要 `CAP_NET_RAW`**，普通用户/proot 下绑定会失败
   → 用 `unshare -rmnp` 进 user namespace 才拿得到
2. **`mknod` 在 user namespace 里被内核拒绝**（`Operation not permitted`），
   连 userns 自己挂的 tmpfs 也不行 → 改成**单文件 `mount --bind /dev/null`**
   （注意：不能整个 bind `/dev`，devtmpfs 在 userns 里挂不上去）

## 1. 为什么不用 FirmAE

FirmAE 是最省事的路，但它依赖 Docker；本机 Docker 拉 `registry-1.docker.io`
时被代理 TLS 拦截（`x509: certificate is not valid for any names`）。
于是改为**手工 QEMU system 仿真**，全程不需要 Docker、不需要 root。

## 2. 方案

```
archive.debian.org 的 mipsel 4kc-malta 内核
        +
squashfs-root(固件用户态)打成 initramfs + 自定义 /init
        ↓
qemu-system-mipsel -M malta  →  mathopd(httpd)  →  phpcgi(cgibin 的 PHP 模式)  →  xmldb
```

一键脚本：[`tools/boot-full.sh`](../D-Link/DIR-815/tools/boot-full.sh)

```bash
cd D-Link/DIR-815
ROOTFS=~/work/dir815/squashfs-root ./tools/boot-full.sh build
ROOTFS=~/work/dir815/squashfs-root ./tools/boot-full.sh run     # 前台
# 另开一个终端
curl -i http://127.0.0.1:8080/index.html
```

## 3. 已经跑通的部分

| 环节 | 状态 | 证据 |
|---|---|---|
| 内核启动 | ✅ | Linux 5.10.0-32-4kc-malta，malta 机型 |
| 固件用户态 init | ✅ | 自写 `/init`，busybox 1.14.1 shell |
| 网络 | ✅ | `8139cp` 驱动，eth0 = 10.0.2.15，link up |
| xmldb 配置树 | ✅ | `/var/run/xmldb_sock` 建立 |
| httpd 配置生成 | ✅ | `xmldbc -P /etc/services/HTTP/httpcfg.php` 产出带 `Server{}` 的 conf |
| httpd 监听 | ✅ | `tcp 10.0.2.15:80 LISTEN` |
| **HTTP 真实响应** | ✅ | `curl -i /index.html` → `404`，带 `Server: Linux, HTTP/1.1, DIR-815 Ver 2.02b01` |
| PHP 引擎 | ✅ | `xmldbc -P /htdocs/web/DevInfo.php` → `Model Name: DIR-815` 等真实数据 |

## 4. 还没打通的部分

| 环节 | 状态 | 说明 |
|---|---|---|
| `phpcgi`（cgibin 的 PHP-CGI 模式） | ❌ | 各种调用约定都返回 255，无法驱动 |
| `$_POST` 填充 | ❌ | 只由 phpcgi 完成；`xmldbc -P` 的 `-V` 只进 `$_GLOBALS`，不进 `$_POST` |
| getcfg.php 端到端取口令 | ❌ | 卡在上面两条 |

### 关于 `phpcgi`

- `/usr/sbin/phpcgi` 是 `/htdocs/cgibin` 的软链（又一次 argv[0] 分派，
  和 `hedwig.cgi` 同一个机制）
- 试过这些调用方式，全部 `rc=255` 且无输出：
  - `phpcgi < script.php`
  - `REQUEST_METHOD=GET phpcgi < script.php`
  - `phpcgi script.php`
  - `phpcgi "GET /DevInfo.php HTTP/1.0"`
  - 把完整 HTTP 请求（含 Content-Length）从 stdin 喂进去
- 唯一有反应的是 `phpcgi /htdocs/web/DevInfo.php`：返回
  `HTTP/1.1 400 Bad Request ... unsupported HTTP request`，
  说明它把 argv[1] 当成了请求行去解析，但格式和我们的猜测都不一致
- 推测：mathopd 是**改写过的**，用私有协议把请求交给 phpcgi；
  要复现得逆 `sbin/httpd` 的 fork/exec 逻辑

## 5. 对 CVE-2018-10106 的意义

- **PHP 层已确认**：`AUTHORIZED_GROUP=0` 通过 `is_power_user()`，
  `-1` 和空值被拒（见 [cve-2018-10106.md](./cve-2018-10106.md)）
- **HTTP 层未完成**：因为 `$_POST` 拿不到，`SERVICES=DEVICE.ACCOUNT`
  传不进 `getcfg.php`，所以“一条请求拿到管理员口令”没跑通
- 但固件本身已经完整运行，`httpd` 能被真实访问——**继续逆 `phpcgi` 的协议是唯一剩余障碍**

## 6. 踩坑清单（都写进脚本了）

1. **`8139too` 驱动不认 QEMU 的网卡**：报
   `This (id 10ec:8139 rev 20) is an enhanced 8139C+ chip, use 8139cp`，
   必须换成 `8139cp.ko`
2. **`httpd` 需要运行时节点**：`/runtime/services/http/server` 为空时，
   生成的 `httpd.conf` 只有全局配置、没有 `Server{}`，于是“启动了但不监听”
3. **必须 `rm -f /var/run/xmldb_sock`**：静态 rootfs 里残留的 socket 会让
   xmldb 报 `already created` 并拒绝工作
4. **`xmldb` 要带根节点名**：`xmldb -n $(cat /etc/config/image_sign)`
   （来自 `etc/init.d/S20init.sh`）
5. **busybox 缺 applet**：没有 `timeout`、`head`、`printf`、`wc`；
   串口控制台还会把超过 ~80 列的命令行折断，所以测试脚本要写进 rootfs 里跑
6. **`-vga none` 必要**：否则 qemu 找不到 `vgabios-cirrus.bin`；
   网卡加 `,romfile=` 可避开缺失的 `efi-rtl8139.rom`

## 7. 下一步

1. 逆 `sbin/httpd`（mathopd）的 `External` 处理逻辑，搞清它怎么调 `phpcgi`
2. 或者绕开 httpd：直接给 cgibin 造一个符合它期望的调用环境
3. 打通后用 `curl -d 'SERVICES=DEVICE.ACCOUNT' http://127.0.0.1:8080/getcfg.php`
   做真正的未授权读取验证
