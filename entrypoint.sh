#!/bin/bash
set -e

CONFIG_FILE="/data/reality.env"

# 确保 data 目录存在
mkdir -p /data

# 首次启动：自动生成配置并持久化
if [ ! -f "$CONFIG_FILE" ]; then
  echo "首次启动，自动生成配置..."

  KEYS=$(/usr/local/bin/xray x25519)
  PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
  PUBLIC_KEY=$(echo "$KEYS" | grep "Password (PublicKey):" | awk '{print $3}')
  UUID=$(/usr/local/bin/xray uuid)
  SHORT_ID=$(/usr/local/bin/xray uuid | tr -d '-' | head -c 8)

  cat > "$CONFIG_FILE" <<EOF
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF

  chmod 600 "$CONFIG_FILE"
  echo "配置已保存到 $CONFIG_FILE"
fi

# 读取配置
source "$CONFIG_FILE"

# 环境变量（支持运行时自定义）
PORT=${PORT:-443}
SNI=${SNI:-www.microsoft.com}
DEST="${SNI}:${PORT}"

# 生成 Xray config.json
cat > /etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 获取本机公网 IP（多种备用方案）
SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 3 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 3 https://icanhazip.com 2>/dev/null || \
            ip -4 addr show | awk '/inet/ && !/127.0.0.1/ {split($2, a, "/"); print a[1]; exit}' || \
            echo "YOUR_VPS_IP")

echo "=========================================="
echo "节点已就绪，复制下面的 URL 到客户端："
echo ""
echo "vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#reality-node"
echo "=========================================="

exec /usr/local/bin/xray -config /etc/xray/config.json
