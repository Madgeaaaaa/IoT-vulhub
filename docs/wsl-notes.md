# WSL2 环境说明

本仓库在 WSL2 的 Ubuntu 里开发，以下是踩过的点。

## 1. 用 systemd

FirmAE 里的 `systemctl`、docker 服务都假设有 systemd。编辑 `/etc/wsl.conf`：

```ini
[boot]
systemd=true

[user]
default=<你的用户名>
```

然后 Windows 侧 `wsl --shutdown`，重进。

## 2. Docker 装在 WSL 里，而不是 Docker Desktop

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"     # 重新登录后生效
sudo systemctl enable --now docker
docker run --rm hello-world
```

> 用 Docker Desktop 的 WSL2 后端也能跑，但镜像存在 Desktop 的 vhdx 里，
> 空间回收更麻烦。本仓库按"docker 直接装在 WSL 发行版里"来写。

## 3. 嵌套虚拟化（方式 B 想加速才需要）

FirmAE 默认走 QEMU TCG（纯软件模拟），不需要 KVM，**能跑但慢**。
想用 KVM，在 `C:\Users\<你>\.wslconfig` 加：

```ini
[wsl2]
nestedVirtualization=true
memory=8GB
```

重启 WSL 后 `ls /dev/kvm` 存在即成功。注意 `nestedVirtualization` 需要 Win11 + 较新 WSL。

## 4. 磁盘：只增不减

WSL 的根文件系统是一个 `ext4.vhdx`，删文件不会自动还空间给 Windows。

```bash
df -h /                       # WSL 里看
docker system df              # 看 docker 占用
docker image prune -a         # 清理
docker builder prune -a
```

回收（先清理，再关机，再压缩）：

```powershell
wsl --shutdown
# WSL 2.0+
wsl --manage Ubuntu --set-sparse true
# 老办法(管理员):diskpart -> select vdisk file="...ext4.vhdx" -> attach vdisk readonly -> compact vdisk -> detach vdisk
```

找 vhdx 路径：

```powershell
Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss |
  ForEach-Object { (Get-ItemProperty $_.PSPath).BasePath }
```

## 5. 别把项目放 /mnt/c

`/mnt/c` 是 9p/drvfs，I/O 慢一个数量级，权限位也不对。
项目放 `~/work/IoT-vulhub`，固件解包产物也留在 ext4 里。

## 6. 内存

全系统仿真每个环境 2–4 GB。16 GB 主机建议在 `.wslconfig` 里 `memory=8GB`，
避免 WSL 把宿主吃满。8 GB 主机建议一次只开一个环境。
