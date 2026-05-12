#!/bin/bash
# i3Chat 安装辅助脚本
# 用于在其他 Mac 上安装使用临时签名的 i3Chat 应用

set -e

APP_NAME="i3Chat.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "i3Chat 安装辅助脚本"
echo "=========================================="
echo ""

# 检查是否提供了应用路径
if [ -z "$1" ]; then
    echo "用法: $0 <i3Chat.app 的路径>"
    echo ""
    echo "示例:"
    echo "  $0 ~/Downloads/i3Chat.app"
    echo "  $0 /Volumes/i3Chat/i3Chat.app"
    exit 1
fi

APP_PATH="$1"

# 检查应用是否存在
if [ ! -d "$APP_PATH" ]; then
    echo "错误: 找不到应用: $APP_PATH"
    exit 1
fi

# 检查是否是 i3Chat.app
if [ "$(basename "$APP_PATH")" != "$APP_NAME" ]; then
    echo "错误: 这不是 $APP_NAME"
    echo "请提供正确的应用路径"
    exit 1
fi

echo "找到应用: $APP_PATH"
echo ""

# 移除隔离属性
echo "步骤 1: 移除隔离属性..."
xattr -cr "$APP_PATH" 2>/dev/null || true
echo "✓ 隔离属性已移除"
echo ""

# 验证应用结构
echo "步骤 2: 验证应用结构..."
if [ ! -f "$APP_PATH/Contents/MacOS/i3Chat" ]; then
    echo "错误: 应用结构不完整"
    exit 1
fi
echo "✓ 应用结构正常"
echo ""

# 检查签名状态
echo "步骤 3: 检查签名状态..."
SIGNATURE=$(codesign -dv "$APP_PATH" 2>&1 | grep "Signature=" || echo "未签名")
echo "当前签名: $SIGNATURE"
echo ""

# 提示用户
echo "=========================================="
echo "安装准备完成！"
echo "=========================================="
echo ""
echo "由于应用使用临时签名，macOS 可能会阻止运行。"
echo ""
echo "安装方法："
echo ""
echo "方法 1 - 右键打开（推荐）："
echo "  1. 在 Finder 中找到 $APP_NAME"
echo "  2. 右键点击应用"
echo "  3. 选择'打开'"
echo "  4. 在安全警告中点击'打开'"
echo ""
echo "方法 2 - 复制到 Applications："
echo "  1. 将 $APP_NAME 拖拽到 /Applications 文件夹"
echo "  2. 首次运行时，在'系统设置' > '隐私与安全性'中允许运行"
echo ""
echo "方法 3 - 使用命令行（需要管理员权限）："
echo "  sudo spctl --master-disable  # 禁用 Gatekeeper（不推荐）"
echo ""
echo "=========================================="
echo ""

# 询问是否要复制到 Applications
read -p "是否要将应用复制到 /Applications? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "/Applications/$APP_NAME" ]; then
        read -p "/Applications/$APP_NAME 已存在，是否覆盖? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "/Applications/$APP_NAME"
        else
            echo "已取消"
            exit 0
        fi
    fi
    
    echo "正在复制到 /Applications..."
    cp -R "$APP_PATH" "/Applications/$APP_NAME"
    xattr -cr "/Applications/$APP_NAME" 2>/dev/null || true
    echo "✓ 应用已复制到 /Applications"
    echo ""
    echo "现在可以："
    echo "  1. 打开 Launchpad 或 Finder 中的 Applications 文件夹"
    echo "  2. 找到 i3Chat 并双击运行"
    echo "  3. 如果被阻止，右键点击选择'打开'"
fi

echo ""
echo "完成！"
