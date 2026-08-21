# ADR-0001: 用 Flutter 全量重写客户端（路线 A：同仓 monorepo）

- 状态：Accepted
- 日期：2026-08-18（迁移 Round 1，分支 `flutter-rewrite`）
- 决策依据：仓库改版前的迁移分析（未随本仓库公开）

## 背景

仓库现状是 100% Kotlin + Jetpack Compose 的原生 Android 客户端，MVP 已收口
（40/48 host RPC、81 个 JVM 测试全绿、真机 e2e 通过）。原章程（README Goals、
PLAN 第 1 节、docs/spec.md Non-Goals）三处明文"无 RN/Flutter"。

分析结论：若需要第二平台（iOS/桌面/Web），Flutter 是唯一可行路线；技术可行性高
——11,273 行 Kotlin 中约 70%（domain/network/adapter 非 UI 部分）是零或低平台
依赖的机械翻译，且本项目架构（防腐层、纯函数 reducer、零 UI 依赖 markdown
解析器）本就为可移植性设计。但这是**全量重写而非增量迁移**：add-to-app 绞杀者
模式对单人项目是负收益（wire 层两份/双 UI 栈/桥接维护成本）。

## 决策

1. **动机确认为跨平台**，采纳路线 A：同仓 monorepo 全量重写。
2. checkout `flutter-rewrite` 分支执行；`flutter/` 目录承载 pub workspace
   四包（app、domain、network、harness_adapter），依赖方向与 legacy 四模块
   一一对应：`app → domain ← harness_adapter → network`。
3. legacy Kotlin 栈（`app/`、`core/`、Gradle 文件）**冻结**：平价前只修 P0
   bug，不新增能力；平价判据达成后一次删除。
4. 平价判据（可度量，缺一不删 legacy）：
   - 40/48 host RPC 覆盖（未覆盖 8 项与 legacy 完全一致）；
   - 81 个 legacy JVM 测试语义等价移植全绿；
   - opt-in real-host e2e（`DSH_E2E_URL`）冒烟 PASS；
   - import 门禁（Dart 版扫描 `import 'package:…'`）CLEAN。
5. 技术选型：Flutter 3.47.0 stable / Dart 3.13；Riverpod 3.x（状态+DI 二合一）；
   `http` + `web_socket_channel`；`freezed` + `json_serializable`；
   markdown 解析器直译为纯 Dart（**不采用** discontinued 的 `flutter_markdown`），
   渲染层自绘 Widget；`--dart-define=DSH_BASE_URL=…` 注入 base URL。
6. 进度以版本里程碑与 [docs/spec.md](spec.md) 为事实来源；阶段推进门禁见 CI 与
   验证门禁。

## 被放弃的约束及理由

原章程"100% Kotlin + Compose、无 RN/Flutter"的三条立规理由，在 Flutter 方案下
分别由对应机制满足：

| 原理由 | Flutter 方案下的满足方式 |
|---|---|
| 布局所有权归属客户端代码 | Widget 组合，布局全部在 `flutter/app`，服务端数据不驱动布局 |
| 无桥接层（平台通道） | 纯 Dart 栈，UI↔domain↔adapter 无任何 platform channel；仅 `--dart-define` 配置注入 |
| 测试可移植性 | `flutter_test`/`test` 对应 JVM suite；fake-host 用 `shelf` 复刻；81 测试作平价清单 |

## 后果

- 正面：一套代码多平台；domain/adapter 的纯 Dart 化让未来的 iOS/桌面/Web 壳
  成为纯工程问题（iOS 侧 loopback 需 `iproxy 3080 3080`，见分析 R4）。
- 负面：4–6 周量级的重写投入；双栈并存期（Phase 1–5）legacy 只修 P0；
  `flutter_markdown` 生态风险由自研直译承担。
- 不变项：dsh 后端与 `reference/` submodule 完全不动；wire 协议词汇仍被
  `harness_adapter` 唯一隔离；UI 只见中立 domain 模型。
