#!/bin/bash

# 切换到脚本所在目录，确保相对路径正确
cd "$(dirname "$0")" || exit

echo "=========================================================================="
echo "请选择要在 QNAP 上执行的部署任务："
echo "1. 🚀 全部部署 (Docker 基础环境 + MariaDB + LMS + Yattee)"
echo "2. 🐳 仅部署 Docker 基础环境 (tags: docker)"
echo "3. 🗄️  仅部署/更新 MariaDB 容器，并生成解耦凭证 (tags: mariadb)"
echo "4. 🎵 仅部署/更新 LMS 音乐服务器 (tags: lms)"
echo "5. 📺 仅部署/更新 Yattee 服务器 (tags: yattee)"
echo "6. 🍪 提取本地 YouTube Cookie 并同步到 QNAP (tags: cookie)"
echo "7. 🔍 检查所有服务状态 (tags: status)"
echo "0. ❌ 退出 (默认)"
echo "=========================================================================="
read -r -p "请输入选项 [0]: " choice

case "$choice" in
    1)
        echo ">>> 开始全局部署..."
        ansible-playbook site.yml
        ;;
    2)
        echo ">>> 开始部署 Docker 基础环境..."
        ansible-playbook site.yml --tags docker
        ;;
    3)
        echo ">>> 开始部署 MariaDB 并导出跨项目凭证..."
        ansible-playbook site.yml --tags mariadb
        ;;
    4)
        echo ">>> 开始部署 LMS 音乐服务器..."
        ansible-playbook site.yml --tags lms
        ;;
    5)
        echo ">>> 开始部署 Yattee 服务器..."
        ansible-playbook site.yml --tags yattee
        ;;
    6)
        echo ">>> 开始提取并同步 Cookie..."
        ansible-playbook site.yml -i inventory/hosts.ini -t cookie -e sync_cookie=true
        ;;
    7)
        echo ">>> 正在检查所有服务状态..."
        ansible-playbook check_status.yml -i inventory/hosts.ini
        ;;
    0|*)
        echo ">>> 已退出。"
        exit 0
        ;;
esac

if [[ "$choice" == "1" || "$choice" == "5" ]]; then
    echo "=========================================================================="
    read -r -p "❓ Yattee 服务端已部署完毕！是否现在立刻提取并同步你的 YouTube Cookie 来完成最后一步初始化？ [y/N]: " sync_cookie
    if [[ "$sync_cookie" =~ ^[Yy]$ ]]; then
        echo ">>> 开始提取并同步 Cookie..."
        ansible-playbook site.yml -i inventory/hosts.ini -t cookie -e sync_cookie=true
    fi
fi

echo ">>> 任务完成！"
