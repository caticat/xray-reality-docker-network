# 自建 Reality 节点（零配置版）

基于 Xray-core 的 VLESS + Reality 翻墙节点，Docker 化部署，**完全自动化配置**。

---

## 特点

- 零配置，无需手动生成密钥/UUID
- 一键启动，`docker compose up -d` 即可
- 自动输出客户端 URL，复制即用
- 配置持久化，重启/换 IP 不变

---

## 快速开始

### 第一步：安装 Docker

```bash
curl -fsSL https://get.docker.com | bash
```

### 第二步：上传文件并启动

```bash
# 创建对应文件夹
mkdir -p /root/xray/

# 上传 docker/ 目录到 VPS
scp -r docker/ root@your-vps-ip:/root/xray/

# 启动（首次会自动创建 data/ 目录）
cd /root/xray/docker
docker compose up -d

# 查看客户端 URL（自动生成）
docker compose logs | grep "vless://"
```

复制输出的 `vless://` URL 到客户端即可。

**注意：** `data/` 目录会自动创建，用于存储密钥配置，请勿删除或提交到 git。

---

## 工作原理

**首次启动：** 自动生成 UUID、密钥对、Short ID，保存到 `data/reality.env`，输出客户端 URL。

**再次启动：** 读取 `data/reality.env`，直接使用已有配置，重新输出 URL。

---

## 自定义伪装站点（可选）

取消 `docker-compose.yml` 中的注释：

```yaml
environment:
  - PORT=443
  - SNI=www.apple.com
```

推荐站点（大厂、TLS 稳定）：

| 站点                      |
|--------------------------|
| `www.microsoft.com`（默认）|
| `www.apple.com`          |
| `www.cloudflare.com`     |

修改后重启生效：`docker compose restart`

---

## 常用操作

### Docker Compose 命令说明

| 命令 | 作用 | 使用场景 |
|------|------|---------|
| `docker compose up -d` | 创建并启动容器（后台运行） | 首次部署 |
| `docker compose start` | 启动已存在的容器 | 执行 stop 后重新启动 |
| `docker compose stop` | 停止容器（不删除） | 临时停止服务 |
| `docker compose restart` | 重启容器 | **最常用**，修改配置后生效 |
| `docker compose down` | 停止并删除容器 | 更新镜像、彻底清理 |

**日常使用：** `up -d` 一次，后续用 `restart` 或 `stop/start`。`down` 很少用（会清空日志）。

**`-d` 含义：** detach（后台运行），不加会占用终端。

---

### 常用命令

```bash
# 查看客户端 URL
docker compose logs | grep "vless://"

# 查看实时日志
docker compose logs -f

# 重启服务（修改配置后）
docker compose restart

# 临时停止
docker compose stop

# 重新启动
docker compose start

# 查看运行状态
docker compose ps

# 更新镜像（需要先 down）
docker compose down
docker compose build --no-cache
docker compose up -d

# 重新生成配置（慎用，客户端需重新导入）
rm -rf data/
docker compose restart
```

---

## 换 IP 流程（IP 被封后）

### 方案 A：保留配置（推荐，客户端只改 IP）

```bash
# 1. 备份配置
scp -r root@旧IP:/root/xray/docker/data/ ./backup/

# 2. 销毁旧 VPS，创建新 VPS

# 3. 安装 Docker，上传文件
curl -fsSL https://get.docker.com | bash
scp -r docker/ root@新IP:/root/xray/
scp -r backup/data/ root@新IP:/root/xray/docker/

# 4. 启动
cd /root/xray/docker && docker compose up -d

# 5. 客户端只改 IP，其他参数不变
```

### 方案 B：重新生成配置（不带 data/ 目录上传）

```bash
# 上传时不带 data/，启动后自动生成新配置
docker compose up -d
docker compose logs | grep "vless://"
# 重新导入新 URL 到客户端
```

---

## 故障排查

### 客户端连接超时

节点日志正常（显示 `Xray started`）但客户端超时，通常是防火墙拦截了端口。

```bash
# 1. 确认 xray 正在监听端口
ss -tlnp | grep 443

# 2. 检查防火墙状态
ufw status
```

如果 ufw 是 active 但 443 未放行，执行：

```bash
ufw allow 443/tcp
```

> Vultr 等服务商的 Ubuntu 镜像默认启用 ufw，只开放 22（SSH），需手动放行代理端口。

---

## 关于"无加密"

客户端 URL 中 `encryption=none` **是正常配置，不是漏洞**。

Reality 的加密由 **TLS 层**提供（伪装成真实 HTTPS），VLESS 协议层不需要二次加密。这是 Reality 标准配置，安全性极高。

---

## 注意事项

- `data/` 目录包含敏感密钥，不要提交到 git
- 不要高并发跑流量，不要跑 BT/PT 下载
- Reality 降低被识别概率，但 IP 仍是核心风险，被封只能换 IP
