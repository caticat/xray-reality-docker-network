FROM alpine:3.19

# 安装运行时依赖（iproute2 提供 ip 命令，作为 IP 获取备用方案）
RUN apk add --no-cache curl bash iproute2 unzip \
    && curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o /tmp/xray.zip \
    && unzip /tmp/xray.zip -d /tmp/ \
    && mv /tmp/xray /usr/local/bin/xray \
    && rm -rf /tmp/xray.zip /tmp/geoip.dat /tmp/geosite.dat \
    && chmod +x /usr/local/bin/xray

WORKDIR /etc/xray

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
