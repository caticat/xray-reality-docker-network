# 项目说明

本项目的主要入口脚本为：

```
vultr_tool/vultr-ctl.sh
```

## 目录结构

- `docker/`：包含 Docker 相关配置和脚本
    - `docker-compose.yml`：Docker Compose 配置文件
    - `Dockerfile`：Docker 镜像构建文件
    - `entrypoint.sh`：容器入口脚本
    - `data/`：存放环境变量等数据文件
        - `reality.env`：环境变量文件
- `vultr_tool/`：包含主要控制脚本
    - `vultr-ctl.sh`：**项目主入口脚本**
    - `README.md`：vultr_tool 目录说明

## 使用说明

请直接运行 `vultr_tool/vultr-ctl.sh` 脚本作为项目入口。

---

如需详细使用方法，请参考各目录下的 README.md 文件。