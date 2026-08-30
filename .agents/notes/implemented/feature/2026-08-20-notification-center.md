# Agent Note: 通知中心（前台 toast + 后台系统通知）

Status: implemented

## Problem

后台 agent 完成任务的返回不会变成通知提醒用户。此前 `TurnCompleteNotifier`
只覆盖"选中会话 turn 完成 + 应用在后台"这一种情况，且 Android 13+
缺少 `POST_NOTIFICATIONS` 权限声明（flutter_local_notifications v16+
不再自动合并该权限），系统通知实际从不弹出；前台也没有任何完成通知。
用户要求补齐：主 agent turn 完成、其他会话新内容（未读）、待审批请求、
plan 审阅四类事件，前台用可点击跳转的 toast，后台用系统通知。

## Decision

新增一个 app 侧通知中心，纯事件驱动、控制器无文案：

- **事件模型与检测器**（`app/lib/notifications/notification_events.dart`）：
  `NotificationDetector` 把 `observeSessions()` 的 `List<SessionSummary>`
  快照折叠成 `AppNotificationEvent`（`selectedTurnComplete` /
  `otherTurnComplete` / `approvalRequested` / `planReviewRequested`）。
  首个快照播种不触发（已运行/已等待的会话不是"新"）；running→idle 触发
  turn 完成，`pendingInteraction` 进入 `approval`/`planReview` 触发对应
  等待；`question` 不触发（普通提问不是待办）。会话消失即停止跟踪。
  question 的等待现由 working 会话的常驻通知（WAITING 态）进入通知体系，
  见 [working 会话常驻通知](2026-08-29-ongoing-working-notifications.md)；
  检测器本身仍不发 question 事件。
- **通知中心**（`app/lib/notifications/app_notification_center.dart`）：
  每 backend 一个实例，订阅 `observeSessions()` 折叠事件，按
  `channelFor(event, isForegrounded)` 路由：后台一律走系统通知；前台除
  "选中会话自己 turn 完成"（用户正在看，静默）外走 toast 流。
  `shouldNotifyForeground` 三态拆成显式 `NotificationChannel` 枚举，
  避免"前台选中完成被误发系统通知"的歧义。
- **系统通知**（`app/lib/notifications/system_notifier.dart`，由
  `TurnCompleteNotifier` 扩展）：按事件类型分区（turns/approvals/reviews），
  高重要度给待审批/待审阅；`NotificationTarget` 把 backend+session 编码进
  payload，支持通知点击深链（`getNotificationAppLaunchDetails` 冷启动 +
  `onDidReceiveNotificationResponse` 运行时）。
- **前台 toast**（`app/lib/notifications/notification_toast.dart`）：
  顶部可点击横幅，`AppRoot` 用 `Stack` 叠加渲染；点击跳转到目标会话
  （切 backend → `SelectSession` → 切到 chat destination）。
- **接线**：`providers.dart` 增加 `systemNotifierProvider`（单实例，main 里
  initialize 后 override 注入，修复原先"main 初始化 A、provider 用 B"
  的双实例问题）、`appNotificationCenterProvider`（每 backend）、
  `foregroundNotificationEventsProvider`（合并各 backend toast 流，AppRoot
  监听并保持中心存活）、`systemNotificationTargetsProvider`。
  `ChatController.onTurnComplete` 钩子移除，turn 完成检测统一进中心
  （单一归属，符合"一个异步操作一个生命周期所有者"）。
- **pendingInteraction 折叠搬入**：`SessionSummary.pendingInteraction`
  （domain 字段）与 adapter 的 approval/question 帧折叠
  （`_foldPendingFrame`/`_trackPending`/`_dropPending`/`_projectPending` +
  `combineLatest3`）从主工作区未提交工作照搬进本分支，使审批/plan 两个
  触发点在 master 上即可用（主工作区同一份改动不受影响）。
- **Android 权限修复**：`AndroidManifest.xml` 声明
  `POST_NOTIFICATIONS` + `VIBRATE` —— 这是系统通知在 Android 13+
  真正弹出的前提，也是用户反馈"从不通知"的根因之一。
- **l10n**：新增 en/zh 文案（otherTurnComplete/approval/planReview 标题、
  频道、toast 关闭 tooltip），gen-l10n 重新生成。
- **spec.md**：新增 §4.4 记录 registry 级 pending 折叠（复用 §4.3 的
  approval/question 帧，session 列表层投影）。

## Alternatives considered

- **逐条消息未读计数**：wire 的 `SessionSummary` 无已读/未读计数，
  逐消息跟踪需要为所有会话常驻 timeline 订阅，成本高且参考客户端也没有
  该语义；采用"非选中会话 turn 完成 = 有新内容"作为可靠可观测代理。
- **前台选中完成也 toast**：用户选择"正在看的不通知"；toast 只覆盖其他
  会话/审批/plan，避免打扰正在盯着的会话。
- **保留 ChatController.onTurnComplete**：会让 turn 完成检测分散两处
  （controller 钩子 + 中心），可能重复通知；统一收进中心。
- **浏览器 Notification API（web）**：本客户端只有 Android 平台目录，
  系统通知用 flutter_local_notifications 的 Android 通道。
- **不用 pendingInteraction、只做 turn 相关**：放弃审批/plan 两个用户
  明确选择的触发点；不采纳。

## Consequences

- 四类事件在前后台都有通知通道；前台 toast 可点击直达会话，后台系统通知
  可点击深链。
- `ChatController` 不再承担通知职责（`onTurnComplete` 移除），其测试同步
  更新；`NotificationDetector`/`channelFor`/`NotificationTarget` 为纯函数/
  纯数据，可直接单测。
- 系统通知在 Android 13+ 需要用户授予通知权限（manifest 已声明，插件
  initialize 时请求）；未授权时静默不弹（与既有吞错策略一致）。
- 通知中心是每 backend 的 autoDispose provider，由 AppRoot 的合并流保持
  存活，后台 turn 也能折叠出系统通知（受 Android 后台执行约束，尽力而为）。
- pendingInteraction 折叠与主工作区未提交实现同源；主工作区合并时若与
  本分支同段代码冲突，内容相同可平凡解决。
