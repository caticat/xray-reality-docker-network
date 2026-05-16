# Vultr Reality 节点管理脚本

通过 Vultr API 一键创建、查询、删除 VLESS + Reality 代理节点。

## 依赖

```bash
# Ubuntu/Debian
apt install jq sshpass

# CentOS/RHEL
yum install jq sshpass

# macOS
brew install jq hudochenkov/sshpass/sshpass
```

## 获取 API Key

1. 登录 [my.vultr.com](https://my.vultr.com)（需代理访问）
2. 左侧菜单 **Account** → **API Keys**
3. 点击 **Add API Key**，填写名称，权限保持默认
4. 复制保存（只显示一次）

## 使用

```bash
# 设置 API Key（必需；仅当前终端会话有效，不会写入历史记录）
export VULTR_API_KEY=your_api_key_here

# 查看帮助
bash vultr-ctl.sh help

# 在日本创建节点
bash vultr-ctl.sh create nrt

# 在新加坡创建节点
bash vultr-ctl.sh create sgp

# 等待约 5 分钟后获取 vless URL（只接受 Vultr 官方实例 ID）
bash vultr-ctl.sh url <instance-id>

# 列出所有实例及保存的密码
bash vultr-ctl.sh list

# 删除实例（只接受 Vultr 官方实例 ID）
bash vultr-ctl.sh delete <instance-id>

# 查看可用区域
bash vultr-ctl.sh regions

# 默认使用防火墙 7487fb38-476c-414f-95d0-84c440323138；也可以显式覆盖
export VULTR_FIREWALL_ID=7487fb38-476c-414f-95d0-84c440323138
bash vultr-ctl.sh create sgp
```

## 注意事项

- `nodes.json` 保存节点 IP 和密码，已加入 `.gitignore`，不会提交到 git
- 密码只在创建时由 Vultr 返回一次，脚本会立即保存，请勿删除 `nodes.json`
- `url` 依赖本地 `nodes.json` 中保存的 IP 和密码，只支持本脚本创建并保存过的实例
- 脚本不会自动创建 Vultr 防火墙；默认挂载防火墙 `7487fb38-476c-414f-95d0-84c440323138`，可通过 `VULTR_FIREWALL_ID` 覆盖
- 从创建实例到 vless URL 可用约需 **5-8 分钟**（实例启动 + Docker 安装 + 容器构建）
- API Key 只通过环境变量传入，不写入任何文件；未设置时脚本会直接失败并提示 `export VULTR_API_KEY=your_api_key_here`
- 同地区多实例时 Label 会带年月日时分后缀区分，如 `reality-nrt-202605161430`
