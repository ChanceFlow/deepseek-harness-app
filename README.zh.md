# deepseek-harness-app

[English](README.md) | 简体中文

[![CI](https://img.shields.io/github/actions/workflow/status/ChanceFlow/deepseek-harness-app/ci.yaml?label=CI&logo=github)](https://github.com/ChanceFlow/deepseek-harness-app/actions/workflows/ci.yaml)
[![Release](https://img.shields.io/github/v/release/ChanceFlow/deepseek-harness-app?include_prereleases&label=release)](https://github.com/ChanceFlow/deepseek-harness-app/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#deepseek-harness-app)
[![License: MIT](https://img.shields.io/github/license/ChanceFlow/deepseek-harness-app)](LICENSE)

基于 Flutter 开发的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
（`dsh`）原生 Android 客户端。它连接运行在你电脑上的**未经修改的 `dsh web`
后端**，让你把 agent 会话装进口袋：实时观看任务运行、审批工具调用、回答问题、
管理工作区、模型、目标和子代理——支持英文和简体中文。

<p align="center">
  <img src="docs/screenshots/chat.png" width="250" alt="聊天时间线">
  <img src="docs/screenshots/sessions.png" width="250" alt="会话抽屉">
  <img src="docs/screenshots/markdown.png" width="250" alt="Markdown 渲染">
</p>

## 快速开始

### 1. 安装 APK

从 [发布页](../../releases) 获取最新 APK：

- **`v<semver>`** — 稳定版。
- **`dev`** — 滚动预发布版，每次合入 `master` 都会刷新，是尝鲜最新功能最快的途径。

```sh
adb install dsh-android-<version>.apk
```

每个发布都附带一个 `.sha256` 校验文件。

### 2. 在电脑上启动后端

应用连接的是原生 `dsh web` 服务——无需插件、无需补丁：

```sh
npx @deepseek-ai/dsh web --port 3080
```

### 3. 连接后端

`dsh web` 只监听 loopback——这是上游出于安全的刻意决定，因为 agent 可以执行代码：
`dsh web` 会直接拒绝 `--host 0.0.0.0`（"会把远程代码执行暴露到网络上"）。dsh 没有
面向局域网的模式，所以发布 APK 内置 `http://127.0.0.1:3080`，你需要把这条 loopback
端口转发到运行 dsh 的电脑上：

| 场景 | 做法 |
|---|---|
| **USB 连接手机或模拟器** | `adb reverse tcp:3080 tcp:3080` —— 一条命令，应用即可连接。 |
| **不用 adb 的模拟器** | 用 `--dart-define=DSH_BASE_URL=http://10.0.2.2:3080` 自建 APK，这是模拟器访问宿主机 loopback 的专用路由。 |
| **其他任何可达端点** —— 隧道、第二台机器 | 直接在应用里把它加为另一个后端——见 [多后端](#多后端)。 |

> 后端只对 loopback 连接开放设置面，因此应用内的主机设置页也需要同样的端口转发。

## 多后端

一个应用，多个 dsh 主机：设置页维护一份设备本地的后端注册表——随时添加、重命名、
切换。每个已配置的后端都保持在线，激活的那个驱动聊天。全新安装时注册表以构建期
URL 为种子，所以在你添加第二台主机（笔记本、构建机、隧道连接的远程 dsh）之前，
一切如常。

## 功能一览

- **聊天** — 会话列表（搜索、在工作区内创建、重命名、归档、分叉、运行中指示）、
  扁平时间线与账本式大纲（可折叠回合分组、压缩标记）、Markdown 渲染（围栏代码、
  标题、列表、表格、可点击链接）、队列行、审批、提问、计划审阅卡片、后台任务、
  图片附件、技能候选。
- **多后端** — 在本机配置多个 dsh 主机，随时切换由哪个驱动聊天。
- **工作区** — 从路径或应用内主机目录浏览器创建、重命名、删除、手动排序。
- **模型** — 提供商分组、当前选择、推理档位、提供商故障。
- **子代理** — 父级选择器、子级条目、打开子级时间线、发送提示、中断。
- **目标** — 按阶段创建/暂停/恢复/完成，带 CAS 修订的目标编辑。
- **设置** — 按命名空间编辑并带修订 CAS，凭据的 describe/set/unset。

## 协议兼容性

上游 dsh 仓库以 git submodule 形式钉在 [`reference/deepseek-harness`](reference/)
下的一个官方提交——当前是 **`dsh-v0.1.1-rc.2`**
（[钉版本与契约文件映射](reference/README.md)）。dsh 正在快速迭代且有破坏性变更：
本客户端只追踪这一个钉死的契约，请勿假设与其他 dsh 版本协议兼容。目前覆盖 48 个
主机 RPC 方法中的 40 个——完整清单见 [docs/spec.md](docs/spec.md)。

## 模块边界

pub 工作区位于 `flutter/` 下：

```text
flutter/app                        Flutter UI（界面、Markdown 渲染器）。
flutter/packages/domain            面向 UI 的中性模型：ChatMessage、Session、TimelineItem。
flutter/packages/harness_adapter   唯一理解 dsh 线上协议的包。
flutter/packages/network           传输原语：RPC 信封、HTTP/WebSocket 接缝。
flutter/packages/dev               调试构建工具：遥测、帧跟踪、崩溃采集。
```

`app` 和 `domain` 永不导入 dsh 类型；所有线上协议知识都隔离在 `harness_adapter`
边界之后，由 `scripts/check_dart_imports.py` 强制。

## 开发

```sh
git clone --recurse-submodules https://github.com/ChanceFlow/deepseek-harness-app.git
adb reverse tcp:3080 tcp:3080    # 设备 loopback 3080 -> 宿主机的 dsh
cd flutter/app
flutter run
```

构建期默认后端是 `http://127.0.0.1:3080`；可用 `--dart-define=DSH_BASE_URL=...`
覆盖（仅模拟器可用的 `10.0.2.2` 路由见 [§连接后端](#3-连接后端)）。

完整命令清单与聚合验证门禁见 [AGENTS.md §Commands](AGENTS.md#commands)；
PATH 上需要 Flutter 3.47.1 stable。真实主机端到端测试是可选开启的——见下方
[§可选真实主机端到端](#可选真实主机端到端)。

### 可选真实主机端到端

```sh
cd flutter
DSH_E2E_URL=http://127.0.0.1:3080 flutter test packages/harness_adapter/test/local_dsh_e2e_test.dart
```

## APK 发布

发布 APK 由内部 forge 流水线
（[`.gitea/workflows/release-apk.yaml`](.gitea/workflows/release-apk.yaml)）构建，
并镜像到 [发布页](../../releases)：每次 `master` 推送都会刷新滚动 `dev`
预发布版，`v<semver>` 标签切出稳定版，两者都附带签名 APK（发布密钥库，
非调试密钥）和 `.sha256` 校验文件。命名遵循 SemVer 2.0；内部发布正文带
自动生成的 `## What's Changed` 变更日志，镜像到 GitHub 的发布则携带产物
与版本元数据。GitHub 侧的同名工作流
（[`.github/workflows/release-apk.yaml`](.github/workflows/release-apk.yaml)）
在没有签名 secrets 时会跳过构建——本仓库是镜像，不是第二个构建渠道。

## 验证状态

`python3 scripts/verify_all.py` 是聚合门禁：严格 casts/inference/raw-types 下的
`flutter analyze`、完整测试套件（未设 `DSH_E2E_URL` 时真实主机端到端自动跳过）、
导入门禁、启动图标漂移门禁，以及文档门禁。CI 以两个并行任务运行它——`docs`
（仅 Python）和 `code`（Flutter）——每次推送和 PR 都会执行，两者都是合并必需。

## 历史

由最初的 Kotlin/Compose 原型用 Flutter 重写——见
[ADR-0001](docs/adr-0001-flutter-rewrite.md)。Kotlin 时代的提交保留在历史中；
当前发布的是 `flutter/` 下的 Flutter 工作区。

## 许可证

[ MIT ](LICENSE)
