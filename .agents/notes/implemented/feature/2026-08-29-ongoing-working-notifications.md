# Agent Note: Working 会话的常驻系统通知（ongoing 生命周期）

Status: implemented

## Problem

后台 agent 长时间运行时，用户在系统层面完全看不见"哪些会话在干活"：
既没有常驻行（此前的通知全是瞬时的 toast/系统通知，划过即失），完成后
若不打开 app 也无从回访；且 `NotificationDetector` 只认 approval 与
planReview 两类 pending，question 等待此前完全不进任何通知通道。用户
要求给每个 working 会话一条 Android 常驻（ongoing）通知，走完
WORKING→WAITING→DONE→已读消失的完整生命周期。

## Decision

每会话一条、状态机 declarative 的常驻通知管线：

- **纯 fold**（`app/lib/notifications/working_sessions_fold.dart`）：
  输入 `List<SessionSummary>` + selectedSessionId + 是否前台，输出每会话
  期望态 `gone/working/waiting(子态)/done`。无状态、无 Flutter 依赖。
  **边沿复用 domain 的 `completed` 位**（adapter 已折叠 running→false 且
  非打开态才置位、`openSession`/重新 running 即清），fold 不再自造边沿——
  这是与 `NotificationDetector`（自持 `_lastRunning`）的关键差异：常驻是
  "当前期望态"的投影，冷启动也要能直接挂出 working/done，故取声明式。
- **确定性 id**（`app/lib/notifications/notification_key.dart`）：
  FNV-1a(32) over `"$backendId/$sessionId"` 的 UTF-8 字节 `& 0x7FFFFFFF`，
  tag = 同一键字符串。进程重启后新进程能原地替换/取消旧进程留下的
  ongoing 行，计数器 id 会留下无法指认的孤儿。启动即全量 reconcile 是
  孤儿兜底路径。
- **SystemNotifier**：plugin 构造注入 seam；新方法 `showWork` /
  `updateWorkBody`（silent ongoing channel `"working"`，low importance、
  ongoing、onlyAlertOnce、autoCancel false）、`promoteWorkToDone`（同 id
  原地替换——插件同 id re-show 连 ongoing flag 一起换——落到现有
  `"turns"` channel，non-ongoing + autoCancel，onlyAlertOnce 避免与瞬时
  事件二次响铃）、`cancelWork`（按 (id, tag)）。initialize 显式创建
  `"working"` channel（低优先级/静音，不依赖首条 show 的参数）。
- **完成行与瞬时完成通知是同一行**（2026-09-12 补）：`show()` 对两类
  turn-complete 也走会话的确定性 `(id, tag)`，`promoteWorkToDone` 的
  title/body 改为与瞬时完成行一致（title = `turnCompleteTitle`，body =
  会话名 + 工作区）。此前同一件事会留下两行、且 title/body 恰好互换
  （working 行 title = 会话名，瞬时行 title = 事件名），用户看到的是
  "两条互不相关却内容对调"的通知。审批/审阅保留计数 id：它们与常驻行
  并存，是不同的事实。
- **先 reconcile 再 route**（2026-09-12 补）：`_onSessions` 把
  `_reconcileWorking()` 提到瞬时事件路由之前。完成通知与常驻行共用坐标，
  顺序决定结果：先 reconcile，fold 先把 done 提升到位（或撤掉会话不再要
  的行），瞬时投递落在已稳定的状态上；反过来路由，"用户开着的会话在后台
  完成"会被 fold 判 `gone` 并立刻 `cancelWork` 掉刚投递的通知。
- **启动即未确认全清**（2026-09-12 补）：`sweepStaleRows(enabledBackendIds)`
  改为 `clearUnconfirmedRows()` —— 取消 ledger 里的**全部**行，而不是只清
  禁用/删除 backend 的行。ledger 记录的是"上一个进程发了什么"，本进程对
  它一无所知（会话可能已完成，主机也可能不可达而永远拿不到快照），而
  ongoing 行不可滑动删除，留下就是永久疤痕。代价：主机可达时会有一瞬
  "消失→重现"。第一份真实快照按 fold 重新挂。
- **AppNotificationCenter**：订阅会话流 + 选中变化流 +
  `appLifecycleChangesProvider`（providers.dart 的 WidgetsBindingObserver
  失效信号），每次全量跑 fold 与"上次已应用态"做 diff，只在变化处发
  notifier 调用。OS 滑掉不可观测，diff 语义保证已显示的 done 不因快照
  重放而复活；重新 running 会重新挂常驻。前台且被观看的会话不挂
  （沿用 selected 静默规则，"被观看" = 选中 + Chat destination 激活，
  见 [通知中心](2026-08-20-notification-center.md) 的 watched 事实；
  done 不受此抑制——completed 位本就不为打开
  态arming）。**子代理会话不是一等通知主体**：`_onSessions` 先按
  `parentSessionId == null` 过滤，瞬时 detector 与常驻 fold 都只见根会话
  （被委托的回合由根会话的 running/pending 说话），child 从 `live` 集合
  离场顺带触发孤儿清理，旧版留下的 child 常驻行会被自动 cancel。已读单
  一挂接点 = SelectSession→`repository.openSession`
  （清 completed 位），三个入口（列表点击、通知 tap、冷启动 target）
  全部汇于此处，中心只是观察 selectedSessionId/快照变化。
- **l10n**：新键 `workingChannel`（对齐既有 `approvalChannel` 命名习惯，
  非 `workingChannelName`）、`workingChannelDescription`、
  `workingNotificationBody`、`waitingApprovalBody`、`waitingPlanReviewBody`、
  `waitingAnswerBody`；done 复用 `turnCompleteTitle`。en/zh 同改，
  gen-l10n 重跑。
- 无 FCM：进程被杀后通知停止更新，重启后 reconcile 接管。后台**执行**保活
  不在本 note 的范围内：需求当时只是可见性，2026-09-11 起由
  [后台保活前台服务](2026-09-11-background-keep-alive-foreground-service.md)
  以"有在飞的活"为范围提供（对可见性需求的结论不变）。

## Alternatives considered

- **单条聚合通知**（"N 个会话在工作中"）：被否，用户要按会话看到"在做
  什么"，且拆成每会话一行天然获得系统的分组折叠。
- **WorkManager / 前台服务**：被否，需求只是可见性而非执行保活，常驻通
  知不需要 FGS 的进程承诺与权限成本。执行保活的需求后来出现，由
  [后台保活前台服务](2026-09-11-background-keep-alive-foreground-service.md)
  另行采纳 FGS；此处对"仅可见性"情形的结论不变。
- **fold 自持 running 边沿**（仿 NotificationDetector）：被否，domain 已
  有 completed 事实，重复造边沿会让冷启动无法直接投影出期望态，且 fold
  不再是可单测的纯函数。
- **递增 id + 内存映射**：被否，重启即孤儿。
- **给 question 补 AppNotificationKind 事件**：不采纳，question 经 WAITING
  常驻进入通知体系（静默展示），瞬时事件管线保持不动；对
  [通知中心](2026-08-20-notification-center.md) 中"question 不触发"构成
  部分覆盖，两处并存。
- **保留两份 doc 行的措辞差异、只修重复投递**：不采纳，两者耦合 —— 只改
  措辞会让同一件事留下两条一模一样的通知，比原来更难理解。
- **按 `updatedAtEpochMs` 判超时清理孤儿常驻行**：被否，长工具调用期间
  该值可能长时间不推进，会误杀正在跑的会话；且超时阈值本身是无依据的
  猜测。启动即未确认全清用已有 ledger 实现同一目标，语义更诚实（"本进程
  无法确认任何上一进程的行"）。

## Consequences

- 自动证据：fold 全边沿/三 pending 子态/selected 抑制纯单测
  （`test/notifications/working_sessions_fold_test.dart`）；id 哈希钉值
  （`notification_key_test.dart`）；notifier seam 断言 ongoing/onlyAlertOnce/
  同 id promote/cancel 带 tag、完成行改用会话坐标、`clearUnconfirmedRows`
  清空全部 ledger 行（`system_notifier_test.dart`）；center 路由与 reconcile
  diff（`app_notification_center_test.dart`）。
- 真机手动证据（不伪造测试）：常驻行滑不掉、WAITING 原地改体不响、
  done 可滑且点后 autoCancel、多会话系统分组、杀进程后重启旧行被清除
  （孤儿清理）、Android 13+ 权限授予前后行为、状态栏小图标为单色剪影。
- 系统设置新增 `"working"` channel（可关，命名走 l10n）；done 与回合
  完成共用 `"turns"` channel，且共用同一行。
- center 现在 watch chatControllerProvider：每 backend 的控制器与其中心
  同生命周期常驻（多 backend 时 timeline/会话订阅不再随切换销毁，与连接
  keep-alive 的既有要求同向）。
- 前后台切换全量 reconcile：回前台清掉正在看的会话的常驻，其余保持。
- 已知取舍：启动全清会让"主机可达且会话确实在跑"的情形出现一次
  消失→重现；这是换取"孤儿行在结构上不可能存在"的代价。
