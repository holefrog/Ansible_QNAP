# 📜 Yattee 使用指南

本文档为 Ansible 自动化部署完成后的**使用操作指南**。所有服务端基础设施（Docker 容器、Nginx 反代、SSL 证书、DDNS）均由 Ansible 一键部署，无需手动配置。

> **⚠️ 部署前特别注意 (针对 ChangeIP 用户)**
> 如果你使用的是 ChangeIP 等部分动态域名服务，请务必在跑 Ansible 部署前，先登录控制台（**Services -> DNS Manager**），手动添加一条子域名记录（Host 填 `yattee`，Type 填 `A`，Value 填上服务器公网 IP）。由于 ChangeIP 的 API 不支持“无中生有”创建子域名记录，如果不提前加好，会导致后续申请 Let's Encrypt 证书时因找不到该域名而中断部署！

---

## 📱 第一步：注册美区谷歌账号（带 2FA）

由于谷歌在 2026 年大幅强化了对网页端的风控，直接在电脑端注册极易卡死在手机号验证上。**使用安卓手机的系统设置层注册，能 100% 触发「跳过」按钮，是最可靠的方案。**

### 1. 安卓手机系统层注册（免强绑定非美区手机号）
1. **网络隔离：** 在安卓手机上打开网络工具，切换到 **美国（US）** 节点，并开启 **全局路由（Global）** 模式。
2. **切断网页：** 不要使用 Chrome。直接进入安卓手机的 **`Settings (系统设置)`** -> 找到 **`Google`** 或 **`Accounts (账户)`** -> 点击 **`Add account (添加账户)`** -> 选择 **Google**。
3. **开始创建：** 点击左下角 `Create account` -> 选择 `For my personal use`。
4. **填写资料：** 名字随意填，生日年份确保成年（填 2000 年以前，未成年账号会触发 YouTube API 的内容限制导致 Yattee 报错）。
5. **绕过验证码（关键点）：** 走到填写手机号的页面时，直接点击左下角的 **`Skip (跳过)`** 按钮。顺利绕过强制手机号强绑定，直接生成纯正的美区账号。

### 2. 开启 2FA 两步验证（账号保护）
在使用 Cookie 授权方案时，你的密码和账号不会直接在服务器端暴露，极大降低了被谷歌风控的概率。但为了进一步保障账号安全，强烈建议开启两步验证。

1. 账号注册成功后，在电脑或手机浏览器中登录该新账号，访问 **[https://myaccount.google.com](https://myaccount.google.com)**。
2. 在左侧/顶部菜单点击 **`Security (安全性)`** -> 往下划找到 **`How you sign in to Google（登录 Google 的方式）`** -> 点击 **`2-Step Verification (两步验证)`** 并将其开启。*（注：此处可以使用你的本地真实手机号接收一次性短信完成验证，仅用于两步验证保护，不会改变账号的美区归属国身份）*。
3. 两步验证开启后，你的美区账号即做好了万全准备。此账号只需在你的个人电脑浏览器中保持登录即可，后续我们将通过提取本地浏览器 Cookie 的方式进行凭证授权。

## 📺 第二步：配置 YouTube 身份凭证 (Cookies)

在 2024-2026 年，YouTube 针对 RackNerd 等机房 VPS 以及各类数据中心进行了严格的反爬风控。如果后台不填入任何身份凭证，在提取视频时必定会报出 `Sign in to confirm you’re not a bot` 的错误。

过去我们需要手动开启全局代理并注入 Cookie，**现在这个过程已经被 Ansible 彻底自动化！**

1. **一键自动提取与同步**：
   直接在你的控制节点（运行 Ansible 的电脑）上，进入 `Ansible_QNAP/ansible/` 目录，运行：
   ```bash
   ./apply.sh
   ```
   在菜单中选择 **选项 6 (提取本地 YouTube Cookie 并同步到 QNAP)**。

2. **操作指引**：
   - 脚本会询问你本地是否有代理（例如 `socks5://127.0.0.1:12334`），如果有请填入。
   - 随后，脚本会自动在你的本地电脑弹出一个处于隔离模式的 Chrome 浏览器。
   - 在这个浏览器中，登录你刚刚注册的美区 YouTube 账号。
   - 登录成功后，**彻底关闭该 Chrome 窗口**。
   - 脚本会自动接管，通过 `yt-dlp` 提取加密 Cookie，转换格式，并通过 SSH 安全地推送到 QNAP 的 Yattee 容器内。
   - 最后，脚本会自动重启 Yattee 容器让 Cookie 即刻生效！

3. *注意：如果未来在使用 Yattee 时再次出现提取失败或无法播放，说明 Cookie 已过期，请再次运行 `./apply.sh` 选择菜单 6 重新获取并覆盖。*

---

## 📱 第三步：iPhone Yattee 客户端对接

1. **在 iPhone 上安装 Yattee**：
   - 先在 App Store 下载 **TestFlight**。
   - 然后使用浏览器打开链接 `https://testflight.apple.com/join/jTWDHuZE`。
   - 页面会自动跳转到 TestFlight，接受邀请并下载最新版本的 Yattee。
2. 进入 **`Settings (⚙️)`** -> **`Sources (源)`** -> 点击底部 **`+ Add Remote Server (添加源)`**。
3. 在 **Address (地址)** 中填入你的专属后端地址：`https://yattee.yourdomain.com/`。
4. 点击下方的 **`Detect (检测)`**，检测成功后会要求输入账号密码（例如 `admin`/`admin`）。
5. 保存后，就可以在首页使用新增加的 Source 来搜索和播放了。

---

## 🔄 容器自动更新

由于 YouTube 网页端算法频繁改版，底层的 `yt-dlp` 解析组件需要定期更新。

Ansible 已部署了 **`yattee-update.timer`** 定时任务，**每周一凌晨 4:00** 自动执行 `git pull && docker compose up -d --build`，在不破坏落盘 Cookie 凭证的前提下完成静默热更新。

如果遇到解析故障需要手动立即更新，SSH 登录 VPS 执行：

```bash
cd /opt/yattee-server
git pull && docker compose up -d --build
```

## 🛠️ 排障与运行日志

如果在使用过程中遇到视频无法播放、或者想确认 Invidious 代理是否正常接管了流量，可以通过实时查看容器日志来排查问题。SSH 登录 VPS 后执行：

```bash
docker logs -f yattee-server
```

*(使用 `Ctrl + C` 可以退出日志实时查看模式)*

