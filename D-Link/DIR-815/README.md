# D-Link DIR-815 固件仿真环境

## 1. 目标设备

| 项目 | 内容 |
|---|---|
| 型号 | D-Link DIR-815（**Rev B1**） |
| 硬件平台 | Ralink **RT3052**（MIPS 24KEc，小端） |
| 固件 | `DIR815_revB_FW_V2.02b01.bin`（4,591,760 B） |
| sha256 | `faaf6c614e615d25be93706195a33b059a23a26192c620d01ef09ede6828d638` |
| 内核 | Linux 2.6.33.2 / gcc 4.3.3 / 2010-10-11 |
| 根文件系统 | squashfs 4.0，**LZMA** 压缩，64 KB 块，1873 inode |
| 架构判定 | 按 `mipsel` 处理；**最终以解包后 `file htdocs/cgibin` 为准** |

> DIR-815 有多个硬件版本，固件**互不通用**：
>
> | 版本 | 芯片 | 固件头签名 |
> |---|---|---|
> | Rev A1 | Ralink RT3662 | `...dir815a1` |
> | **Rev B1（本环境）** | Ralink RT3052 | `signature=wrgnd12_dlob.hans_dir815b` |
> | Rev E / S / R | Realtek RT8197F/G | 另一套 SDK |
>
> 详细解析见 [docs/firmware-notes.md](../../docs/firmware-notes.md)。

## 2. 已知漏洞线索

- **位置**：`/htdocs/web/hedwig.cgi`（通常是 `/htdocs/cgibin` 的软链，入口
  `hedwigcgi_main`）
- **类型**：处理过长 Cookie（`uid=`）时发生**栈溢出**，可导致远程代码执行
- **来源**：D-Link DIR-645 的公开报告，同一套 `cgibin` 也存在于 DIR-300/600/815
- **前置条件**：只处理 `POST`；该接口通常无需认证（以实测为准）

> ⚠️ 这条线索来自 DIR-645/A1 系列的研究，**B 版固件的 `cgibin` 需要你自己确认**
> 是否同样存在：解包后看 `htdocs/web/hedwig.cgi` 在不在、`cgibin` 里有没有
> `hedwigcgi_main` 这个符号（`strings` 或 IDA/Ghidra 都行）。

## 3. 目录结构

```
D-Link/DIR-815/
├── README.md                      # 本文件
├── firmware/                      # 放固件(不入库)
├── init_env.sh                    # 探测架构 + 生成 .env + 软链 squashfs-root
├── tools/unpack.sh                # 解包(LZMA squashfs 需要特殊处理)
├── tools/poc_hedwig_cookie.py     # 存在性验证 PoC
├── docker-compose-firmae.yml      # 方式 A:FirmAE(推荐)
├── firmae/{Dockerfile,run.sh}
├── docker-compose-system.yml      # 方式 B:QEMU system(本固件不适用,见下)
├── system-emu/{Dockerfile,run.sh,images/}
└── docker-compose-user.yml        # 方式 C:QEMU user 单二进制(调试最快)
    user-emu/{Dockerfile,run.sh}
```

## 4. 快速开始

### 4.1 放固件

```bash
cd D-Link/DIR-815
cp "/d/资料/fuzz/固件/firmware/D-Link/DIR-815/DIR815_revB_FW_V2.02b01.bin" firmware/
sha256sum firmware/*.bin
```

### 4.2 解包（⚠️ 这个固件是 LZMA squashfs，普通 unsquashfs 解不开）

`binwalk` 能识别出 squashfs 4.0，但压缩算法是 **LZMA（id=2）**，Ubuntu 自带的
`unsquashfs` 会报 `Unsupported compression type 2`。仓库提供了三种走法，
`tools/unpack.sh` 会自动按顺序尝试：

```bash
cd baseImage/binwalk && docker build -t iot-vulhub/binwalk .
cd ../../D-Link/DIR-815
./tools/unpack.sh
```

脚本的尝试顺序：

1. `binwalk -Me`（如果你的环境里已经有 sasquatch，直接就成）
2. 定位 squashfs 偏移 → `dd` 切出来 → `7z x`（p7zip 支持 LZMA squashfs）
3. 都失败时提示装 sasquatch，或者改用 FirmAE 容器里自带的 binwalk

手工版（第 2 条）：

```bash
# 找偏移
binwalk firmware/DIR815_revB_FW_V2.02b01.bin | grep -i squashfs
# 本例是 0x140090
dd if=firmware/DIR815_revB_FW_V2.02b01.bin of=root.sqsh bs=1 skip=$((0x140090))
7z x root.sqsh -orootfs
```

成功后会得到 `squashfs-root/`，确认里面有：

```bash
ls squashfs-root/htdocs/cgibin
file squashfs-root/htdocs/cgibin      # 期望:ELF 32-bit LSB executable, MIPS
```

### 4.3 初始化

```bash
./init_env.sh
#   [*] 固件: firmware/DIR815_revB_FW_V2.02b01.bin
#   [*] rootfs: firmware/_...extracted/squashfs-root
#   [*] 架构探测: mipsel  (来自 /htdocs/cgibin)
#   [*] 已写入 .env (ARCH=mipsel)
#   [*] 已创建软链 squashfs-root
```

### 4.4 三种仿真方式

| 方式 | 真实度 | 本固件可行性 | 适用 |
|---|---|---|---|
| **A. FirmAE** | 高（全系统 + NVRAM 伪造） | ✅ 推荐 | 要看 Web 后台、复现网络层漏洞 |
| B. QEMU system 手动 | 高 | ❌ **基本不可行** | 需要通用 mipsel 内核时才考虑 |
| **C. QEMU user** | 低（单进程） | ✅ 最适合调栈溢出 | 只调 `cgibin`、复现崩溃、gdb |

> **为什么方式 B 不适用**：能提取到的是 Ralink 板级内核（2.6.33.2，带 RT3052 板级
> 代码），它需要真实的 RT3052 硬件描述，在 QEMU 的 `malta` 机型上起不来。
> 想要全系统仿真就老老实实用 FirmAE。

---

#### 方式 A：FirmAE（推荐）

```bash
docker compose -f docker-compose-firmae.yml build     # 首次数 GB
docker compose -f docker-compose-firmae.yml run --rm firmae
```

进入容器后：

```bash
cd /opt/FirmAE
./run.sh -r dlink /firmware/DIR815_revB_FW_V2.02b01.bin   # 启动仿真
./run.sh -d dlink /firmware/DIR815_revB_FW_V2.02b01.bin   # 调试模式(保留 console)
./run.sh -c dlink /firmware/DIR815_revB_FW_V2.02b01.bin   # 清理
```

或用镜像里的包装脚本（自动取 `/firmware/` 下第一个 bin）：

```bash
firmae-run        # 等价于 ./run.sh -r $BRAND $FW
firmae-run -d     # 调试
```

启动成功后 FirmAE 会在宿主机建 `tap` 设备并配好路由（compose 用了
`network_mode: host`），直接在 WSL 里访问：

```bash
curl -I http://192.168.0.1/
```

默认口令先试 `admin` + **空密码**，再试 `admin/admin`。

如果访问不到，退到容器内：

```bash
docker compose -f docker-compose-firmae.yml exec firmae bash -c 'curl -s http://192.168.0.1/ | head'
```

> 顺便：FirmAE 自己的 `binaries/binwalk` 自带 sasquatch，**也能用来解包本固件**，
> 解包失败时可以在 firmae 容器里试。

---

#### 方式 C：QEMU user 单二进制（复现崩溃最快）

不需要内核、不需要网络：

```bash
docker compose -f docker-compose-user.yml build

# 正常跑一次
docker compose -f docker-compose-user.yml run --rm \
  -e PAYLOAD="$(python3 -c 'print("A"*1024)')" user-emu

# 挂 gdbserver
docker compose -f docker-compose-user.yml run --rm -e MODE=gdb user-emu
# 另开终端(注意 --entrypoint)
docker run --rm -it --network host --entrypoint gdb-multiarch iot-vulhub/dir815-user:latest \
  -q -ex 'set architecture mips' -ex 'set endian little' \
  -ex 'target remote 127.0.0.1:6666'
```

原理：`hedwig.cgi` 是 `/htdocs/cgibin` 的软链，用 `qemu-<arch>-static -0
/htdocs/web/hedwig.cgi` 伪造 `argv[0]` 让 cgibin 进入 `hedwigcgi_main` 分支，
再用 `-E HTTP_COOKIE=uid=AAA...` 把超长 Cookie 喂进去。

## 5. 网络拓扑

```
WSL Ubuntu / 攻击机             docker(host 网络)              固件
──────────────────────────────────────────────────────────────────────
curl / 浏览器 ───────────────────► FirmAE ── tap ──► 192.168.0.1:80

qemu-user(方式 C) ── 纯本地进程,不需要网络;gdbserver :6666
```

## 6. 漏洞验证

```bash
python3 tools/poc_hedwig_cookie.py -u http://192.168.0.1/ --sweep 32:2048:32
```

判定：

- `RESET` / `HANG` → **溢出已触发**（存在性成立）
- 全程 `ALIVE` → 长度不够 / 该版本已修 / Cookie 名不对

完整利用要在 `hedwigcgi_main` 的栈帧里精确覆盖返回地址；脚本留了 `--length`
和 `PAYLOAD` 接口供你接入自己的 ROP 链。

## 7. 排错

| 现象 | 原因 / 处理 |
|---|---|
| `unsquashfs: Unsupported compression type 2` | 本固件是 LZMA squashfs，用 `tools/unpack.sh` 或 sasquatch/7z |
| `init_env.sh` 报找不到 squashfs-root | 解包失败，见 4.2；或 binwalk 只识别未提取 |
| 架构探测成 `unknown` | `./init_env.sh mipsel` 手动指定 |
| FirmAE 起不来 | 换 `-d` 看 console；RT3052 属于常见平台，多半是品牌脚本参数问题 |
| 方式 C 报 `No such file or directory` | 缺动态链接器：确认 `-L` 指向 rootfs 且 `ARCH` 没把 mips/mipsel 搞反 |
| `qemu: uncaught target signal 11` | 正常段错误，说明打到了；用 gdb 接上去看栈 |

## 8. 参考

- 固件解析记录：[docs/firmware-notes.md](../../docs/firmware-notes.md)
- 《从零开始复现 DIR-815 栈溢出漏洞》：`https://zhuanlan.zhihu.com/p/517019827`
- 《D-Link DIR-815 路由器多次溢出分析》：`https://cloud.tencent.cn/developer/article/2483196`
- opencve DIR-815：`https://app.opencve.io/cve/?vendor=dlink&product=dir-815`
- FirmAE：`https://github.com/pr0cf5/FirmAE`

## 9. TODO

- [x] 确认固件版本与架构（Rev B1 / RT3052 / LZMA squashfs）
- [ ] 解包后确认 `htdocs/web/hedwig.cgi` 与 `hedwigcgi_main` 是否存在于 B 版
- [ ] FirmAE 跑通后补启动截图与后台截图
- [ ] 给出一条可用的 ROP 链（或至少稳定的崩溃 PoC + 偏移）
