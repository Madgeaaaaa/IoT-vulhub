# IoT-vulhub

IoT 固件漏洞复现环境合集。目录组织参考 [vulhub](https://github.com/vulhub/vulhub) 与
[Vu1nT0tal/IoT-vulhub](https://github.com/Vu1nT0tal/IoT-vulhub)。

目标：为每个固件漏洞提供一个**可重复启动、可调试、可清理**的环境，让复现过程不依赖运气。

## 环境列表

详见 [vuln_list.md](./vuln_list.md)。

| 厂商 | 目标 | 内容 | 状态 |
|---|---|---|---|
| D-Link | DIR-815（Rev B1 / RT3052） | 全系统仿真 + `hedwig.cgi` Cookie 栈溢出验证 | 环境就绪，待跑通 |

## 目录约定

```
IoT-vulhub/
├── baseImage/                    # 通用基础镜像(binwalk 等)
├── docs/                         # 环境搭建笔记
└── <厂商>/<环境名>/
    ├── README.md                 # 说明文档(必填:拓扑、启动方式、验证方法)
    ├── firmware/                 # 固件目录(固件不入库,只放 README)
    ├── init_env.sh               # 探测架构、生成 .env、软链 squashfs-root
    ├── docker-compose-*.yml      # 一种仿真方式一个文件
    ├── firmae/                   # FirmAE 全系统仿真
    ├── system-emu/               # QEMU system 手动全系统
    ├── user-emu/                 # QEMU user 单二进制(调试用)
    └── tools/                    # poc / exp / 辅助脚本
```

新增环境的流程见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 端口约定

所有环境统一，换环境不用重新记端口：

| 用途 | 端口 |
|---|---|
| 固件 Web(80)映射到本机 | 8888 |
| ssh 映射到本机 | 1234 |
| ssh socks 本机代理 | 2345 |
| gdbserver 调试 | 6666 |
| nc 本地监听 | 7777 |
| python3 -m http.server | 8000 |
| msf 反弹 shell | 31337 |
| FirmAE / firmadyne 固件网段 | 192.168.0.0/24 |

## 依赖

- Ubuntu 20.04 / 22.04,或 WSL2（见 [docs/wsl-notes.md](./docs/wsl-notes.md)）
- docker + docker compose v2（`docker compose`,不是老的 `docker-compose`）
- 建议内存 ≥ 16 GB,磁盘可用 ≥ 30 GB（全系统仿真每个环境 2-4 GB 内存）

## 快速开始

```bash
git clone <this-repo>.git && cd IoT-vulhub
cd D-Link/DIR-815
cat README.md          # 按里面的步骤放固件、解包、启动
```

## 免责声明

本项目仅用于**学习、教学与授权范围内的安全测试**。所有固件版权归原厂商所有，
仓库不托管固件本体。请勿将仿真环境暴露在公网，请勿用于未授权目标。
