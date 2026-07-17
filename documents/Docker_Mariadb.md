# Kodi + MariaDB 集中数据库配置指南

本文档描述如何将 Kodi 的媒体库从本地 SQLite 迁移到 QNAP 上的 MariaDB 容器，
实现配置持久化。TV 重装后 Ansible 推送一个配置文件，Kodi 启动即恢复全部媒体库，
无需重新刮削。

---

## 版本对照表

| Kodi 版本 | 数据库版本 |
|-----------|-----------|
| 21.x Omega | MyVideos131 |
| 22.x Piers | MyVideos139 |

升级 Kodi 大版本时必须处理数据库迁移，见第 4 节。

---

## 第一阶段：Ansible 自动部署 MariaDB 容器

> 以下步骤已全部自动化，运行一次 playbook 即可完成。

```bash
cd ansible/
./apply.sh
# 在菜单中选择选项 3 (仅部署/更新 MariaDB 容器，并生成解耦凭证)
```

### 自动完成的操作

1. **创建数据目录**
   - `/share/CACHEDEV1_DATA/Container_SSD/kodi-mariadb/data`
   - `/share/CACHEDEV1_DATA/Container_SSD/kodi-mariadb/conf`

2. **渲染并部署 docker-compose.yml** 到 QNAP

3. **启动容器**（`docker compose up -d`）
   - 镜像：`mariadb:10.11`
   - 端口：`3306:3306`
   - 启动参数：`--skip-ssl`（Kodi Android 版不支持 SSL）
   - `restart: unless-stopped`

4. **创建 kodi 数据库用户**
   - `GRANT ALL ON *.*`（Kodi 需要全局权限才能建 TRIGGER）
   - 认证方式：`mysql_native_password`

5. **确保 `kodi_video` 数据库存在**（utf8mb4 编码）

---

## 第二阶段：Kodi 首次配置（一次性手动）

### 2.1 推送 advancedsettings.xml 到 TV

Ansible 会自动渲染并通过 ADB 推送（由其他 role 负责）：

```xml
<advancedsettings>
    <videodatabase>
        <type>mysql</type>
        <host>192.168.50.210</host>
        <port>3306</port>
        <user>kodi</user>
        <pass>{{ mariadb_user_password }}</pass>
        <name>kodi_video</name>
    </videodatabase>
</advancedsettings>
```

### 2.2 启动 Kodi，完成首次建库

Kodi 首次启动后会自动在 MariaDB 中创建 `MyVideos131` 并建表。

验证：
```bash
mysql -h 192.168.50.210 -u kodi -p
SHOW DATABASES;
# 应看到 MyVideos131
```

### 2.3 添加媒体源并刮削（唯一一次手动操作）

在 Kodi 界面：

1. 首页 → Videos → Files → Add videos
2. Browse → 输入 NFS 路径，例如：`nfs://192.168.50.210/Media/Video/Movie/`
3. 给源命名（如"电影"），确定
4. **Set content** → This directory contains → **Movies**
5. 选择刮削器：**The Movie Database (TMDB)**
6. 确定 → **Yes**（刷新所有项目）
7. 等待右上角进度条完成

对每个媒体源重复上述步骤（剧集选 TV Shows）。

> **⚠️ 重要提醒**
> 即使文件夹中已有 `.nfo` 文件，在连接到全新空 MariaDB 后也**必须重新刮削一次**。
> 由于本地有 `.nfo` 元数据，刮削会优先读取本地文件，速度极快。
>
> **这是唯一一次手动操作**。刮削完成后所有数据存入 MariaDB，TV 重装后 Ansible 推送
> `advancedsettings.xml`，Kodi 启动直接读取已有媒体库。

---

## 第三阶段：Ansible 写入媒体路径绑定

首次刮削完成后，运行：

```bash
./apply.sh
# 同样选择选项 3
```

Ansible 会检查 `MyVideos131` 是否存在，然后将 `defaults/main.yml` 中的 `kodi_paths`
写入 `MyVideos131.path` 表（`INSERT IGNORE`，幂等操作）。

### 验证媒体源已写入

```bash
mysql -h 192.168.50.210 -u kodi -p MyVideos131

SELECT strPath, strContent, strScraper
FROM path
WHERE strContent != '' AND strContent IS NOT NULL
ORDER BY strPath;
```

### 监控刮削进度（可选）

```bash
watch -n 2 'mysql -h 192.168.50.210 -u kodi -p你的kodi密码 MyVideos131 \
  -e "SELECT COUNT(*) AS movie_count FROM movie;"'
```

---

## 第四阶段：Kodi 版本升级处理

### 升级流程

升级前备份：

```bash
docker exec kodi-mariadb mysqldump -u root -p \
  --all-databases > kodi_full_backup_before_upgrade.sql
```

升级步骤：
1. 在 TV 上安装新版 Kodi APK
2. 启动 Kodi，它会自动将 `MyVideos131` 迁移到新版本（如 `MyVideos139`）
3. 迁移完成后旧数据库会保留，可手动删除：

```bash
mysql -h 192.168.50.210 -u root -p
DROP DATABASE MyVideos131;
```

> **注意**：升级后需同步修改 `paths.yml` 中的 `login_db: MyVideos131` 为新版本号。

### 迁移失败处理

```bash
mysql -h 192.168.50.210 -u root -p < kodi_full_backup_before_upgrade.sql
```

然后降回旧版 Kodi APK，查明原因后再重试。

---

## 故障排除

**Kodi 启动后媒体库为空，MariaDB 有数据**

通常是网络问题：Kodi 在网络就绪前尝试连接失败后回退到空库。
重启 Kodi（不是重启 TV）通常可解决。

---

**连接被拒绝（Connection refused）**

检查 QNAP 防火墙是否放行了 3306 端口，以及容器是否在运行：

```bash
docker ps | grep kodi-mariadb
```

---

**Kodi 日志位置**

```bash
adb -s 192.168.50.220:5555 pull \
  /storage/emulated/0/Android/data/org.xbmc.kodi/files/.kodi/temp/kodi.log \
  ./kodi.log
```

查找关键字：`Unable to open database` 或 `SQL:`。

---

**电影集目录内的电影无法识别**

**现象**：电影集（如"哈利波特合集"）目录下的电影无法识别。

**原因**：两个设置配合不当：
1. ❌ 开启了"电影在包含单一视频的独立目录中"
2. ❌ 未开启"扫描包含的目录"（*Scan recursively*）

**解决**：
- ❌ 关闭"电影在包含单一视频的独立目录中"
- ✅ 开启"扫描包含的目录"

对应 `defaults/main.yml` 中的 `kodi_paths` 配置：
- 电影集路径：`use_folder_names: 0`，`scan_recursive: 2147483647`

---

**报错 "The table does not exist" / 进入电影墙卡死**

**原因**：竞态条件（Race Condition）。Kodi 初次启动时还没来得及执行 `CREATE TABLE`，
就被强行关闭，留下了只有空壳的 `MyVideos131`。

**解决**：
1. 删除损坏的数据库：
   ```sql
   DROP DATABASE MyVideos131;
   ```
2. 重新启动 Kodi，等待其完整建库（观察 `movie_view` 视图出现后再操作）
3. 重新运行 `ansible-playbook site.yml --tags mariadb`
