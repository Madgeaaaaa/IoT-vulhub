# D-Link DIR-815 固件仿真环境

## 1. 目标设备

| 项目 | 内容 |
|---|---|
| 型号 | D-Link DIR-815（rev A1） |
| 硬件平台 | Ralink RT3662（MIPS） |
| 固件示例 | `DIR815A1_FW103b01.bin`（约 3.5 MB） |
| 固件来源 | D-Link 官方支持站点 / 固件镜像站（见 [firmware/README.md](./firmware/README.md)） |
| 架构判定 | **以 `file` 输出为准**，Ralink 平台通常是 `mipsel`（小端），脚本会自动探测 |

> DIR-815 有多个硬件版本（Rev A1 为 Ralink，后续 Rev E/S/R 换成了 Realtek RT8197F/G），
> 固件**不可混用**。先用 `binwalk` 看一眼再决定，别拿 B 版固件套 A 版环境。

## 2. 已知漏洞线索

本环境主要服务于下面这条线索的复现与调试：

- **位置**：`/htdocs/web/hedwig.cgi`（实际是 `/htdocs/cgibin` 的软链，入口函数 `hedwigcgi_main`）
- **类型**：处理过长 Cookie（`uid=`）时发生**栈溢出**，可导致远程代码执行
- **来源**：D-Link DIR-645 的公开漏洞报告，同一套 cgibin 代码也存在于 DIR-300/600/815
- **前置条件**：只处理 `POST` 请求；该接口通常**无需认证**（以实测为准）

DIR-815 在 opencve 上收录了十多个 CVE，若毕设需要一个明确编号，
建议从中挑一个再回填到本 README 的标题与 `vuln_list.md`（见文末 TODO）。

## 3. 目录结构

```
D-Link/DIR-815/
├── README.md                      # 本文件
├── firmware/                      # 放固件(不入库)
├── init_env.sh                    # 探测架构 + 生成 .env + 软链 squashfs-root
├── docker-compose-firmae.yml      # 方式 A:FirmAE(推荐)
├── firmae/{Dockerfile,run.sh}
├── docker-compose-system.yml      # 方式 B:QEMU system 手动全系统
├── system-emu/{Dockerfile,run.sh,images/}
├── docker-compose-user.yml        # 方式 C:QEMU user 单二进制(调试最快)
├── user-emu/{Dockerfile,run.sh}
└── tools/poc_hedwig_cookie.py     # 存在性验证 PoC
```

## 4. 快速开始

### 4.1 放固件

```bash
cd D-Link/DIR-815
cp ~/Downloads/DIR815A1_FW103b01.bin firmware/
sha256sum firmware/DIR815A1_FW103b01.bin   # 记到 firmware/README.md 里
```

### 4.2 解包

用仓库自带的最小 binwalk 镜像，避免污染主机：

```bash
cd baseImage/binwalk && docker build -t iot-vulhub/binwalk .
cd ../../D-Link/DIR-815

docker run --rm -v "$PWD/firmware:/firmware" iot-vulhub/binwalk \
  -Me /firmware/DIR815A1_FW103b01.bin
```

产物形如 `firmware/_DIR815A1_FW103b01.bin.extracted/squashfs-root/`。

### 4.3 初始化

```bash
./init_env.sh
# 输出示例:
#   [*] 固件: firmware/DIR815A1_FW103b01.bin
#   [*] rootfs: firmware/_...extracted/squashfs-root
#   [*] 架构: mipsel
#   [*] 已生成 .env,并软链 squashfs-root
```

`init_env.sh` 做的事：找固件 → 找 `squashfs-root` → 探测架构 → 写 `.env` → 在环境根建
`squashfs-root` 软链（后面所有 compose 都只认这个路径）。

### 4.4 三种仿真方式

| 方式 | 真实度 | 成功率 | 适用 |
|---|---|---|---|
| **A. FirmAE** | 高（全系统 + NVRAM 伪造） | 最高 | 要看 Web 后台、要复现网络层漏洞 |
| **B. QEMU system 手动** | 高 | 中（要自备内核） | 要完全控制启动流程、要换内核调试 |
| **C. QEMU user** | 低（单进程） | 高（不需要网络） | 只调 `cgibin` 一个二进制、复现栈溢出崩溃 |

---

#### 方式 A：FirmAE（推荐先跑这个）

```bash
docker compose -f docker-compose-firmae.yml build     # 首次数 GB,耐心等
docker compose -f docker-compose-firmae.yml run --rm firmae
```

进入容器后：

```bash
cd /opt/FirmAE
./run.sh -r dlink /firmware/DIR815A1_FW103b01.bin     # 启动并仿真
./run.sh -d dlink /firmware/DIR815A1_FW103b01.bin     # 调试模式(保留 console)
./run.sh -c dlink /firmware/DIR815A1_FW103b01.bin     # 清理该固件的运行状态
```

> FirmAE 的参数以[官方 README](https://github.com/pr0cf5/FirmAE) 为准，版本间会有差异。

也可以直接用镜像里的包装脚本（自动取 `/firmware/` 下第一个 bin）：

```bash
firmae-run        # 等价于 ./run.sh -r $BRAND $FW
firmae-run -d     # 调试
```

启动成功后，FirmAE 会在宿主机建 `tap` 设备并配好到 `192.168.0.1` 的路由，
**在 WSL 的 Ubuntu 里直接访问**即可（容器用了 `network_mode: host`）：

```bash
curl -I http://192.168.0.1/
# 浏览器直接开 http://192.168.0.1/
```

默认口令按 D-Link 惯例先试 `admin` + **空密码**，再试 `admin/admin`。

如果宿主机访问不到（tap 没建起来 / 被防火墙拦），退而在容器内操作：

```bash
docker compose -f docker-compose-firmae.yml exec firmae bash -c 'curl -s http://192.168.0.1/ | head'
```

> 原版 IoT-vulhub 用的是"容器内 ssh + `ssh -D 2345` socks 跳板"的隔离做法；
> 这里改成 host 网络直连，少一层代理。需要隔离时把 `network_mode: host`
> 换成 `ports: ["1234:22"]`，再给镜像装上 `openssh-server` 即可。

---

#### 方式 B：QEMU system 手动全系统

这条路线最麻烦，只有在需要自己换内核、自己控制 init 时才用。先准备同架构内核：

```bash
# 把内核/initrd 放到 system-emu/images/,文件名任意,用 KERNEL 指定
ls system-emu/images/
# 例:vmlinux-mipsel.elf  initrd-mipsel
```

```bash
KERNEL=/env/images/vmlinux-mipsel.elf docker compose -f docker-compose-system.yml up --build
```

`system-emu/run.sh` 会用 `mkfs.ext4 -d squashfs-root` 把根文件系统打包成 `rootfs.ext4`，
再以 `malta` 机型启动，并把 80 端口转发到本机 8888。

> 这台路线的坑：内核必须带目标板需要的驱动；固件的 `/etc/init.d` 依赖 NVRAM 和硬件节点，
> 大概率卡在启动脚本。**只想跑起来看 Web 界面的话，直接用方式 A。**

---

#### 方式 C：QEMU user 单二进制（复现崩溃最快）

不需要内核、不需要网络，几秒钟就能把 `cgibin` 跑起来：

```bash
docker compose -f docker-compose-user.yml build
# 正常跑一次
docker compose -f docker-compose-user.yml run --rm -e PAYLOAD="$(python3 -c 'print("A"*1024)')" user-emu
# 挂 gdbserver
docker compose -f docker-compose-user.yml run --rm -e MODE=gdb user-emu   # 监听 6666
# 另开一个终端(注意 --entrypoint,否则会跑镜像默认的 run.sh)
docker run --rm -it --network host --entrypoint gdb-multiarch iot-vulhub/dir815-user:latest \
  -q -ex 'set architecture mips' -ex 'set endian little' \
  -ex 'target remote 127.0.0.1:6666'
```

原理：`hedwig.cgi` 是 `/htdocs/cgibin` 的软链，用 `qemu-<arch>-static -0 /htdocs/web/hedwig.cgi`
伪造 `argv[0]` 让 cgibin 进入 `hedwigcgi_main` 分支，再用 `-E HTTP_COOKIE=uid=AAA...`
把超长 Cookie 喂进去。

## 5. 网络拓扑

```
WSL Ubuntu / 攻击机             docker(host 网络)              固件
──────────────────────────────────────────────────────────────────────
curl / 浏览器 ───────────────────► FirmAE ── tap ──► 192.168.0.1:80

qemu-user(方式 C) ── 纯本地进程,不需要网络;gdbserver 走 :6666
qemu-system(方式 B) ── 80 映射到本机 :8888,ssh 映射到 :2222
```

## 6. 漏洞验证

```bash
# 对已启动的 FirmAE 环境(需要 socks 或直接从容器内访问)
python3 tools/poc_hedwig_cookie.py -u http://192.168.0.1/ -l 1200 --socks 127.0.0.1:2345
```

判定方式：

- 连接被重置 / 无响应 / 服务进程消失 → **溢出已触发**（存在性成立）
- 一直返回 200 且服务稳定 → 长度不够或该固件版本有边界检查，逐步加大 `-l`

完整利用需要在 `hedwigcgi_main` 栈帧里精确覆盖返回地址，配合 ROP 链或
`system()` 调用；这部分脚本里留了 `--payload` 参数供你接入自己的 shellcode。

## 7. 排错

| 现象 | 原因 / 处理 |
|---|---|
| `init_env.sh` 报找不到 squashfs-root | binwalk 没解出来，检查固件是否加密/加了头；试 `binwalk -Me` 后看 `_*.extracted` |
| 架构探测成 `unknown` | 加参数手动指定：`./init_env.sh mipsel` |
| FirmAE 起不来固件 | 换 `-d` 调试模式看 console 输出；常见是 flash 布局与 FirmAE 的 `run.sh` 品牌脚本不匹配 |
| 方式 B 内核 panic | 内核与架构不匹配，或 rootfs 缺 `/dev/console` |
| 方式 C 报 `No such file or directory` | 缺动态链接器，确认 `-L squashfs-root` 且架构参数正确（`mips` vs `mipsel` 搞反最常见） |
| `qemu: uncaught target signal 11` | 正常的段错误，说明溢出打到了；用 gdb 接上去看栈 |

## 8. 参考

- D-Link 固件归档:`ftp.dlink.by/pub/Router/DIR-815/Firmware/RevA/`
- 《从零开始复现 DIR-815 栈溢出漏洞》:`https://zhuanlan.zhihu.com/p/517019827`
- 《D-Link DIR-815 路由器多次溢出分析》:`https://cloud.tencent.cn/developer/article/2483196`
- opencve DIR-815 漏洞列表:`https://app.opencve.io/cve/?vendor=dlink&product=dir-815`
- FirmAE:`https://github.com/pr0cf5/FirmAE`

## 9. TODO（本环境还没做完的部分）

- [ ] 确认固件实际架构（`mips` 还是 `mipsel`）并回填到 `init_env.sh` 的默认值
- [ ] FirmAE 跑通后补启动截图与 `192.168.0.1` 后台截图
- [ ] 给出一条可用的 `hedwig.cgi` ROP 利用链（或至少稳定的崩溃 PoC + 偏移量）
- [ ] 回填一个明确的 CVE 编号
