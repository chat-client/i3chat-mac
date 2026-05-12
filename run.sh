#!/bin/bash
# 运行i3Chat应用的脚本

cd "$(dirname "$0")"

# 清除扩展属性
xattr -cr build/i3Chat.app 2>/dev/null

# 运行应用
open build/i3Chat.app
