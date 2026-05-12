# i3Chat Xcode 工程

本目录包含为 i3Chat IRC 客户端生成的 Xcode 工程文件。

## 工程结构

```
i3Chat.xcodeproj/
├── project.pbxproj          # Xcode 项目配置文件
└── xcshareddata/xcschemes/  
    └── i3Chat.xcscheme      # 构建方案
```

## 编译配置

该工程基于原有的 Makefile 配置进行生成，包含以下特性：

### 编译器设置
- 编译器：clang
- Objective-C ARC：启用
- C 标准：C11
- 优化级别：Debug(0) / Release(s)

### 链接框架
- Foundation.framework
- Cocoa.framework
- AppKit.framework
- QuartzCore.framework

### 头文件搜索路径
- $(SOURCE_ROOT)
- $(SOURCE_ROOT)/IRCClient
- $(SOURCE_ROOT)/Storage
- $(SOURCE_ROOT)/UI
- $(SOURCE_ROOT)/third-party/sqlite

### 部署目标
- macOS 10.13 及以上

## 使用方法

### 方法1：使用 Xcode IDE

1. 在 Xcode 中打开工程：
   ```bash
   open i3Chat.xcodeproj
   ```

2. 选择编译方案：
   - Debug：用于开发调试
   - Release：用于发布版本

3. 按 Cmd+B 编译或 Cmd+R 编译并运行

### 方法2：使用命令行 xcodebuild

**编译Debug版本：**
```bash
xcodebuild -scheme i3Chat -configuration Debug build
```

**编译Release版本：**
```bash
xcodebuild -scheme i3Chat -configuration Release build
```

**编译并运行：**
```bash
xcodebuild -scheme i3Chat -configuration Debug build && open build/Debug/i3Chat.app
```

**清除构建输出：**
```bash
xcodebuild clean
```

## 编译输出

编译后的应用包将位于：
- Debug: `build/Debug/i3Chat.app`
- Release: `build/Release/i3Chat.app`

## 源文件组织

工程中的源文件按以下方式组织：

```
Main
├── main.m                          # 主入口
├── DebugLog.h                      # 调试日志头文件
├── Info.plist                      # 应用配置

IRCClient/
├── IRCClient.m                     # IRC 客户端实现
└── IRCConfig.m                     # IRC 配置

Storage/
├── MessageStorage.m                # 消息存储
├── ServerHistoryStorage.m          # 服务器历史存储
└── StorageConstants.m              # 存储常量

UI/
├── AppDelegate.m                   # 应用代理
├── MainWindowController.m          # 主窗口
├── LoginWindowController.m         # 登录窗口
├── ChatViewController.m            # 聊天视图
├── ChatViewController+*.m          # 聊天视图分类
├── ChannelBuffer.m                 # 频道缓冲
├── ChannelListWindowController.m   # 频道列表窗口
├── LinksListWindowController.m     # 链接列表窗口
├── WhoisWindowController.m         # Whois 窗口
├── HistoryWindowController.m       # 历史记录窗口
├── SettingsWindowController.m      # 设置窗口
└── LocalizationManager.m           # 本地化管理

Resources/
├── AppIcon.iconset/                # 应用图标集
├── en.lproj/                       # 英文本地化
└── zh-Hans.lproj/                  # 简体中文本地化

third-party/sqlite/
├── sqlite3.c                       # SQLite 3 源代码
├── sqlite3.h                       # SQLite 3 头文件
└── sqlite3ext.h                    # SQLite 3 扩展头文件
```

## 常见问题

### 编译错误：找不到头文件

确保 `USER_HEADER_SEARCH_PATHS` 已正确配置。工程已自动设置以下搜索路径：
- `$(SOURCE_ROOT)`
- `$(SOURCE_ROOT)/IRCClient`
- `$(SOURCE_ROOT)/Storage`
- `$(SOURCE_ROOT)/UI`
- `$(SOURCE_ROOT)/third-party/sqlite`

### 链接错误

检查所有源文件（.m 文件）是否都已添加到 Target 的 "Build Phases" → "Compile Sources" 中。

### 代码签名问题

工程配置中代码签名身份设置为 "-"（ad-hoc），可在 Xcode 中修改或使用以下命令行选项：
```bash
xcodebuild -scheme i3Chat CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## 与 Makefile 的对应

| Makefile 特性 | Xcode 配置 |
|---|---|
| OBJCFLAGS (-fobjc-arc -std=c11) | CLANG_ENABLE_OBJC_ARC=YES, GCC_C_LANGUAGE_DIALECT=c11 |
| FRAMEWORKS | Link Binary With Libraries |
| INCLUDES | USER_HEADER_SEARCH_PATHS |
| SOURCES | Compile Sources |
| sqlite3 编译 | 直接包含 sqlite3.c 源文件 |
| 输出文件夹 | SYMROOT=build |

## 许可证

版权 © 2025-2028
