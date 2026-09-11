# Agent Note: 后台保活前台服务（keep-alive FGS）

Status: implemented

## Problem

应用移入后台或锁屏后连接会断：真实日志里先是
`/api/remote.mux` downlink 关闭，接着 25 秒空档（进程被冻结）后才出现
`Failed host lookup` 与一串 3 秒
`Generation handshake failed: TimeoutException`，最后设置页拉
`api/agentPresets/list` 抛 `Client is already closed`。锁屏时 Android 把
离开前台的进程当 cached process 冻结，Dart isolate 停转，mux 上再无任何
活动，这一代连接静默死亡，回前台只能等退避重连。

通知中心已经把"后台回合跑完也能通知"写进契约
（[通知中心](2026-08-20-notification-center.md)），但没有保活手段时，
该契约在锁屏后不成立。

## Decision

原生 `DshKeepAliveService`
（[MainActivity](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/MainActivity.kt)
注册 `dsh/keep_alive` 通道）：`startForeground` + 低优先级常驻通知 +
`PARTIAL_WAKE_LOCK`。前台服务让进程不再进入 cached 状态，wake lock 让熄屏
后 CPU 继续跑，socket 因此存活到回合结束。

- **FGS 类型**：API 34+ 用 `specialUse`，manifest 同时声明
  `dataSync|specialUse` 与两个权限——API 29–33 不认识 specialUse，走
  `dataSync` 分支。实际启动用的类型永远不受 Android 15 的
  `dataSync` 6h/24h 预算约束；`onTimeout` 仍保留为兜底。
- **范围 = 有在飞的活**：纯谓词
  `sessionHasWorkInFlight`
  （[working_sessions_fold.dart](../../../../flutter/app/lib/notifications/working_sessions_fold.dart)：
  running 或等待用户的根会话）；`AppNotificationCenter` 只在该事实翻转时
  发 `workInFlightChanges`；DI 的 `keepAliveCoordinatorProvider` 合并所有
  启用 backend 的事实驱动
  [KeepAliveCoordinator](../../../../flutter/app/lib/platform/keep_alive_coordinator.dart)。
  空闲锁屏不保活。
- **去重 + 30s linger**：回合刚结束就来的下一轮（队列、目标循环）复用同
  一个 service，避免 Android 12+ 拒绝"后台启动前台服务"；启动被拒只记
  warning，等 lifecycle resume 信号重试。宿主没有通道（桌面、widget 测试）
  时静默惰性。
- **文案走 ARB**：新增 `keepAliveChannelName/Description` 与
  `keepAliveNotificationTitle/Body`（en/zh 同改，gen-l10n 重跑），Dart 把
  解析好的标题/正文/渠道名传给原生，Kotlin 不写死用户可见文本。

## Alternatives considered

- **WorkManager / 前台服务**：在
  [常驻工作通知](2026-08-29-ongoing-working-notifications.md) 里被否决，但
  那次否决只针对"可见性"需求——常驻通知不需要保活。现在需求是"执行保
  活"（锁屏后回合要跑完并通知），前提变了，故重新采纳 FGS，两条 note 并存
  交叉引用（部分取代）。
- **只按 lifecycle 开关，不接工作事实**：FGS 变成常开，后台永远挂一条通
  知；且从后台启动 FGS 在 Android 12+ 可能被拒。按"有在飞的活"限定范围，
  通知只在该出现的时候出现。
- **Android 15 `dataSync` 类型**：6h/24h 是累计预算，重度用户当天耗尽后
  保活再也起不来，恰在最需要它的场景失效；`specialUse` 无此上限。
- **只做 lifecycle 感知重连（不保活）**：解锁瞬间恢复、少刷屏，但锁屏期
  间的回合仍然断，通知契约仍不成立。
- **WifiLock / 引导关闭电池优化**：WifiLock 的权限与语义收益不明确（有流
  量时现代 Android 本就保持 Wi-Fi），白名单引导要新增设置页；两者都不做，
  Doze 仍是已知边界。

## Consequences

- 有在飞的活时锁屏/切后台：连接保持，回合照常完成并进入系统通知；活干完
  30 秒后服务停止、通知消失。空闲时后台仍会断，靠既有退避在回前台时重连。
- 新增权限 `FOREGROUND_SERVICE`(`_DATA_SYNC`/`_SPECIAL_USE`)、`WAKE_LOCK`；
  新增系统通知渠道 `keep-alive`（用户可在系统设置关闭）；F-Droid 需接受
  `specialUse` 子类型声明。
- 证据：`test/platform/keep_alive_coordinator_test.dart`（去重、linger、拒
  绝后重试、无通道静默、dispose）、`test/platform/keep_alive_service_test.dart`
  （通道方法与两种失败形态）、fold 谓词与 center 边沿测试；Kotlin/Manifest
  由 debug APK 构建验证。
- 已知边界：Doze（设备静止且熄屏约 30 分钟后）仍会挂起网络；空闲重连窗口
  内仍可能出现"用已关闭 transport"的 `Client is already closed`，那是
  [远程 mux 单下行](../bug-fix/2026-09-11-remote-mux-sole-downlink.md) 之外
  的独立缺陷，未在本变更中处理。
