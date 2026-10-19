#!/bin/bash

# 切换到脚本所在目录，确保相对路径正确
cd "$(dirname "$0")" || exit

echo "=========================================================================="
echo "请选择要在 QNAP 上执行的部署任务："
echo "1. 🚀 全部部署 (Docker 基础环境 + MariaDB + LMS)"
echo "2. 🐳 仅部署 Docker 基础环境 (tags: docker)"
echo "3. 🗄️  仅部署/更新 MariaDB 容器，并生成解耦凭证 (tags: mariadb)"
echo "4. 🎵 仅部署/更新 LMS 音乐服务器 (tags: lms)"
echo "5. 🔍 检查所有服务状态 (tags: status)"
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
        echo ">>> 正在检查所有服务状态..."
        ansible-playbook check_status.yml -i inventory/hosts.ini
        ;;
    0|*)
        echo ">>> 已退出。"
        exit 0
        ;;
esac

echo ">>> 任务完成！"
