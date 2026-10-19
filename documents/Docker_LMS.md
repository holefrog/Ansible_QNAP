# Lyrion Music Server (LMS) 容器技术规格与运维指南

本文档记录 LMS（原 Logitech Media Server）在 QNAP NAS 上的容器化架构设计、网络决策推导与日常运维细节。

---

## 1. 服务概述

- **镜像名称**：`lmscommunity/lyrionmusicserver:latest`
- **容器名称**：`lyrionms`
- **服务定位**：家庭局域网流媒体音频中枢，支持 Squeezebox 协议，服务于 Squeezelite、WiiM、AirPlay、Chromecast 等音频终端。
- **配置数据路径**：`/share/CACHEDEV1_DATA/Container_SSD/LMS_Data`

---

## 2. 关键架构决策：为什么必须使用 Host 网络模式？

LMS 在容器化部署中与传统 Web 应用（如 MariaDB、Nginx）有根本性差异。官方及社区均强烈推荐使用 `network_mode: host`，其技术推导如下：

### 2.1 硬件播放器广播与多播穿透（UDP 3483 / 5353 / 1900）
1. **SlimProto 自动发现**：Squeezebox 硬件播放器及 Squeezelite 客户端在局域网通电后，会发送 `UDP 3483` 广播报文搜寻服务器。
2. **多播与投播协议**：用于 AirPlay（Shairplay）的 `mDNS (UDP 5353)` 以及用于 DLNA/UPnP 的 `SSDP (UDP 1900)` 均为二层链路多播。
3. **Bridge 网桥硬伤**：Docker 默认的 Bridge 模式（172.x.x.x）跨 NAT 时会阻断广播与多播包，导致局域网物理播放器无法自动感知服务器存在，必须每次手动硬编码 IP，且投播插件完全失效。

### 2.2 根除流媒体 URL 的“172 内网死链”
1. **流媒体回调机制**：LMS 在向播放器下发音频流时，应用层会在 Payload 中拼接服务端网卡 IP（例如 `http://<server-ip>:9000/stream.mp3`）。
2. **Bridge 模式缺陷**：LMS 容器内部检测到的 IP 为 `172.x.x.x`，下发给处于局域网（`192.168.50.xxx`）的播放器后，播放器尝试向 172 网段拉流直接握手超时或报错。
3. **Host 模式收益**：容器完全共享 QNAP 物理网络命名空间，LMS 检测到的即为 `192.168.50.210`，派发的推流地址在局域网内直接生效。

---

## 3. 端口与网络占用规范

在 `network_mode: host` 模式下，LMS 不再通过 Docker 映射端口，而是直接绑定宿主机的以下端口：

| 端口 | 协议 | 用途说明 | 冲突排查建议 |
| :--- | :--- | :--- | :--- |
| **9000** | TCP | Web 管理后台（支持 Material Skin 界面） | 需确保 QNAP 未运行其他占用 9000 的 Web 服务 |
| **9090** | TCP | CLI / Telnet 控制接口（供自动化与脚本调用） | 专用控制端口 |
| **3483** | TCP | SlimProto 音频流控制传输通道 | Squeezebox 协议专用 |
| **3483** | UDP | SlimProto 硬件播放器自动发现广播 | 局域网广播寻址 |

> **注意**：在 Docker Compose 文件中，声明 `network_mode: host` 后**禁止同时声明 `ports:`**，否则 Compose 将输出语法互斥告警并忽略映射。

---

## 4. 存储规划与安全隔离

LMS 采用读写分离与最小权限挂载策略：

```
/share/CACHEDEV1_DATA/Container_SSD/LMS_Data/
├── config/              # 读写挂载 (/config) - 配置文件、插件缓存、内部 SQLite 库
├── playlist/            # 读写挂载 (/playlist) - 播放列表文件 (.m3u)
└── docker-compose.yml   # Ansible 动态渲染部署文件
```

- **音源曲库安全挂载**：
  宿主机音频源目录挂载至容器 `/music:ro`，强制声明为**只读（Read-Only）**，物理隔绝容器对原始高品质音乐文件的误删、修改或破坏风险。
- **运行权限**：
  配置 `PUID: 99`、`PGID: 100`，严格匹配 QNAP 系统的管理员组文件权限，防止升级重建容器后出现目录权限锁定（Permission Denied）。

---

## 5. 部署逻辑与自愈机制

通过 Ansible Role（`roles/lms/`）实现了幂等与自愈：

1. **配置变更监听**：每次运行会先预渲染 `docker-compose.yml`，比对散列值。若模板变更（如修改了网络模式或目录），自动标记 `compose_template.changed`。
2. **多态自愈**：
   - 镜像有更新（`pull_result.changed`）；
   - 配置文件变更（`compose_template.changed`）；
   - 容器处于停止或退出状态（不在 running 列表中）。
   满足以上任一条件，Ansible 会先安全执行 `docker rm -f lyrionms` 释放宿主机端口，再拉起新容器，实现秒级平滑过渡。

---

## 6. 常用运维与调试命令（环境声明：QNAP 宿主机）

以下排错命令需在 **QNAP 宿主机**（或在开发机通过 `ssh` 包装）运行：

````bash
# 1. 检查 LMS 端口实际占用情况
netstat -tuln | grep -E ":(9000|9090|3483)"

# 2. 查看容器运行状态与资源占用
docker ps --filter name=lyrionms
docker stats lyrionms --no-stream

# 3. 查看实时启动日志
docker logs -f lyrionms --tail 100
````
