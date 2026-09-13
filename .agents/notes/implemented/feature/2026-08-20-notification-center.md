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
  "被观看会话自己 turn 完成"（用户正在看，静默）外走 toast 流。
  `shouldNotifyForeground` 三态拆成显式 `NotificationChannel` 枚举，
  避免"前台选中完成被误发系统通知"的歧义。
  **"被观看"事实**（`app/lib/notifications/watched_session.dart` +
  `watchedSessionIdProvider`）：web 的"选中即静默"假设会话面板常驻
  屏幕，手机的三 destination 互斥全屏——选中会话仅在 Chat destination
  激活时才算被观看；用户在 Workspaces/Settings 页时选中会话的 turn
  完成照常 toast。中心的 `selectedSessionIdOf` 轮询该事实，其变化
  （选择 + destination 切换）同时是 reconcile 的失效信号。
- **系统通知**（`app/lib/notifications/system_notifier.dart`，由
  `TurnCompleteNotifier` 扩展）：按事件类型分区（turns/approvals/reviews），
  高重要度给待审批/待审阅；`NotificationTarget` 把 backend+session 编码进
  payload，支持通知点击深链（`getNotificationAppLaunchDetails` 冷启动 +
  `onDidReceiveNotificationResponse` 运行时）。
- **前台 toast**（`app/lib/notifications/notification_toast.dart`）：
  顶部可点击横幅，`AppRoot` 用 `Stack` 叠加渲染；点击跳转到目标会话
  （切 backend → `SelectSession` → 切到 chat destination）。
- **通知入口落在最新消息**（2026-09-12 补）：`SelectSession` 携带
  `landAtLatest`，控制器把每次选中请求发布为 `selectionRequestSeq` +
  `selectionLandsAtLatest` 两个事实，`_ChatPanelState` 据此在"同一会话被
  重新选中"时也重新绑定并跳到时间线尾部（`_bindSession(landAtLatest:)`
  跳过持久化阅读位置的读取）。此前两个缺陷：通知指向当前已打开的会话时
  `selectedSessionId` 不变，`didUpdateWidget` 不重绑，界面毫无反应；改了
  会话时又恢复上次阅读位置，恰好把通知要说的那条消息藏在下面。列表点击
  仍是 `landAtLatest: false`，断点续读不变。
- **点击按事件流投递，不按 provider 状态**（2026-09-12 补）：
  `systemNotificationTargetsProvider` / `foregroundNotificationEventsProvider`
  由 `StreamProvider` 改为 `Provider<Stream<…>>`，`AppRoot` 在 `initState`
  直接订阅。原因：同一会话的常驻行与完成通知 payload 相同，同一会话两次
  完成的事件也相等，`ref.listen` 对 `AsyncValue` 的相等判断会把第二个
  整个吞掉（"点了通知没反应"）。前台通道在 build 里 watch + 按流实例重订阅，
  以跟随 backend registry 变化后的新流。
- **一次完成只有一行**（2026-09-12 补）：turn 完成这类瞬时投递改走会话的
  确定性 `(id, tag)`（与常驻 fold 同一坐标），审批/审阅仍用计数 id；
  `AppNotificationCenter._onSessions` 改为**先 reconcile 再 route** —— 否则
  "用户开着的会话在后台完成"会被 fold 的 `gone` 立刻 `cancelWork` 掉
  （已打开会话的 `completed` 位不 arm）。
- **通知文案约定**（2026-09-12 补）：瞬时事件行/toast 的 title 说"发生了什么"、
  body 说"哪个会话（+ 工作区）"；运行/等待常驻行反过来（title = 会话名，
  body = 状态），因为多会话并行时"哪个会话"才是主信息。完成行与瞬时行是同
  一事实，共用措辞。正文由 `notificationBodyLine(title, context)` 单点组合，
  toast 与系统通知不可能漂移。工作区上下文来自 domain 新增的
  `SessionSummary.workspaceLabel`，且仅当它不等于 `displayTitle` 时才拼。
- **小图标**：`AndroidInitializationSettings('@drawable/ic_stat_dsh')` ——
  Android 从 alpha 通道渲染通知小图标，用 `@mipmap/ic_launcher` 会渲染成
  白块；`ic_stat_dsh` 是既有的单色剪影，保活前台服务一直在用。
- **权限请求移出启动路径**（2026-09-12 补，取代原"initialize 时请求"）：
  `SystemNotifier.initialize()` 不再请求权限。改为首个"有 agent 工作在飞"
  时就地请求：`AppRoot` 订阅 `workInFlightChangesProvider`（`KeepAliveCoordinator`
  新增的工作在飞事实，非服务状态），先弹一次自建说明（`AlertDialog`），
  用户确认后才花掉 Android 的那次系统弹窗，并用 `NotificationPermissionGate`
  把"已说明过"记进设备本地存储，不重复打扰。理由：Android 在两次拒绝后不再
  弹窗，首次启动、屏幕上什么都没有时的请求正是用户会拒的那个。
- **通知失败进错误日志**（2026-09-12 补）：`SystemNotifier` 四处裸
  `catch (_)` 改为 `_reportFailure(...)` → `ErrorLogCollector`（warning，
  context 带 component/call）。仍然不向聊天界面抛，但"通知不弹"不再是
  现场无法诊断的事。
- **通知文案跟随 App 内语言**（2026-09-12 补）：通知在 widget 树之外组装，
  读不到 `MaterialApp.locale`。`applyLocale` 由 `notificationLocaleSyncProvider`
  在语言偏好变化时推送；保活文案的 resolver 改为按调用时 `ref.read`
  （不能 watch —— 那会让 coordinator 因语言变化重建并重启前台服务）。
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
  会话/审批/plan，避免打扰正在盯着的会话。"正在看"由 watched 事实定义
  （选中 + Chat destination 激活）：destination 切走后同一会话的完成
  照常通知，web 假设在手机上不成立。
- **保留 ChatController.onTurnComplete**：会让 turn 完成检测分散两处
  （controller 钩子 + 中心），可能重复通知；统一收进中心。
- **浏览器 Notification API（web）**：本客户端只有 Android 平台目录，
  系统通知用 flutter_local_notifications 的 Android 通道。
- **不用 pendingInteraction、只做 turn 相关**：放弃审批/plan 两个用户
  明确选择的触发点；不采纳。
- **把"落在最新"做成屏幕对通知的专用分支**（例如 `AppRoot` 直接向
  transcript 发一个滚动指令）：会让空间行为脱离它自己的数据来源。改为
  控制器发布"这次选中请求要求落在最新"这一事实，屏幕自己决定空间响应，
  维持"adapter/控制器出事实，app 定布局"的边界。
- **保留 `StreamProvider` + `ref.listen`，只在测试里放宽断言**：Riverpod
  对 `AsyncValue` 的相等判断是缺陷本身，不是断言的问题；改成直接订阅事件流
  才是消除整类丢事件的做法。
- **给"已有完成通知还在通知栏"的重复点击加特例**：不采纳。两次点击同一
  目标是两次真实用户意图，事件流天然都送到。
- **继续在 `initialize()` 里请求权限**：屏幕还没画一帧就弹系统对话框，
  且 Android 的弹窗次数有限；改为就地请求 + 先说明。
- **按 `updatedAtEpochMs` 判超时来清理孤儿常驻行**：长工具调用期间该值
  可能长时间不推进，会误杀正在跑的会话；见常驻通知那条 note 的取舍。
- **把通知正文的"要批准什么"（工具名/命令）一并做掉**：需要 adapter 在
  `_trackPending` 保留 approval 帧请求体、domain 加字段并更新 `docs/spec.md`，
  与本次的导航/文案修复不同层，另开一片。

## Consequences

- 四类事件在前后台都有通知通道；前台 toast 可点击直达会话，后台系统通知
  可点击深链。
- `ChatController` 不再承担通知职责（`onTurnComplete` 移除），其测试同步
  更新；`NotificationDetector`/`channelFor`/`NotificationTarget` 为纯函数/
  纯数据，可直接单测。
- 系统通知在 Android 13+ 需要用户授予通知权限（manifest 已声明）；权限由
  首个有工作在飞的时刻就地请求（先自建说明，再花系统弹窗），被拒时记录进
  错误日志并保持静默——"未授权仍静默不弹"不变，但不再无人知晓。
- 通知中心是每 backend 的 autoDispose provider，由 AppRoot 的合并流保持
  存活，后台 turn 也能折叠出系统通知（受 Android 后台执行约束，尽力而为）。
- 通知入口（toast 点击、系统通知点击、冷启动深链）一律落在会话的最新消息；
  列表点击仍恢复持久化阅读位置。三条入口共用 `AppRoot._navigateToTarget`，
  该处改为 await backend registry 后再判定，顺带堵掉"registry 未就绪时
  复活已删除 backend 连接"的路径。
- 重复事件不再被吞：通知点击与前台事件两条通道都是直接订阅的流。
- 文案断言从英文原句改为经 l10n 解析的 key（`system_notifier_test.dart` 的
  test host locale 解析），改动文案时测试跟随。
- **已知缺口（本批明确未做）**：自建说明只出现一次，用户在说明里选"以后再说"
  后既没有花掉系统弹窗，也没有任何应用内入口再把通知打开（设置页还没有通知
  分区）。也就是说"以后再说"是事实上的永久关闭。恢复入口属于设置页那一批，
  在此之前该文案不承诺可随时开启。
- 小图标改用 `ic_stat_dsh` 后，状态栏/通知栏的小图标从启动图标白块变为单色
  剪影；保活前台服务通知一直用的就是这个资源。
- pendingInteraction 折叠与主工作区未提交实现同源；主工作区合并时若与
  本分支同段代码冲突，内容相同可平凡解决。
