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
# 设置 API Key（仅当前终端会话有效，不会写入历史记录）
# 如果未设置，脚本会交互式提示输入
export VULTR_API_KEY=your_vultr_api_key

# 查看帮助
bash vultr-ctl.sh help

# 在日本创建节点
bash vultr-ctl.sh create nrt

# 在新加坡创建节点
bash vultr-ctl.sh create sgp

# 等待约 5 分钟后获取 vless URL（支持 ID / Label / IP）
bash vultr-ctl.sh url <instance-id>
bash vultr-ctl.sh url reality-nrt-0505
bash vultr-ctl.sh url 43.123.45.67

# 列出所有实例及保存的密码
bash vultr-ctl.sh list

# 删除实例（支持 ID / Label / IP）
bash vultr-ctl.sh delete <instance-id>

# 查看可用区域
bash vultr-ctl.sh regions
```

## 注意事项

- `nodes.json` 保存节点 IP 和密码，已加入 `.gitignore`，不会提交到 git
- 密码只在创建时由 Vultr 返回一次，脚本会立即保存，请勿删除 `nodes.json`
- 从创建实例到 vless URL 可用约需 **5-8 分钟**（实例启动 + Docker 安装 + 容器构建）
- API Key 只通过环境变量传入，不写入任何文件；未设置时脚本会交互式提示输入（`read -s`，不回显不写历史）
- 同地区多实例时 Label 会带日期后缀区分，如 `reality-nrt-0505`
