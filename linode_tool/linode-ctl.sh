#!/bin/bash
# Linode 节点管理脚本
# 依赖：curl, jq, ssh, sshpass, openssl
# 使用前设置：export LINODE_API_KEY=your_api_key_here

set -euo pipefail

API="https://api.linode.com/v4"
NODES_FILE="$(dirname "$0")/nodes.json"
SELF="bash linode-ctl.sh"
PLAN="g6-nanode-1"
IMAGE="linode/ubuntu24.04"
FIREWALL_ID="${LINODE_FIREWALL_ID:-14171990}"  # 默认防火墙 ID，可用环境变量覆盖
SSH_PORT="${LINODE_SSH_PORT:-42915}"  # 自定义 SSH 端口，避免 22 被扫描

# ──────────────────────────────────────────────
# 工具函数
# ──────────────────────────────────────────────

check_deps() {
  local install_hints
  declare -A install_hints=(
    [curl]="apt install curl              / yum install curl                    / brew install curl"
    [jq]="apt install jq                 / yum install jq                      / brew install jq"
    [ssh]="apt install openssh-client    / yum install openssh-clients         / brew install openssh"
    [sshpass]="apt install sshpass         / yum install sshpass                 / brew install hudochenkov/sshpass/sshpass"
    [openssl]="apt install openssl          / yum install openssl                 / brew install openssl"
  )
  local missing=0
  for cmd in curl jq ssh sshpass openssl; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "错误：缺少依赖 $cmd" >&2
      echo "  Ubuntu/Debian: ${install_hints[$cmd]%% /*}" >&2
      local rest="${install_hints[$cmd]#*/ }"
      echo "  CentOS/RHEL:   ${rest%% /*}" >&2
      echo "  macOS:         ${install_hints[$cmd]##*/ }" >&2
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1
}

check_api_key() {
  if [[ -z "${LINODE_API_KEY:-}" ]]; then
    echo "错误：未设置 LINODE_API_KEY，请先执行：export LINODE_API_KEY=your_api_key_here" >&2
    exit 1
  fi
}

linode_get() {
  curl -sS -H "Authorization: Bearer $LINODE_API_KEY" "$API$1"
}

linode_post() {
  curl -sS -X POST \
    -H "Authorization: Bearer $LINODE_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$2" \
    "$API$1"
}

linode_delete() {
  curl -sS -X DELETE \
    -H "Authorization: Bearer $LINODE_API_KEY" \
    "$API$1"
}

# 生成随机密码（16字符，含大小写+数字+特殊字符）
generate_password() {
  printf '%s!A1\n' "$(openssl rand -base64 16 | tr -d '=+/' | head -c 20)"
}

# 初始化 nodes.json
init_nodes_file() {
  if [[ ! -f "$NODES_FILE" ]]; then
    echo "[]" > "$NODES_FILE"
  fi
}

# 追加节点记录
save_node() {
  local id="$1" ip="$2" password="$3" region="$4"
  init_nodes_file
  local updated
  updated=$(jq --arg id "$id" --arg ip "$ip" --arg pw "$password" \
               --arg region "$region" --arg date "$(date +%Y-%m-%d)" \
    '. + [{"id": $id, "ip": $ip, "password": $pw, "region": $region, "created": $date}]' \
    "$NODES_FILE")
  echo "$updated" > "$NODES_FILE"
  echo "节点信息已保存到 $NODES_FILE"
}

# 从 nodes.json 中删除节点记录
remove_node() {
  local id="$1"
  init_nodes_file
  local updated
  updated=$(jq --arg id "$id" '[.[] | select(.id != $id)]' "$NODES_FILE")
  echo "$updated" > "$NODES_FILE"
}

# ──────────────────────────────────────────────
# 查询可用 region 列表
# ──────────────────────────────────────────────

cmd_regions() {
  echo "可用区域列表："
  linode_get "/regions" | jq -r '.data[] | "\(.id)\t\(.label)"' | sort
}

cmd_firewalls() {
  echo "防火墙列表："
  linode_get "/networking/firewalls" | jq -r '.data[] | "\(.id)\t\(.label)\tstatus=\(.status)\tlinodes=\((.entities // []) | length)"' | sort
}

# ──────────────────────────────────────────────
# 列出当前实例
# ──────────────────────────────────────────────

cmd_list() {
  echo "=== Linode 实例列表 ==="
  local result
  result=$(linode_get "/linode/instances")
  local count
  count=$(echo "$result" | jq '.data | length')
  if [[ "$count" -eq 0 ]]; then
    echo "（无实例）"
  else
    echo "$result" | jq -r '.data[] | "\(.id)\t\(.ipv4[0])\t\(.region)\t\(.status)\t\(.label)"' | \
      awk 'BEGIN{printf "%-10s %-16s %-12s %-12s %s\n","ID","IP","Region","Status","Label"} \
           {printf "%-10s %-16s %-12s %-12s %s\n",$1,$2,$3,$4,$5}'
  fi

  echo ""
  echo "=== 已保存的节点密码 ==="
  init_nodes_file
  local saved_count
  saved_count=$(jq length "$NODES_FILE")
  if [[ "$saved_count" -eq 0 ]]; then
    echo "（无保存记录）"
  else
    jq -r '.[] | "\(.id)\t\(.ip)\t\(.password)\t\(.region)\t\(.created)"' "$NODES_FILE" | \
      awk 'BEGIN{printf "%-10s %-16s %-22s %-12s %s\n","ID","IP","Password","Region","Created"} \
           {printf "%-10s %-16s %-22s %-12s %s\n",$1,$2,$3,$4,$5}'
  fi
}

# ──────────────────────────────────────────────
# 创建实例
# ──────────────────────────────────────────────

cmd_create() {
  local region="${1:-sg-sin-2}"
  check_api_key
  echo "使用防火墙 ID: $FIREWALL_ID"

  # 从 ../docker 目录读取文件内容
  local docker_dir
  docker_dir="$(cd "$(dirname "$0")/../docker" && pwd)"
  for f in Dockerfile docker-compose.yml entrypoint.sh; do
    if [[ ! -f "$docker_dir/$f" ]]; then
      echo "错误：找不到 $docker_dir/$f，请确保 docker 目录与 linode_tool 目录同级" >&2
      exit 1
    fi
  done
  local dockerfile_content compose_content entrypoint_content
  dockerfile_content=$(tr -d '\r' < "$docker_dir/Dockerfile")
  compose_content=$(tr -d '\r' < "$docker_dir/docker-compose.yml")
  entrypoint_content=$(tr -d '\r' < "$docker_dir/entrypoint.sh")

  # 拼接 cloud-init 脚本
  local user_data_script="#!/bin/bash
set -e

sleep 10

ufw allow ${SSH_PORT}/tcp
ufw allow 443/tcp

# 先修改 SSH 端口。只有确认 ${SSH_PORT} 已监听且 22 不再监听，才继续后续部署。
mkdir -p /run/sshd
if grep -qE '^[#[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config; then
  sed -i \"s/^[#[:space:]]*Port[[:space:]].*/Port ${SSH_PORT}/\" /etc/ssh/sshd_config
else
  echo \"Port ${SSH_PORT}\" >> /etc/ssh/sshd_config
fi
/usr/sbin/sshd -t

systemctl daemon-reload
systemctl disable --now ssh.socket || true
systemctl enable ssh.service
systemctl restart ssh.service

for i in {1..10}; do
  if ss -ltn \"( sport = :${SSH_PORT} )\" | grep -q \":${SSH_PORT}\"; then
    break
  fi
  sleep 1
done

if ! ss -ltn \"( sport = :${SSH_PORT} )\" | grep -q \":${SSH_PORT}\"; then
  echo \"ERROR: SSH is not listening on ${SSH_PORT}; stop cloud-init before deployment\" >&2
  systemctl status ssh.service --no-pager >&2 || true
  exit 1
fi

if ss -ltn \"( sport = :22 )\" | grep -q ':22'; then
  echo \"ERROR: SSH is still listening on 22; stop cloud-init before deployment\" >&2
  ss -ltnp >&2 || true
  exit 1
fi

ufw delete allow 22/tcp || true

# 开启 BBR
echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
sysctl -p

curl -fsSL https://get.docker.com | bash

mkdir -p /root/xray/docker
cd /root/xray/docker

cat > Dockerfile <<'DOCKERFILE_END'
${dockerfile_content}
DOCKERFILE_END

cat > docker-compose.yml <<'COMPOSE_END'
${compose_content}
COMPOSE_END

cat > entrypoint.sh <<'ENTRYPOINT_END'
${entrypoint_content}
ENTRYPOINT_END

chmod +x entrypoint.sh
sed -i 's/\r$//' Dockerfile docker-compose.yml entrypoint.sh

docker compose up -d --build

sleep 30
docker compose logs 2>/dev/null | grep 'vless://' | tail -1 > /root/vless_url.txt
"

  local user_data_b64
  user_data_b64=$(printf '%s' "$user_data_script" | base64 -w 0)

  # 生成随机密码
  local root_pass
  root_pass=$(generate_password)
  local firewall_id
  firewall_id="${FIREWALL_ID:--1}"

  local label="reality-${region}-$(date +%Y%m%d%H%M)"
  echo "正在创建实例（region=$region, plan=$PLAN, label=$label）..."

  local response
  response=$(linode_post "/linode/instances" "{
    \"region\": \"$region\",
    \"type\": \"$PLAN\",
    \"image\": \"$IMAGE\",
    \"label\": \"$label\",
    \"root_pass\": \"$root_pass\",
    \"interface_generation\": \"linode\",
    \"interfaces\": [{
      \"firewall_id\": $firewall_id,
      \"public\": {}
    }],
    \"disk_encryption\": \"enabled\",
    \"maintenance_policy\": \"linode/migrate\",
    \"backups_enabled\": false,
    \"booted\": true,
    \"metadata\": {
      \"user_data\": \"$user_data_b64\"
    }
  }")

  local instance_id main_ip
  instance_id=$(echo "$response" | jq -r '.id // empty')
  if [[ -z "$instance_id" ]]; then
    echo "创建失败，API 响应：" >&2
    echo "$response" | jq . >&2
    exit 1
  fi

  main_ip=$(echo "$response" | jq -r '.ipv4[0] // "pending"')

  echo "实例已提交创建："
  echo "  ID     : $instance_id"
  echo "  Region : $region"
  echo "  密码   : $root_pass"
  echo ""
  echo "等待实例启动（通常 1-3 分钟，最多等待 5 分钟）..."

  # 轮询等待 status=running 且 IP 分配完成
  local wait=0
  local status
  while true; do
    sleep 15
    wait=$((wait + 15))
    local info
    info=$(linode_get "/linode/instances/$instance_id")
    status=$(echo "$info" | jq -r '.status')
    main_ip=$(echo "$info" | jq -r '.ipv4[0]')
    echo "  [${wait}s] status=$status ip=$main_ip"
    if [[ "$status" == "running" && "$main_ip" != "null" && "$main_ip" != "" ]]; then
      break
    fi
    if [[ $wait -ge 300 ]]; then
      echo "等待超时，实例可能仍在初始化，请稍后手动执行 '$SELF url $instance_id'" >&2
      break
    fi
  done

  save_node "$instance_id" "$main_ip" "$root_pass" "$region"

  echo ""
  echo "实例已就绪："
  echo "  ID  : $instance_id"
  echo "  IP  : $main_ip"
  echo "  密码: $root_pass"
  echo ""
  echo "注意：cloud-init 脚本仍在后台运行（安装 Docker + 启动容器约需 3-5 分钟）"
  echo "等待约 5 分钟后执行以下命令获取 vless URL："
  echo "  $SELF url $instance_id"
}

# ──────────────────────────────────────────────
# 获取 vless URL
# ──────────────────────────────────────────────

cmd_url() {
  local instance_id="${1:-}"
  if [[ -z "$instance_id" ]]; then
    echo "用法：$SELF url <instance-id>" >&2
    exit 1
  fi
  if [[ ! "$instance_id" =~ ^[0-9]+$ ]]; then
    echo "错误：url 只接受 Linode 官方实例 ID（数字），请先执行 '$SELF list' 查看 ID。" >&2
    exit 1
  fi

  init_nodes_file
  local ip password
  ip=$(jq -r --arg id "$instance_id" '.[] | select(.id == $id) | .ip' "$NODES_FILE")
  password=$(jq -r --arg id "$instance_id" '.[] | select(.id == $id) | .password' "$NODES_FILE")

  if [[ -z "$ip" || -z "$password" || "$ip" == "null" || "$password" == "null" ]]; then
    echo "错误：nodes.json 中找不到实例 $instance_id 的记录" >&2
    exit 1
  fi

  echo "SSH 连接 $ip:${SSH_PORT} 获取 vless URL..."
  local url
  url=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" \
    root@"$ip" "if [ -s /root/vless_url.txt ]; then cat /root/vless_url.txt; elif [ -d /root/xray/docker ]; then cd /root/xray/docker && docker compose logs 2>/dev/null | grep 'vless://' | tail -1; fi")

  if [[ -z "$url" ]]; then
    echo "暂未获取到 vless URL，容器可能还在初始化，请稍后再试。" >&2
    echo "可手动 SSH 查看：ssh root@$ip -p $SSH_PORT（密码：$password）" >&2
    exit 1
  fi

  echo ""
  echo "=== vless URL ==="
  echo "$url"
  echo "================="
}

# ──────────────────────────────────────────────
# 删除实例
# ──────────────────────────────────────────────

cmd_delete() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    echo "用法：$SELF delete <instance-id>" >&2
    exit 1
  fi

  if [[ ! "$input" =~ ^[0-9]+$ ]]; then
    echo "错误：delete 只接受 Linode 官方实例 ID（数字），请先执行 '$SELF list' 查看 ID。" >&2
    exit 1
  fi
  check_api_key

  echo "即将删除实例：$input"
  read -r -p "确认删除？(y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消。"
    exit 0
  fi

  local response
  response=$(linode_delete "/linode/instances/$input")
  if [[ -n "$response" ]]; then
    echo "删除失败，API 响应：" >&2
    echo "$response" | jq . >&2
    exit 1
  fi

  remove_node "$input"
  echo "实例 $input 已删除，本地记录已移除。"
}

# ──────────────────────────────────────────────
# 帮助
# ──────────────────────────────────────────────

cmd_help() {
  cat <<EOF
Linode Reality 节点管理脚本

用法：
  $SELF <命令> [参数]

命令：
  list                          列出所有实例及保存的密码
  create [region]               创建新实例（默认 sg-sin-2=新加坡2，可用 jp-tyo-3=日本东京3）
  url <instance-id>             获取指定实例的 vless URL
  delete <instance-id>          删除指定实例
  regions                       列出所有可用区域
  firewalls                     列出所有防火墙及 ID

示例：
  $SELF create sg-sin-2        # 在新加坡2创建
  $SELF create jp-tyo-3        # 在日本东京3创建
  $SELF firewalls              # 查看防火墙 ID
  $SELF list
  $SELF url 123456789
  $SELF delete 123456789

环境变量：
  LINODE_API_KEY       API Key（必需，使用 export LINODE_API_KEY=your_api_key_here 设置）
  LINODE_FIREWALL_ID   防火墙 ID（默认 14171990；设为 -1 表示不挂载）
  LINODE_SSH_PORT      SSH 端口（默认 42915）
EOF
}

# ──────────────────────────────────────────────
# 入口
# ──────────────────────────────────────────────

check_deps

case "${1:-help}" in
  list)    check_api_key; cmd_list ;;
  create)  cmd_create "${2:-sg-sin-2}" ;;
  url)     cmd_url "${2:-}" ;;
  delete)  cmd_delete "${2:-}" ;;
  regions) check_api_key; cmd_regions ;;
  firewalls) check_api_key; cmd_firewalls ;;
  help|--help|-h) cmd_help ;;
  *)
    echo "未知命令：$1" >&2
    cmd_help
    exit 1
    ;;
esac
