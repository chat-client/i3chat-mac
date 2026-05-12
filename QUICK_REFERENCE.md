# 🚀 i3Chat Xcode 项目 - 快速参考卡

## 📂 项目位置
```
/Users/zsx/work/gitee/chat-client/i3chat/mac/xcode/i3Chat.xcodeproj
```

## ⚡ 最快开始方式

### 在 Xcode 中打开
```bash
open /Users/zsx/work/gitee/chat-client/i3chat/mac/xcode/i3Chat.xcodeproj
```
然后 **Cmd+B** 编译，**Cmd+R** 运行。

### 在命令行编译
```bash
cd /Users/zsx/work/gitee/chat-client/i3chat/mac/xcode
xcodebuild -scheme i3Chat -configuration Debug build
open build/Debug/i3Chat.app
```

## ✅ 编译状态

| 配置 | 状态 | 可执行文件 | 位置 |
|------|------|-----------|------|
| Debug | ✅ BUILD SUCCEEDED | 2.7M | build/Debug/i3Chat.app |
| Release | ✅ BUILD SUCCEEDED | 3.9M | build/Release/i3Chat.app |

## 📊 项目配置

- **架构**：arm64 (Apple Silicon)
- **最小系统**：macOS 10.13
- **语言**：Objective-C (C11)
- **编译器**：clang (LLVM)
- **源文件**：27 个
- **框架**：4 个（Foundation, Cocoa, AppKit, QuartzCore）
- **本地化**：English, 简体中文

## 🔨 常用命令

```bash
# 编译 Debug 版本
xcodebuild -scheme i3Chat -configuration Debug build

# 编译 Release 版本
xcodebuild -scheme i3Chat -configuration Release build

# 清除编译
xcodebuild clean

# 编译并运行（一行完成）
xcodebuild -scheme i3Chat -configuration Debug build && open build/Debug/i3Chat.app

# 查看详细编译日志
xcodebuild -scheme i3Chat -configuration Debug build -v

# 列出可用 scheme
xcodebuild -list
```

## 📚 文档

| 文件 | 用途 |
|------|------|
| `PROJECT_COMPLETION_REPORT.md` | 完成报告（最详细）|
| `XCODE_COMPLETION_SUMMARY.md` | 项目说明（推荐） |
| `XCODE_PROJECT_README.md` | 技术文档 |
| `QUICK_REFERENCE.md` | 本文件（快速查询）|

## 🎯 编辑项目

### 在 Xcode 中
1. 打开 `i3Chat.xcodeproj`
2. 在左侧选择项目名 "i3Chat"
3. 在中间选择 "i3Chat" target
4. 在右侧选择 "Build Settings" 或 "Build Phases"

### 直接编辑配置文件
```bash
# 打开项目配置文件
open /Users/zsx/work/gitee/chat-client/i3chat/mac/xcode/i3Chat.xcodeproj/project.pbxproj
```

## 🐛 调试

1. 在 Xcode 中打开项目
2. 在代码中设置断点（点击行号）
3. 按 **Cmd+Y** 附加调试器
4. 按 **Cmd+R** 运行应用
5. 应用会在断点处停止

## 📦 编译输出

编译成功后，应用位于：

```
build/
├── Debug/
│   └── i3Chat.app
│       ├── Contents/
│       │   ├── Info.plist
│       │   ├── Resources/
│       │   │   ├── AppIcon.icns
│       │   │   ├── en.lproj/
│       │   │   └── zh-Hans.lproj/
│       │   └── MacOS/
│       │       └── i3Chat (可执行文件)
│       └── ...
└── Release/
    └── i3Chat.app
```

## 🔍 验证编译

```bash
# 检查可执行文件
file build/Debug/i3Chat.app/Contents/MacOS/i3Chat

# 检查框架链接
otool -L build/Debug/i3Chat.app/Contents/MacOS/i3Chat

# 列出编译文件
ls -lh build/Debug/i3Chat.app/Contents/MacOS/i3Chat
```

## 📋 源文件组织

```
IRCClient/        → IRC 协议实现 (2 个文件)
Storage/          → 数据存储 (3 个文件)
UI/               → 用户界面 (18 个文件)
third-party/sqlite/  → SQLite 数据库 (1 个文件)
main.m            → 主程序入口
Info.plist        → 应用配置
DebugLog.h        → 调试日志
```

## 🛠 问题排查

### 编译失败
1. 清除编译：`xcodebuild clean`
2. 检查 Xcode 是否最新：`xcode-select --install`
3. 重新编译：`xcodebuild build`

### 运行时崩溃
1. 在 Xcode 中运行获得详细错误信息
2. 检查 Console.app 的系统日志

### 找不到头文件
1. 检查 Build Settings > Search Paths > Header Search Paths
2. 确保路径设置正确

## 💡 快速技巧

```bash
# 只显示编译结果摘要
xcodebuild build | grep -E "BUILD|error|warning"

# 后台编译并通知
xcodebuild build && afplay /System/Library/Sounds/Glass.aiff

# 编译并自动刷新 Finder
xcodebuild build && touch build/

# 创建压缩版本
cd build/Release && zip -r i3Chat.zip i3Chat.app && ls -lh i3Chat.zip
```

## ✨ 功能特性

✅ 完全的 Xcode 集成  
✅ Debug 和 Release 配置  
✅ 代码签名配置  
✅ 本地化支持  
✅ 完整的框架链接  
✅ 优化编译设置  

---

**最后更新**：2026年4月18日  
**Xcode 版本**：14.3+  
**macOS 版本**：10.13+

