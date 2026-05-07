#!/bin/bash
# Vultr 节点管理脚本
# 依赖：curl, jq, ssh, sshpass
# 使用前设置：export VULTR_API_KEY=your_api_key_here

set -euo pipefail

API="https://api.vultr.com/v2"
NODES_FILE="$(dirname "$0")/nodes.json"
SELF="bash vultr-ctl.sh"
PLAN="vc2-1c-1gb"
OS_NAME="Ubuntu 24.04 LTS x64"

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
  )
  local missing=0
  for cmd in curl jq ssh sshpass; do
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
  if [[ -z "${VULTR_API_KEY:-}" ]]; then
    echo "未设置 VULTR_API_KEY，请输入（输入时不显示字符）：" >&2
    read -r -s VULTR_API_KEY
    export VULTR_API_KEY
    echo ""
    if [[ -z "$VULTR_API_KEY" ]]; then
      echo "错误：API Key 不能为空" >&2
      exit 1
    fi
  fi
}

vultr_get() {
  curl -s -H "Authorization: Bearer $VULTR_API_KEY" "$API$1"
}

vultr_post() {
  curl -s -X POST \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$2" \
    "$API$1"
}

vultr_delete() {
  curl -s -X DELETE \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "$API$1"
}

# 初始化 nodes.json（不存在时创建空数组）
init_nodes_file() {
  if [[ ! -f "$NODES_FILE" ]]; then
    echo "[]" > "$NODES_FILE"
  fi
}

# 追加节点记录（不覆盖已有记录）
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

# 按 ID、Label 或 IP 反查 instance-id
resolve_instance_id() {
  local input="$1"
  # 如果已经是标准 UUID 格式，直接返回
  if [[ "$input" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "$input"
    return
  fi
  # 否则从 API 列表中按 label 或 IP 查找
  local result
  result=$(vultr_get "/instances" | jq -r --arg q "$input" \
    '.instances[] | select(.label == $q or .main_ip == $q) | .id')
  if [[ -z "$result" ]]; then
    echo "错误：找不到匹配的实例 '$input'（支持 ID / Label / IP）" >&2
    exit 1
  fi
  local count
  count=$(echo "$result" | wc -l)
  if [[ "$count" -gt 1 ]]; then
    echo "错误：'$input' 匹配到多个实例，请使用 ID 指定：" >&2
    echo "$result" >&2
    exit 1
  fi
  echo "$result"
}



get_os_id() {
  vultr_get "/os" | jq -r --arg name "$OS_NAME" \
    '.os[] | select(.name == $name) | .id'
}

# ──────────────────────────────────────────────
# 查询可用 region 列表
# ──────────────────────────────────────────────

cmd_regions() {
  echo "可用区域列表："
  vultr_get "/regions" | jq -r '.regions[] | "\(.id)\t\(.city), \(.country)"' | sort
}

# ──────────────────────────────────────────────
# 列出当前实例
# ──────────────────────────────────────────────

cmd_list() {
  echo "=== Vultr 实例列表 ==="
  local result
  result=$(vultr_get "/instances")
  local count
  count=$(echo "$result" | jq '.instances | length')
  if [[ "$count" -eq 0 ]]; then
    echo "（无实例）"
  else
    echo "$result" | jq -r '.instances[] | "\(.id)\t\(.main_ip)\t\(.region)\t\(.status)\t\(.label)"' | \
      awk 'BEGIN{printf "%-38s %-16s %-8s %-10s %s\n","ID","IP","Region","Status","Label"} \
           {printf "%-38s %-16s %-8s %-10s %s\n",$1,$2,$3,$4,$5}'
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
      awk 'BEGIN{printf "%-38s %-16s %-20s %-8s %s\n","ID","IP","Password","Region","Created"} \
           {printf "%-38s %-16s %-20s %-8s %s\n",$1,$2,$3,$4,$5}'
  fi
}

# ──────────────────────────────────────────────
# 创建实例
# ──────────────────────────────────────────────

cmd_create() {
  local region="${1:-nrt}"
  check_api_key

  echo "查询 Ubuntu 24.04 os_id..."
  local os_id
  os_id=$(get_os_id)
  if [[ -z "$os_id" ]]; then
    echo "错误：未找到 $OS_NAME，请运行 '$SELF regions' 确认区域，或检查 OS 名称。" >&2
    exit 1
  fi
  echo "os_id: $os_id"

  # 从 ../docker 目录读取文件内容（与 docker/entrypoint.sh 等自动同步）
  local docker_dir
  docker_dir="$(cd "$(dirname "$0")/../docker" && pwd)"
  for f in Dockerfile docker-compose.yml entrypoint.sh; do
    if [[ ! -f "$docker_dir/$f" ]]; then
      echo "错误：找不到 $docker_dir/$f，请确保 docker 目录与 vultr_tool 目录同级" >&2
      exit 1
    fi
  done
  local dockerfile_content compose_content entrypoint_content
  dockerfile_content=$(cat "$docker_dir/Dockerfile")
  compose_content=$(cat "$docker_dir/docker-compose.yml")
  entrypoint_content=$(cat "$docker_dir/entrypoint.sh")

  # 拼接完整 cloud-init 脚本（变量插值方式，各部分内容展开后拼成一个字符串）
  local user_data_script="#!/bin/bash
set -e

sleep 10

# 开启 BBR（提升跨境链路利用率）
echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
sysctl -p

curl -fsSL https://get.docker.com | bash

ufw allow 22/tcp
ufw allow 443/tcp

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

docker compose up -d --build

sleep 30
docker compose logs 2>/dev/null | grep 'vless://' | tail -1 > /root/vless_url.txt
"

  local user_data_b64
  user_data_b64=$(printf '%s' "$user_data_script" | base64 -w 0)

  local label="reality-${region}-$(date +%m%d)"
  echo "正在创建实例（region=$region, plan=$PLAN, label=$label）..."
  local response
  response=$(vultr_post "/instances" "{
    \"region\": \"$region\",
    \"plan\": \"$PLAN\",
    \"os_id\": $os_id,
    \"label\": \"$label\",
    \"hostname\": \"$label\",
    \"backups\": \"disabled\",
    \"user_data\": \"$user_data_b64\"
  }")

  local instance_id main_ip password
  instance_id=$(echo "$response" | jq -r '.instance.id // empty')
  if [[ -z "$instance_id" ]]; then
    echo "创建失败，API 响应：" >&2
    echo "$response" | jq . >&2
    exit 1
  fi

  main_ip=$(echo "$response" | jq -r '.instance.main_ip // "pending"')
  password=$(echo "$response" | jq -r '.instance.default_password // ""')

  echo "实例已提交创建："
  echo "  ID       : $instance_id"
  echo "  Region   : $region"
  echo "  密码     : $password"
  echo ""
  echo "等待实例启动（通常 1-3 分钟，最多等待 5 分钟）..."

  # 轮询等待 status=active 且 IP 分配完成
  local wait=0
  local status power
  while true; do
    sleep 15
    wait=$((wait + 15))
    local info
    info=$(vultr_get "/instances/$instance_id")
    status=$(echo "$info" | jq -r '.instance.status')
    main_ip=$(echo "$info" | jq -r '.instance.main_ip')
    power=$(echo "$info" | jq -r '.instance.power_status')
    echo "  [${wait}s] status=$status power=$power ip=$main_ip"
    if [[ "$status" == "active" && "$power" == "running" && "$main_ip" != "0.0.0.0" ]]; then
      break
    fi
    if [[ $wait -ge 300 ]]; then
      echo "等待超时，实例可能仍在初始化，请稍后手动执行 '$SELF url $instance_id'" >&2
      break
    fi
  done

  # 保存节点信息（密码不会丢失，追加写入）
  save_node "$instance_id" "$main_ip" "$password" "$region"

  echo ""
  echo "实例已就绪："
  echo "  ID  : $instance_id"
  echo "  IP  : $main_ip"
  echo "  密码: $password"
  echo ""
  echo "注意：cloud-init 脚本仍在后台运行（安装 Docker + 启动容器约需 3-5 分钟）"
  echo "等待约 5 分钟后执行以下命令获取 vless URL："
  echo "  $SELF url $instance_id"
}

# ──────────────────────────────────────────────
# 获取 vless URL
# ──────────────────────────────────────────────

cmd_url() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    echo "用法：$SELF url <instance-id|label|ip>" >&2
    exit 1
  fi

  local instance_id
  instance_id=$(resolve_instance_id "$input")

  init_nodes_file
  local ip password
  ip=$(jq -r --arg id "$instance_id" '.[] | select(.id == $id) | .ip' "$NODES_FILE")
  password=$(jq -r --arg id "$instance_id" '.[] | select(.id == $id) | .password' "$NODES_FILE")

  if [[ -z "$ip" || -z "$password" ]]; then
    echo "错误：nodes.json 中找不到实例 $instance_id 的记录" >&2
    exit 1
  fi

  echo "SSH 连接 $ip 获取 vless URL..."
  local url
  url=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    root@"$ip" "cat /root/vless_url.txt 2>/dev/null || (cd /root/xray/docker && docker compose logs 2>/dev/null | grep 'vless://' | tail -1)")

  if [[ -z "$url" ]]; then
    echo "暂未获取到 vless URL，容器可能还在初始化，请稍后再试。" >&2
    echo "可手动 SSH 查看：ssh root@$ip（密码：$password）" >&2
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
    echo "用法：$SELF delete <instance-id|label|ip>" >&2
    exit 1
  fi

  check_api_key

  local instance_id
  instance_id=$(resolve_instance_id "$input")

  echo "即将删除实例：$instance_id"
  read -r -p "确认删除？(y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消。"
    exit 0
  fi

  vultr_delete "/instances/$instance_id"
  remove_node "$instance_id"
  echo "实例 $instance_id 已删除，本地记录已移除。"
}

# ──────────────────────────────────────────────
# 帮助
# ──────────────────────────────────────────────

cmd_help() {
  cat <<EOF
Vultr Reality 节点管理脚本

用法：
  $SELF <命令> [参数]

命令：
  list                          列出所有实例及保存的密码
  create [region]               创建新实例（默认 nrt=日本，可用 sgp=新加坡）
  url <instance-id|label|ip>    获取指定实例的 vless URL
  delete <instance-id|label|ip> 删除指定实例
  regions                       列出所有可用区域

示例：
  $SELF create nrt              # 在日本创建
  $SELF create sgp              # 在新加坡创建
  $SELF list
  $SELF url abc-123-def         # 按 ID
  $SELF url reality-nrt-0505    # 按 Label
  $SELF url 43.123.45.67        # 按 IP
  $SELF delete reality-nrt-0505
EOF
}

# ──────────────────────────────────────────────
# 入口
# ──────────────────────────────────────────────

check_deps

case "${1:-help}" in
  list)    check_api_key; cmd_list ;;
  create)  cmd_create "${2:-nrt}" ;;
  url)     cmd_url "${2:-}" ;;
  delete)  cmd_delete "${2:-}" ;;
  regions) check_api_key; cmd_regions ;;
  help|--help|-h) cmd_help ;;
  *)
    echo "未知命令：$1" >&2
    cmd_help
    exit 1
    ;;
esac
