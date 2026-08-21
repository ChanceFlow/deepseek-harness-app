# Agent Note: debug 遥测打点 — 踢掉 pi-crash-intake,统一走 OTLP/SigNoz

Status: implemented

## Problem

Debug 构建需要把 log、事件打点、metric、帧率、崩溃全部收集起来用于排查,
且只在 dev 包自动嵌入(release 零残留)。此前仓库只有一套 intake 崩溃链
(`flutter/packages/dev` + pi-crash-intake 服务器,见被取代的
`2026-08-21-dev-crash-capture.md`):崩溃 POST 到自建 intake,遥控测
(log/event/metric/帧率)完全空缺 —— 官方 `opentelemetry_otlp` 在 Dart 3
下又无法解析,不能直接接 OTLP。经与用户讨论定案:踢掉 intake(仓库内
intake 代码全删),崩溃与遥测统一走 OTLP/HTTP 到自托管 SigNoz。

## Decision

`flutter/packages/dev` 从"崩溃采集包"扩展为**唯一的 debug-build tooling
包**(kDebugMode 门闸 + FLUTTER_TEST 跳过,release 零编译,沿用既有模式):

- **传输 = OTLP/HTTP → SigNoz**,客户端用 `dartastic_opentelemetry`
  (Apache-2.0,社区 fork,`^0.9.8`;官方 `opentelemetry_otlp` 仍是
  0.5.0-dev 且 SDK 约束 `<3.0.0`,Dart 3 解析失败 —— 冻结为拒绝选项)。
  `TelemetrySettings.endpoint` 来自 `DSH_DEBUG_OTLP_URL`(app
  config.dart,默认 `http://10.0.2.2:4318`,真机走 dev 机内网 IP;
  cleartext 在 debug manifest 已放行,零改动)。
- **Facade** `DebugTelemetry`(app 唯一接触面):`log(level, msg)` →
  OTel log record;`event(name, attrs)` → log record + eventName(每秒
  事件速率上限,滑动窗口采样);`count`/`record`/`setGauge` →
  counter/histogram/gauge,SDK 的 `PeriodicExportingMetricReader`(15s)
  做本地聚合导出;`reportCrash` → severity FATAL log record。全部吞错,
  遥测绝不影响 app。
- **崩溃链保留但换传输**:`CrashMarker` 同步落盘(垂死进程场景,写失败
  静默)+ 重启检测(`takeIfPresent` 上报后删除)+ 钩子链(`FlutterError
  .onError` / `PlatformDispatcher.instance.onError` 让位旧 handler);
  `CrashBundleWire`/`CrashReporter`(intake POST)删除,`CrashRecord`
  自足 JSON(无外部 schema),上报 = FATAL log record,属性携带
  provenance(缺省 'unknown' 时 SigNoz 无法定位源码,不阻塞)。
- **帧率**:`WidgetsBinding.addTimingsCallback` 采 `FrameTiming` →
  `app.frame.total_ms` histogram(逐帧)+ `app.frame.jank_total`
  counter(>16.7ms)+ `app.frame.fps` gauge(每秒);`FrameStatsAccumulator`
  纯函数可单测。
- **打点示例**:`main.dart` 初始化后打 `app.start` 事件;业务级打点按需
  在控制器调 facade(后续任务)。
- **删除 intake 足迹**:config.dart `PICRASH_INTAKE_URL`、dev 包
  crash_bundle/crash_reporter、README 段落、旧笔记(本笔记承接理由)。

## Alternatives considered

- **官方 `opentelemetry_otlp`**。Rejected:0.5.0-dev 预发布 + sdk 约束
  `<3.0.0`,probe 证实 `pub get` 无法解析;官方主线在 Dart 3 断供。
- **`sentry_flutter`(错误/性能/metrics 全家桶)**。Rejected:锁定 Sentry
  协议与后端;团队无 Sentry 实例;与"自托管 SigNoz + OTLP 开放标准、
  将来可进生产"的方向冲突。
- **扩展 pi-crash-intake 收遥测**。Rejected:用户定案踢掉 intake;一个
  自研协议服务器不值得为 dev 遥测扩协议,OTLP 是现成标准。
- **新建 `debug_tools` 包**。Rejected:与 dev 包职责重叠(两个 debug 包
  即混乱);dev 已是既定 debug 门闸/打点管线,遥测并入它是自然演化。
- **posthog_flutter**(事件打点+可自托管)。Rejected:无 trace/帧率/指标
  深度,且重复 OTel 已覆盖的事件面。
- **崩溃只在 capture 时异步上报(不写 marker)**。Rejected:垂死进程异步
  HTTP 大概率发不出;marker+重启上报把采集与传输解耦(旧笔记理由,保持)。

## Consequences

- debug 构建:log/event/metric/帧率/崩溃全部 OTLP→SigNoz(默认
  `10.0.2.2:4318`),崩溃标记文件照旧在 app documents 目录;release
  构建零残留(kDebugMode const 分支 + `kReleaseMode` 拒绝安装)。
- `packages/dev` 依赖变为 flutter + dartastic_opentelemetry(app 侧
  path_provider 传目录);intake 相关的 dart-define 全删,新增
  `DSH_DEBUG_OTLP_URL`。
- SigNoz 需在 dev 机跑起来(compose 在 ~/services/,不入库);OTLP
  端口 4318。遥测失败全部静默降级,不影响 app。
- 已知取舍:dartastic 社区小(25★),若 fork 出问题,备选是手写最小
  OTLP exporter(protobuf 包可用、不违反无 codegen 规则);dartastic
  的 metrics/logs 信号仍带实验性标记,当前行为经测试固定。
- `device`/`sessionId` 仍走 bootstrap 注入填空值,未接设备信息插件与
  session 状态(与旧笔记同取舍)。