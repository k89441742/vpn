#!/usr/bin/env bash
# 给已安装的 WireGuard 增加一台设备。
# 用法：./add-client.sh 设备名
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "请用 root 运行：$0 设备名"
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "用法：$0 设备名"
  echo "例如：$0 laptop"
  exit 1
fi

NAME="$1"
if [[ ! "${NAME}" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "设备名只能包含字母、数字、下划线和短横线。"
  exit 1
fi

if [[ ! -f /etc/wireguard/vpn.env ]]; then
  echo "未找到 /etc/wireguard/vpn.env，请先运行 ./install.sh"
  exit 1
fi

# shellcheck disable=SC1091
source /etc/wireguard/vpn.env

CONF="${CLIENT_DIR}/${NAME}.conf"
if [[ -f "${CONF}" ]]; then
  echo "客户端 ${NAME} 已存在：${CONF}"
  exit 1
fi

NEXT=""
for i in $(seq 2 254); do
  if ! grep -qE "10\\.7\\.0\\.${i}(/32)?" "${WG_DIR}/wg0.conf"; then
    NEXT="${i}"
    break
  fi
done

if [[ -z "${NEXT}" ]]; then
  echo "10.7.0.0/24 地址已用完。"
  exit 1
fi

umask 077
PRIV="$(wg genkey)"
PUB="$(printf '%s\n' "${PRIV}" | wg pubkey)"
ADDR="10.7.0.${NEXT}"

cat >> "${WG_DIR}/wg0.conf" <<EOF

[Peer]
# ${NAME}
PublicKey = ${PUB}
AllowedIPs = ${ADDR}/32
EOF

cat > "${CONF}" <<EOF
[Interface]
PrivateKey = ${PRIV}
Address = ${ADDR}/24
DNS = ${DNS}
MTU = ${MTU}

[Peer]
PublicKey = ${SERVER_PUB}
AllowedIPs = 0.0.0.0/0
Endpoint = ${ENDPOINT_IP}:${WG_PORT}
PersistentKeepalive = 25
EOF
chmod 600 "${CONF}"

if ip link show wg0 >/dev/null 2>&1; then
  wg syncconf wg0 <(wg-quick strip wg0)
else
  systemctl start wg-quick@wg0
fi

echo "已添加 ${NAME} -> ${ADDR}"
echo "配置文件：${CONF}"
echo
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ansiutf8 < "${CONF}"
fi
