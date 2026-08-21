# Agent Note: dev 崩溃采集包（日志环形缓冲 + 崩溃标记 + 重启检测 + intake 上报）

Status: implemented

## Problem

debug 构建在真机/模拟器上崩溃后，没有任何崩溃信息离开设备：日志只在
logcat，异常细节不落盘，下一次启动也不知道"上次崩了"。pi-crash-intake
服务端已经就绪（triage 建 Issue、去重、按 source.commit 拉源码自修复），
但**喂数据的客户端不存在**。本任务补齐 App 侧：debug 构建崩溃 → 本地记录
→ 重启后上报 intake，payload 携带版本信息契约（app/version/build +
source{repo,commit} + 堆栈 + 日志尾部），让自修复循环吃到真实崩溃。

## Decision

新增 workspace 包 `flutter/packages/dev/`（零 domain/network/adapter
依赖，只依赖 flutter + http + path_provider），app 在 `main()` 以
`kDebugMode` 门接入：

- **`LogBuffer`**：固定容量（默认 200 行）环形日志缓冲，行带 ISO 时间戳；
  供 app 在未来把关键路径日志喂进去。内存态。
- **`CrashMarker`**：崩溃发生瞬间**同步写盘**（`writeAsStringSync` +
  `flush: true`）的 JSON marker，内容是完整 crash bundle——进程可能马上
  死，异步上报不可靠，同步落盘保证不丢；`takeIfPresent()` 读+删一步完成
  （上报失败不重报）。写盘失败静默（崩溃处理器绝不能再崩）。
- **`CrashReporter`**：`POST {intake}/api/crash`（http，可注入 client 供
  测试断言 wire）；网络失败/非 2xx 返回 false 不抛。
- **`DevCrashBootstrap`**：安装 `FlutterError.onError` +
  `PlatformDispatcher.instance.onError` 钩子（链到旧 handler，不改变 app
  现有错误行为），崩溃时写 marker；`start()` 时读上次 marker → 重启检测
  → 回调 `onRestartDetected`（默认 fire-and-forget 上报）。`kReleaseMode`
  拒绝安装。
- **App 接线**（`app/lib/main.dart` + `app/lib/config.dart`）：
  `kDebugMode` + 非 `FLUTTER_TEST` 环境才初始化；path_provider 失败静默
  降级（采集绝不影响启动）；`config.dart` 增加 dart-define 契约：
  `PICRASH_INTAKE_URL`（默认 `http://10.0.2.2:9876`，模拟器宿主）、
  `DSH_SOURCE_COMMIT`（构建时 `git rev-parse HEAD` 注入，**自修复循环的
  关键**）、`DSH_SOURCE_REPO`、`DSH_APP_VERSION`、`DSH_BUILD_NUMBER`。
- **Payload 契约对齐 intake**：`src/triage-context.ts`（pi-crash-intake）的
  CrashBundle 字段一一对应 mirror（app/version/build/platform/device/
  dshBaseUrl/sessionId/source{repo,commit}/crash{type,message,stackFrames,
  occurredAt}/logs）；`crash_bundle_test.dart` 显式断言每个键。

## Alternatives considered

- **崩溃时直接异步上报**（不写 marker）。Rejected：进程死亡时异步 HTTP
  大概率发不出去；marker+重启上报把"采集"和"传输"解耦，传输失败还可重试。
- **用 `runZonedGuarded` 包整个 app**。Rejected：会改变现有 zone 语义，
  且覆盖面不比两个官方钩子更广；两个钩子已覆盖框架错误 + 未捕获异步。
- **dev 包依赖 domain/harness_adapter 复用版本模型**。Rejected：版本信息
  是编译期 dart-define 注入（`String.fromEnvironment`），运行时模型反而
  引入层间耦合；dev 保持自足、app 通过 config 喂数据。
- **collection 包做环形缓冲**。Rejected：零依赖约束，手写 60 行足够。
- **release 构建也采集（接线上崩溃服务）**。Rejected：本任务只做 debug
  开发循环；release 需要正经崩溃平台（如 Play Console），不在范围。

## Consequences

- debug 构建崩溃后下次启动会上报到 intake；release 构建行为不变
  （`kDebugMode` 分支 + `kReleaseMode` 拒绝安装双重保护）。
- 构建命令需要注入 `--dart-define=DSH_SOURCE_COMMIT=$(git rev-parse HEAD)`
  才有意义的自修复；默认 'unknown' 时 intake 跳过 fix 阶段。
- marker 是单文件 JSON，位于 app documents 目录；无上报确认机制（上报
  失败即丢弃），后续可加"待上报队列"（marker 保留 + 退避重试）。
- `device`/`sessionId` 目前是默认值/空（未接设备信息插件与 session 状态）；
  通过 bootstrap 的 `deviceProvider`/`sessionIdProvider` 注入即可补全。
- 包名 `dev` 是 workspace 保留词冲突时需改名（当前无冲突）。