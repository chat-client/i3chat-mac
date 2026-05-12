//
//  DebugLog.h
//  i3Chat
//
//  统一的日志开关控制
//

#ifndef DebugLog_h
#define DebugLog_h

// ============================================
// 全局日志总开关：设置为 0 可关闭所有调试日志
// ============================================
#ifndef DEBUG_LOG_ENABLED
#define DEBUG_LOG_ENABLED 0
#endif

// ============================================
// 各模块日志开关（仅在 DEBUG_LOG_ENABLED=1 时生效）
// ============================================

// IRC 客户端协议日志
#ifndef IRC_DEBUG_LOG
#define IRC_DEBUG_LOG 0
#endif

// 频道列表窗口日志
#ifndef CHANNEL_LIST_DEBUG_LOG
#define CHANNEL_LIST_DEBUG_LOG 0
#endif

// 聊天视图控制器日志
#ifndef CHAT_VIEW_DEBUG_LOG
#define CHAT_VIEW_DEBUG_LOG 0
#endif

// 主窗口控制器日志
#ifndef MAIN_WINDOW_DEBUG_LOG
#define MAIN_WINDOW_DEBUG_LOG 0
#endif

// 登录窗口控制器日志
#ifndef LOGIN_WINDOW_DEBUG_LOG
#define LOGIN_WINDOW_DEBUG_LOG 0
#endif

// 存储模块日志（MessageStorage, ServerHistoryStorage）
#ifndef STORAGE_DEBUG_LOG
#define STORAGE_DEBUG_LOG 0
#endif

// AppDelegate 日志
#ifndef APP_DELEGATE_DEBUG_LOG
#define APP_DELEGATE_DEBUG_LOG 0
#endif

// 聊天消息窗口性能分析（displayMessagesForChannel 各阶段耗时）
#ifndef CHAT_PERF_DEBUG_LOG
#define CHAT_PERF_DEBUG_LOG 0
#endif

// 是否输出重复的性能日志（用于对比不同宏路径）
// 0 = 默认关闭（避免重复输出）
// 1 = 启用非宏块的重复日志
#ifndef CHAT_PERF_DUPLICATE_LOG
#define CHAT_PERF_DUPLICATE_LOG 0
#endif

// 性能测量开关（控制是否进行性能测量，而不仅仅是日志输出）
// 当设置为 0 时，所有性能测量代码会被优化掉，避免性能开销
#ifndef CHAT_PERF_MEASURE_ENABLED
#define CHAT_PERF_MEASURE_ENABLED 0
#endif

// ============================================
// 日志宏定义
// ============================================

#if DEBUG_LOG_ENABLED && IRC_DEBUG_LOG
#define IRCLog(...) NSLog(__VA_ARGS__)
#else
#define IRCLog(...) do {} while(0)
#endif

#if DEBUG_LOG_ENABLED && CHANNEL_LIST_DEBUG_LOG
#define CHLog(...) NSLog(__VA_ARGS__)
#else
#define CHLog(...) do {} while(0)
#endif

#if DEBUG_LOG_ENABLED && CHAT_VIEW_DEBUG_LOG
#define CVLog(...) NSLog(__VA_ARGS__)
#else
#define CVLog(...) do {} while(0)
#endif

#if DEBUG_LOG_ENABLED && MAIN_WINDOW_DEBUG_LOG
#define MWLog(...) NSLog(__VA_ARGS__)
#else
#define MWLog(...) do {} while(0)
#endif

#if DEBUG_LOG_ENABLED && LOGIN_WINDOW_DEBUG_LOG
#define LWLog(...) NSLog(__VA_ARGS__)
#else
#define LWLog(...) do {} while(0)
#endif

#if DEBUG_LOG_ENABLED && STORAGE_DEBUG_LOG
#define SLog(...) NSLog(__VA_ARGS__)
#else
#define SLog(...) do {} while(0)
#endif

#if DEBUG_LOG_ENABLED && APP_DELEGATE_DEBUG_LOG
#define ADLog(...) NSLog(__VA_ARGS__)
#else
#define ADLog(...) do {} while(0)
#endif

#if CHAT_PERF_DEBUG_LOG
#define CVPerfLog(...) NSLog(__VA_ARGS__)
#else
#define CVPerfLog(...) do {} while(0)
#endif

// 性能测量宏：仅在 CHAT_PERF_MEASURE_ENABLED 开启时执行测量代码
// 支持单行和多行代码块
#if CHAT_PERF_MEASURE_ENABLED
#define CHAT_PERF_MEASURE(...) __VA_ARGS__
#else
// When disabled, expand to nothing (empty statement)
#define CHAT_PERF_MEASURE(...)
#endif

#endif /* DebugLog_h */
