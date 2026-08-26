#!/usr/bin/env bash
# 给 1GB 机器上的 MySQL 8 容器降内存。
# 默认：innodb_buffer_pool_size=128M，关掉 performance_schema。
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "请用 root 运行：$0"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker，退出。"
  exit 1
fi

POOL_SIZE="${POOL_SIZE:-128M}"
CID="$(docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | awk '/mysql/ {print $1; exit}')"

if [[ -z "${CID}" ]]; then
  echo "没有正在运行的 MySQL 容器。"
  exit 1
fi

NAME="$(docker inspect -f '{{.Name}}' "${CID}" | sed 's#^/##')"
IMAGE="$(docker inspect -f '{{.Config.Image}}' "${CID}")"
echo "容器：${NAME}  (${CID:0:12}  ${IMAGE})"

ROOT_PASS="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${CID}" | awk -F= '/^MYSQL_ROOT_PASSWORD=/{print $2; exit}')"

if [[ -n "${ROOT_PASS}" ]]; then
  echo "当前 innodb_buffer_pool_size："
  docker exec "${CID}" mysql -uroot -p"${ROOT_PASS}" -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null || true
  echo "当前 performance_schema："
  docker exec "${CID}" mysql -uroot -p"${ROOT_PASS}" -N -e "SHOW VARIABLES LIKE 'performance_schema';" 2>/dev/null || true
else
  echo "容器环境变量里没有 MYSQL_ROOT_PASSWORD，跳过查询。"
fi

CNF_BODY="$(cat <<EOF
[mysqld]
innodb_buffer_pool_size=${POOL_SIZE}
performance_schema=OFF
max_connections=50
innodb_flush_method=O_DIRECT
EOF
)"

CONF_MOUNT="$(docker inspect -f '{{range .Mounts}}{{println .Destination " " .Source}}{{end}}' "${CID}" | awk '$1 ~ /\/etc\/mysql(\/conf.d)?$/ {print $2; exit}')"

if [[ -n "${CONF_MOUNT}" && -d "${CONF_MOUNT}" ]]; then
  TARGET="${CONF_MOUNT}/lowmem.cnf"
  echo "${CNF_BODY}" > "${TARGET}"
  echo "已写入 ${TARGET}"
  echo "重启容器以使配置生效……"
  docker restart "${CID}"
  sleep 5
  if [[ -n "${ROOT_PASS}" ]]; then
    echo "重启后 innodb_buffer_pool_size："
    docker exec "${CID}" mysql -uroot -p"${ROOT_PASS}" -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null || true
  fi
  echo "完成。用 free -h 看一下内存。"
  exit 0
fi

echo
echo "这个 MySQL 容器没有挂载 /etc/mysql/conf.d，不能直接改文件。"
echo "如果你用 docker compose，在 mysql 服务里加上 command 后执行 docker compose up -d："
echo
cat <<EOF
    command:
      - --innodb_buffer_pool_size=${POOL_SIZE}
      - --performance_schema=OFF
      - --max_connections=50
EOF
echo
echo "数据目录必须有 named volume 或 bind mount，否则重建容器会丢库。"
echo "改完后：free -h && docker ps"
