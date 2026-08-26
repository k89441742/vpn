# 1GB Debian 出口 WireGuard

给内存只有约 1GB、已经在跑 Halo / MySQL / Nginx Proxy Manager 的 Debian 机器用。设备连上后，上网流量从服务器公网 IP 转出。

- 装在**宿主机内核**，不走 Docker，不碰 80 / 443 / 81
- 虚拟网段 `10.7.0.0/24`，服务器 `10.7.0.1`
- 默认生成 `windows`、`phone` 两个客户端

## 在服务器上安装

用 root 登录 Debian（FinalShell 即可）：

```bash
apt-get update && apt-get install -y git
git clone https://github.com/k89441742/vpn.git
cd vpn
chmod +x *.sh
```

### 1. 先给 MySQL 降内存（强烈建议）

这台机大约 975MB 内存、已用近 80%，Swap 已经用一半。不先挤内存，一开转发容易 OOM。

```bash
./trim-mysql.sh
free -h
```

脚本会找正在跑的 MySQL 容器。如果挂了 `/etc/mysql/conf.d`，会写入 `lowmem.cnf` 并重启容器；否则会打印一段 docker compose 的 `command`，你自行改完再 `docker compose up -d`。

默认：`innodb_buffer_pool_size=128M`，关闭 `performance_schema`，`max_connections=50`。

### 2. 安装 WireGuard

```bash
./install.sh
```

可选环境变量：

```bash
ENDPOINT_IP=65.49.199.104 WG_PORT=34782 WAN_IF=eth0 ./install.sh
```

重装（会覆盖现有 `wg0.conf` 和客户端密钥）：

```bash
FORCE=1 ./install.sh
```

装完后：

1. 在**云厂商/机房安全组**放行脚本打印的 **UDP 端口**（本机防火墙若开了 ufw 会自动放行）
2. 把 `/root/wireguard-clients/windows.conf` 拷到电脑
3. 手机扫终端里的二维码，或导入 `phone.conf`

不要把含私钥的 `.conf` 提交到 Git。

### 3. 电脑 / 手机

- Windows / macOS / Android / iOS：官方客户端 [wireguard.com/install](https://www.wireguard.com/install/)
- Windows：导入 `windows.conf`，连接
- 手机：扫码或导入 `phone.conf`

连上后打开 https://ifconfig.me ，应显示服务器公网 IP。服务器上执行 `wg show` 能看到握手和流量。同时确认 Halo 博客、NPM 还在：`docker ps`。

## 再加一台设备

```bash
./add-client.sh laptop
```

会在 `/root/wireguard-clients/laptop.conf` 生成配置，并打印二维码。每台设备必须用自己的配置，不要两台机器共用一份。

## 常用命令

```bash
wg show
systemctl status wg-quick@wg0
systemctl restart wg-quick@wg0
journalctl -u wg-quick@wg0 -e
```

连不上时：

- 安全组 / 防火墙有没有放行 **UDP**（不是 TCP）
- `Endpoint` 是否为当前公网 IP 和端口
- 部分网络拦 UDP，可换端口：`FORCE=1 WG_PORT=新端口 ./install.sh` 后重新导入客户端
- 握手成功但网页打不开：把客户端 `MTU` 改成 `1280` 再连

## 目录说明

| 文件 | 作用 |
| --- | --- |
| `trim-mysql.sh` | 降低 MySQL 8 内存 |
| `install.sh` | 安装 WireGuard，生成 windows / phone |
| `add-client.sh` | 再加一台设备 |
| `examples/` | 配置样例（占位符，不能直接用） |

服务器上的真实文件：

- `/etc/wireguard/wg0.conf`
- `/etc/wireguard/vpn.env`
- `/root/wireguard-clients/*.conf`
