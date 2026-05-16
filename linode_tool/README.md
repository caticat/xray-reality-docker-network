# Linode Reality 节点管理脚本

通过 Linode API 一键创建、查询、删除 VLESS + Reality 代理节点。

## 方案

| 项目 | 规格 |
|------|------|
| 方案 | g6-nanode-1（Shared CPU） |
| CPU | 1 vCPU |
| 内存 | 1 GB |
| 存储 | 25 GB SSD |
| 流量 | 1 TB |
| 价格 | **$5/月** |

## 依赖

```bash
# Ubuntu/Debian
apt install jq sshpass openssl

# CentOS/RHEL
yum install jq sshpass openssl

# macOS
brew install jq hudochenkov/sshpass/sshpass openssl
```

## 获取 API Key

1. 登录 [cloud.linode.com](https://cloud.linode.com)
2. 左上角菜单 → **Profile** → **API Tokens**
3. 点击 **Create a Personal Access Token**
4. 权限选择：Linodes（Read/Write），其余保持默认
5. 复制保存（只显示一次）

## 使用

```bash
# 设置 API Key（必需；仅当前终端会话有效，不会写入历史记录）
export LINODE_API_KEY=your_api_key_here

# 查看帮助
bash linode-ctl.sh help

# 在新加坡2创建节点
bash linode-ctl.sh create sg-sin-2

# 在日本东京3创建节点
bash linode-ctl.sh create jp-tyo-3

# 等待约 5 分钟后获取 vless URL（只接受 Linode 官方实例 ID）
bash linode-ctl.sh url <instance-id>

# 列出所有实例及保存的密码
bash linode-ctl.sh list

# 删除实例（只接受 Linode 官方实例 ID）
bash linode-ctl.sh delete <instance-id>

# 查看可用区域
bash linode-ctl.sh regions

# 查看防火墙 ID
bash linode-ctl.sh firewalls

# 默认使用防火墙 14171990；也可以显式覆盖
export LINODE_FIREWALL_ID=14171990
bash linode-ctl.sh create sg-sin-2
```

## 注意事项

- `nodes.json` 保存节点 IP 和密码，已加入 `.gitignore`，不会提交到 git
- Linode 创建实例时需要设置 root 密码，脚本会自动生成强密码并保存到 `nodes.json`
- `url` 依赖本地 `nodes.json` 中保存的 IP 和密码，只支持本脚本创建并保存过的实例
- 脚本不会自动创建 Linode 防火墙；默认挂载防火墙 `14171990`，可通过 `LINODE_FIREWALL_ID` 覆盖
- 从创建实例到 vless URL 可用约需 **5-8 分钟**（实例启动 + Docker 安装 + 容器构建）
- API Key 只通过环境变量传入，不写入任何文件；未设置时脚本会直接失败并提示 `export LINODE_API_KEY=your_api_key_here`
- 同地区多实例时 Label 会带年月日时分后缀区分，如 `reality-sg-sin-2-202605161430`
