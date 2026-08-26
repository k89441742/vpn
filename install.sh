#!/usr/bin/env bash
# 在 Debian 宿主机安装内核 WireGuard，作为出口网关。
# 默认创建 windows、phone 两个客户端。
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "请用 root 运行：$0"
  exit 1
fi

WG_DIR="/etc/wireguard"
CLIENT_DIR="${CLIENT_DIR:-/root/wireguard-clients}"
WG_NET="${WG_NET:-10.7.0.0/24}"
WG_SERVER_IP="${WG_SERVER_IP:-10.7.0.1}"
DNS="${DNS:-1.1.1.1, 8.8.8.8}"
MTU="${MTU:-1420}"

if [[ -f "${WG_DIR}/wg0.conf" && "${FORCE:-0}" != "1" ]]; then
  echo "${WG_DIR}/wg0.conf 已存在。若要重装：FORCE=1 $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wireguard qrencode curl iproute2 iptables

WAN_IF="${WAN_IF:-$(ip -o -4 route show to default | awk '{print $5}' | head -n1)}"
if [[ -z "${WAN_IF}" ]]; then
  echo "找不到默认出口网卡。请设置 WAN_IF=eth0 再运行。"
  exit 1
fi

ENDPOINT_IP="${ENDPOINT_IP:-$(curl -4 -fsS --max-time 8 https://ifconfig.me || true)}"
if [[ -z "${ENDPOINT_IP}" ]]; then
  ENDPOINT_IP="${ENDPOINT_IP:-$(curl -4 -fsS --max-time 8 https://api.ipify.org || true)}"
fi
if [[ -z "${ENDPOINT_IP}" ]]; then
  ENDPOINT_IP="65.49.199.104"
  echo "无法自动探测公网 IP，使用 ${ENDPOINT_IP}。不对的话请设置 ENDPOINT_IP=x.x.x.x 再运行。"
fi

if [[ -z "${WG_PORT:-}" ]]; then
  WG_PORT="$((30000 + RANDOM % 10000))"
fi

mkdir -p "${WG_DIR}" "${CLIENT_DIR}"
chmod 700 "${WG_DIR}" "${CLIENT_DIR}"
umask 077

if [[ "${FORCE:-0}" == "1" ]]; then
  systemctl disable --now wg-quick@wg0 2>/dev/null || true
  ip link delete wg0 2>/dev/null || true
fi

SERVER_PRIV="$(wg genkey)"
SERVER_PUB="$(printf '%s\n' "${SERVER_PRIV}" | wg pubkey)"

cat > /etc/sysctl.d/99-wireguard.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
EOF
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null

cat > "${WG_DIR}/vpn.env" <<EOF
WG_DIR=${WG_DIR}
CLIENT_DIR=${CLIENT_DIR}
WAN_IF=${WAN_IF}
ENDPOINT_IP=${ENDPOINT_IP}
WG_PORT=${WG_PORT}
WG_SERVER_IP=${WG_SERVER_IP}
WG_NET=${WG_NET}
SERVER_PUB=${SERVER_PUB}
DNS="${DNS}"
MTU=${MTU}
EOF
chmod 600 "${WG_DIR}/vpn.env"

cat > "${WG_DIR}/wg0.conf" <<EOF
[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}
PostUp = iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT
EOF
chmod 600 "${WG_DIR}/wg0.conf"

add_one_client() {
  local name="$1"
  local octet="$2"
  local priv pub addr

  priv="$(wg genkey)"
  pub="$(printf '%s\n' "${priv}" | wg pubkey)"
  addr="10.7.0.${octet}"

  cat >> "${WG_DIR}/wg0.conf" <<EOF

[Peer]
# ${name}
PublicKey = ${pub}
AllowedIPs = ${addr}/32
EOF

  cat > "${CLIENT_DIR}/${name}.conf" <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${addr}/24
DNS = ${DNS}
MTU = ${MTU}

[Peer]
PublicKey = ${SERVER_PUB}
AllowedIPs = 0.0.0.0/0
Endpoint = ${ENDPOINT_IP}:${WG_PORT}
PersistentKeepalive = 25
EOF
  chmod 600 "${CLIENT_DIR}/${name}.conf"
  echo "客户端 ${name} -> ${addr}  文件：${CLIENT_DIR}/${name}.conf"
}

add_one_client windows 2
add_one_client phone 3

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow "${WG_PORT}/udp" comment 'wireguard' || true
fi

systemctl enable --now wg-quick@wg0

echo
echo "========== 安装完成 =========="
echo "公网 Endpoint : ${ENDPOINT_IP}:${WG_PORT}  (UDP)"
echo "出口网卡      : ${WAN_IF}"
echo "虚拟网段      : ${WG_NET}  服务器 ${WG_SERVER_IP}"
echo "客户端配置    : ${CLIENT_DIR}/"
echo
echo "请在机房/云厂商安全组放行 UDP ${WG_PORT}。"
echo "Windows：安装官方客户端后导入 ${CLIENT_DIR}/windows.conf"
echo "手机：用 WireGuard 扫下面二维码（或导入 phone.conf）"
echo
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ansiutf8 < "${CLIENT_DIR}/phone.conf"
fi
echo
echo "检查：wg show"
echo "本机状态：systemctl status wg-quick@wg0 --no-pager"
echo "加设备：./add-client.sh 设备名"
