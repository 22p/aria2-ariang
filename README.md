# aria2 + AriaNg (althttpd)

aria2 负责下载，AriaNg 提供 Web UI，althttpd 托管静态文件并通过 CGI 把 `/jsonrpc` 转发给 aria2。基于 `alpine:latest`，组件全部来自 Alpine 仓库。

```
浏览器 ──:8080──> althttpd ─┬─ /          静态 AriaNg
                            └─ /jsonrpc   CGI ──> 127.0.0.1:6800
```

## 快速开始

```bash
docker run -d \
  --name aria2-ariang \
  -p 8080:8080 \
  -v "$PWD/downloads:/aria2/data" \
  -v "$PWD/config:/aria2/conf" \
  -e PUID=1000 \
  -e PGID=1000 \
  -e RPC_SECRET=change-me \
  ghcr.io/22p/aria2-ariang:latest
```

打开 `http://<host>:8080/`。未设置 `EMBED_RPC_SECRET` 时，在「AriaNg 设置 → RPC」里填写一次 `RPC_SECRET`。

## Quadlet（Podman）

```ini
[Unit]
Description=aria2 + AriaNg

[Container]
Image=ghcr.io/22p/aria2-ariang:latest
ContainerName=aria2-ariang
AutoUpdate=registry
PublishPort=8080:8080
Volume=/opt/aria2/data:/aria2/data:z
Volume=/opt/aria2/conf:/aria2/conf:z
Environment=PUID=1000
Environment=PGID=1000
Environment=RPC_SECRET=change-me

[Service]
Restart=always

[Install]
WantedBy=default.target
```

保存为 `/etc/containers/systemd/aria2-ariang.container`（rootful）或 `~/.config/containers/systemd/aria2-ariang.container`（rootless），执行 `systemctl daemon-reload` 后启动 `aria2-ariang`。`AutoUpdate=registry` 需启用 `podman-auto-update.timer`；rootless 下若在意下载文件归属，加 `Environment=ARIA2_RUN_AS_ROOT=1`。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PUID` | `1000` | 运行 UID 与文件所有者，不能为 0 |
| `PGID` | `1000` | 运行 GID |
| `RPC_SECRET` | 空 | aria2 RPC 密钥，启动时写入 `aria2.conf` |
| `EMBED_RPC_SECRET` | 空 | 把密钥嵌入 AriaNg，免手动输入；UI 公开时等于泄露 |
| `BASIC_AUTH_USERNAME` | 空 | HTTP Basic 认证用户名，需与密码同时设置 |
| `BASIC_AUTH_PASSWORD` | 空 | HTTP Basic 认证密码 |
| `BASIC_AUTH_REALM` | `Aria2` | Basic 认证 realm |
| `ARIA2_RPC_PORT` | `6800` | 容器内 RPC 端口，同步写入 `rpc-listen-port` |
| `ARIA2_RUN_AS_ROOT` | 空 | 设为 `1` 时只让 aria2 以 root 运行 |

`aria2.conf` 首次启动生成到 `/aria2/conf/aria2.conf`，之后不再覆盖。

## 端口与卷

| 路径 | 说明 |
| --- | --- |
| `8080/tcp` | AriaNg 页面与 `/jsonrpc` |
| `/aria2/data` | 下载目录 |
| `/aria2/conf` | `aria2.conf` 与 `aria2.session` |

## 注意

- `6800` 不要发布，RPC 只监听回环地址。
- 不支持 WebSocket，保持 AriaNg 默认的 HTTP JSON-RPC。
- `ARIA2_RUN_AS_ROOT=1` 只让 aria2 以 root 运行：rootless 容器中 root 映射到当前用户，下载文件归属正确；rootful 容器中文件会属于 root。
- 公网访问请设置 `RPC_SECRET` 和 Basic 认证，或在前置代理上做 TLS 与鉴权。
