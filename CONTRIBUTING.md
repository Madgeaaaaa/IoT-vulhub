# 贡献指南

## 新增一个环境

1. 建目录 `<厂商>/<环境名>`，环境名用漏洞编号或功能名，例如 `CVE-2019-17621`、`hedwig-rce`。
2. 按下面的结构补齐文件：

```
<厂商>/<环境名>/
├── README.md                 # 必填
│   ├── 目标设备与固件版本(含获取方式、sha256)
│   ├── 网络拓扑(攻击机 / 固件机 的 IP)
│   ├── 启动步骤(优先 FirmAE,其次 system,最后 user)
│   ├── 漏洞位置与验证方法(附 poc 命令与预期输出)
│   └── 参考链接
├── firmware/README.md        # 说明要放哪个文件,固件本体不入库
├── init_env.sh               # 探测架构 -> 生成 .env -> 软链 squashfs-root
├── docker-compose-firmae.yml
├── firmae/{Dockerfile,run.sh}
└── tools/                    # poc / exp
```

3. 在 [vuln_list.md](./vuln_list.md) 里登记。

## 约定

- 端口一律用根 README 里的约定，不要自创。
- `init_env.sh` 不要硬编码架构，从 `busybox` 或目标 CGI 的 `file` 输出探测。
- 脚本用 `#!/usr/bin/env bash` + `set -euo pipefail`，错误要有可读提示。
- 固件、解包产物、镜像一律 `.gitignore`，仓库里只留说明。

## 提交

```bash
git checkout -b feat/dir815
git add .
git commit -m "feat(dir815): 增加 hedwig.cgi 栈溢出仿真环境"
git push -u origin feat/dir815
```

然后开 PR。
