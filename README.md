# Ansible_QNAP

本项目是家庭实验室（Homelab）的**后端基础设施层**。基于 Ansible 自动化架构，专门针对 QNAP NAS 的 Container Station 部署核心级容器服务。

该项目作为独立的服务提供者（Provider），为其他项目（如客户端设备）提供强解耦的数据支撑和凭证下发。

---

## 1. 核心架构与解耦理念

本项目最核心的设计模式是**职责分离与高度可移植**：
1. **全局路径解耦**：彻底摒弃了代码中的硬编码绝对路径。底层的存储卷（如 `qnap_vol1`、`qnap_vol4`）和统一的基础目录，全部集中在 `group_vars/qnap.yml` 中维护。所有的 Role 和应用服务均通过全局变量动态计算路径。未来如需迁移至新磁盘或全新 NAS，仅需修改 `qnap.yml` 即可全局适配。
2. **凭证隔离下发**：前端客户端项目（如 Kodi）需要访问数据库时，本脚本在部署 MariaDB 后，会自动向控制节点的 `~/.config/homelab/mariadb_config.yml` 导出凭证。前端项目直接读取此共享凭证，实现了密码无需硬编码即可跨项目传递。
3. **前置环境优雅拦截**：充分考虑了 QNAP 系统的封闭性。针对无法使用 `apt/yum` 自动安装的组件（如 Container Station），脚本提供优雅的探测机制。若未检测到核心环境，会给出明确直观的提示引导用户在 Web GUI 中手动安装，告别生硬的报错。

---

## 2. 提供的核心服务

### 2.1 MariaDB (Kodi 中心数据库)
- **精准权限管理**：官方 `mariadb` 容器内运行用户为 `999`。脚本在部署时自动修复数据目录挂载权限，根绝 `Error 1006`。
- **全局用户授权**：自动为 `kodi` 用户执行授权，使得前端 Kodi 有权限自发建立、迁移数据库，将建表逻辑彻底还给客户端。
- **环境导出**：执行完毕后自动生成跨库配置。

### 2.2 Lyrion Music Server (LMS)
- **智能增量部署**：利用 Docker Digest 校验，在未拉取到新版本时安全略过；检测到更新才会触发重建。
- **安全平滑升级**：自动定位并清理旧版本容器，释放核心端口，确保升级 `0` 损耗过渡。

### 2.3 Yattee Server
- **双引擎内网穿透架构**：同时支持局域网 HTTP 直连与 Tailscale Sidecar 零信任模式。通过 `yattee_local_port` 与 `yattee_internal_port` 常量解耦暴露本地端口满足局域网纯本地调优需求，同时依靠 Tailscale MagicDNS 提供完美适配 iOS ATS 限制的 Let's Encrypt HTTPS 证书，兼顾调试便利与全天候移动端无缝漫游体验。
- **全自动 Cookie 提取与同步**：支持从本地主机全自动弹窗拉起隔离版 Chrome，用户登录 YouTube 后，脚本会自动使用 `yt-dlp` 提取 Cookie 并以物理文件形式推送到 NAS 的正确目录下，解决 Yattee 免登录无法使用的问题。
  > **⚠️ 注意：关于 Web UI 凭据状态显示的视觉差异**
  > 由于本 Ansible 脚本采用了最高效的底层文件级挂载方式（直接将 `cookies.txt` 挂载为 `--cookies /etc/yt-dlp-cookies.txt` 喂给下载引擎），直接绕过了常规的网页数据库存取。
  > 因此，**你在 3000 端口的 Web 后台（Credentials 栏目）永远只会看到 `No credentials added`**。网页 UI 只能读取其自身的 SQLite 数据库，它是感知不到底层物理挂载文件的。这是完全符合预期的正常现象，请直接无视 UI 提示，只要客户端播放正常即代表底层凭据已完美生效！
- **自动化无损更新**：Ansible 自动将更新脚本注入至 QNAP `crontab`（每周执行），且 Cookie 文件权限完美适配了热更新需求。

---

## 3. 部署与使用指南

### 3.1 前置要求
- 需要一份加密的 `secrets.yml`（参考 `secrets.yml.example`）。
- 控制节点已安装 Ansible 并配置好对 QNAP 的免密或 Vault 支持。

### 3.2 一键操作终端
直接在 `ansible/` 目录下运行导航菜单脚本：

```bash
cd ansible/
./apply.sh
```

**菜单选项功能：**
1. **🚀 全部部署**：依次拉起 Docker 基础环境 -> MariaDB -> LMS -> Yattee，并完成凭证导出。
2. **🐳 仅部署 Docker 基础环境**：用于新 NAS 初始化，检查 Docker 版本并设置必备工作目录。
3. **🗄️ 仅部署 MariaDB**：专门用于强制重置数据库配置及更新跨项目凭证。
4. **🎵 仅部署 LMS**：极其适合日常对 LMS 进行无脑一键平滑升级，自动拉取新版并完成旧数据无缝挂载。
5. **📺 仅部署 Yattee 服务器**：拉起 Yattee 及 Tailscale 容器。部署完成后会智能询问是否需要立刻进行 Cookie 提取初始化。
6. **🍪 提取本地 YouTube Cookie 并同步到 QNAP**：独立运维选项，可在 Cookie 过期时随时一键单独刷新同步。
7. **🔍 检查所有服务状态**：统一的安全健康体检看板！在一个屏幕中汇总所有容器的运行时间、Tailscale 设备在线详情以及所有底层磁盘目录的存在性（结合了优雅的报错屏蔽处理）。

---

## 4. 后续扩展计划

## 5. 详细技术文档库 (documents/)

本系统在构建过程中积累了大量深度剖析架构的知识文档。若想深入了解底层网络协议、组件级调试方法或进阶运维指南，请查阅 `documents/` 目录：

- 📙 **[YATTEE.md](documents/YATTEE.md)**：Yattee 运维进阶指南。包含了无手机号安全注册美区 YouTube 账号以规避风控的独家经验，以及 iOS 客户端的无缝接入流程。
- 📗 **[Docker_Mariadb.md](documents/Docker_Mariadb.md)**：详述了家庭媒体库（Kodi + MariaDB）数据库解耦设计理念、客户端配置自举逻辑，以及跨大版本平滑升级 Kodi 时的后端数据迁移指南。
