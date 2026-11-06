# deepseek-harness-app

[English](README.md) | 简体中文

[![CI](https://img.shields.io/github/actions/workflow/status/ChanceFlow/deepseek-harness-app/ci.yaml?label=CI&logo=github)](https://github.com/ChanceFlow/deepseek-harness-app/actions/workflows/ci.yaml)
[![Release](https://img.shields.io/github/v/release/ChanceFlow/deepseek-harness-app?include_prereleases&label=release)](https://github.com/ChanceFlow/deepseek-harness-app/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#deepseek-harness-app)
[![License: MIT](https://img.shields.io/github/license/ChanceFlow/deepseek-harness-app)](LICENSE)

基于 Flutter 开发的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
（`dsh`）Android 外壳。它连接运行在你电脑上的**未经修改的 `dsh web` 主机**，
并用 WebView 渲染主机自己的 Web 客户端——每个已配置主机一个页面——因此完整的
agent 界面原样随行：对话记录、审批与提问、工作区、模型、目标、子代理、插件、
定时任务、终端与文件预览，语言也由主机页面自行决定。

外壳自己新增的部分只有三样：回合结束或等待你处理时弹出的 Android 通知、
设备本地的主机注册表，以及在有任务进行时保持事件 socket 存活的前台保活服务。
页面里不注入任何东西，也没有 JavaScript 桥。

## 快速开始

### 1. 安装 APK

从 [发布页](../../releases) 获取最新 APK：

- **`v<semver>`** — 稳定版。
- **`dev`** — 滚动预发布版，每次合入 `master` 都会刷新，是尝鲜最新功能最快的途径。

```sh
adb install dsh-android-<version>-arm64-v8a.apk
```

每个发布按 ABI 各出一个包——native 库就是全部体积，而一台手机只会用其中一个：

| APK | 装在哪 |
|---|---|
| `-arm64-v8a` | 2017 年之后的所有手机（拿这个） |
| `-armeabi-v7a` | 更早的 32 位手机 |
| `-x86_64` | 模拟器与 Chromebook |

每个 APK 都有自己的 `.sha256` 校验文件。WebView 引擎随平台提供，因此一个 APK
就是 Flutter 外壳本身，没有额外需要下载安装的运行时。

### 2. 在电脑上启动主机

应用连接的是原生 `dsh web` 服务——无需插件、无需补丁：

```sh
npx @deepseek-ai/dsh web --port 3080
```

### 3. 连接主机

`dsh web` 只监听 loopback——这是上游出于安全的刻意决定，因为 agent 可以执行代码：
`dsh web` 会直接拒绝 `--host 0.0.0.0`（"会把远程代码执行暴露到网络上"）。dsh 没有
面向局域网的模式，所以发布 APK 内置 `http://127.0.0.1:3080`，你需要把这条 loopback
端口转发到运行 dsh 的电脑上：

| 场景 | 做法 |
|---|---|
| **USB 连接手机或模拟器** | `adb reverse tcp:3080 tcp:3080` —— 一条命令，应用即可连接。 |
| **不用 adb 的模拟器** | 用 `--dart-define=DSH_BASE_URL=http://10.0.2.2:3080` 自建 APK，这是模拟器访问宿主机 loopback 的专用路由。 |
| **其他任何可达端点** —— 隧道、第二台机器 | 直接在应用里把它加为另一台主机——见 [多主机](#多主机)。 |

> 主机只对 loopback 连接开放设置面，因此外壳里渲染的主机设置页也需要同样的端口转发。

## 多主机

一个应用，多个 dsh 主机：外壳的主机抽屉维护一份设备本地注册表——随时添加、
切换。每个已配置主机各占一个 WebView；最多三个页面保持温热（当前主机加
两个相邻主机），超出预算的页面在你下次选中时从自己的 URL 重新加载。全新安装时
注册表以构建期 URL 为种子，所以在你添加第二台主机（笔记本、构建机、隧道连接的
远程 dsh）之前，一切如常。

## 功能一览

- **主机自己的完整 Web 客户端，原样呈现** — 页面由 `dsh` 提供并随其版本演进：
  对话与实时运行、审批与提问、计划审阅、工作区、模型与提供商、目标、子代理与团队、
  插件、定时任务、终端、文件预览，以及主机自己的设置。升级 `dsh` 即更新界面，无需
  更新应用；不注入、不改样式。
- **每个主机一个 WebView** — 每个启用主机都是一层堆叠页面，切换只是显示切换而
  不是重新加载；页面池最多保留三个存活页面以约束内存，被释放的主机在选中时重载。
- **通知** — 应用在后台时，回合结束会发出 Android 通知；在前台时则弹出可点击的
  toast。会话开始等待审批或计划审阅时也会通知，进行中的任务通知跟随同一份会话名册
  折叠。外壳无法得知页面正在显示哪个会话，因此没有“正在看”的会话，每个完成的
  回合都会提示。点击会带着当前主机打开应用。
- **有任务在飞时保活** — 存在 running 或等待用户的根会话时，前台服务持有一把
  局部唤醒锁，让 Android 在锁屏后冻结缓存进程也杀不掉事件 socket；最后一个会话
  落定 30 秒后停止。
- **多主机注册表** — 添加并选择主机，健康状态只占标题栏上的一个圆点。重命名、
  URL 编辑、删除与按主机信任自签名/内网 CA 证书目前只是注册表动作，外壳还没有
  编辑入口。
- **本地化的外壳文案** — 主机页面用自己的语言；标题栏、抽屉、主机编辑器、
  权限询问与通知文案支持英文和简体中文。
- **失败面** — 标题栏圆点指明不可达主机，页面自行绘制它的加载错误，空注册表
  给出添加动作而不是白屏。

## 协议兼容性

上游 dsh 仓库以 git submodule 形式钉在 [`reference/deepseek-harness`](reference/)
下的一个官方提交——当前是 **`dsh-v0.2.2-rc.1`**
（[钉版本与契约文件映射](reference/README.md)）。dsh 正在快速迭代且有破坏性变更：
本客户端只追踪这一个钉死的契约，请勿假设与其他 dsh 版本协议兼容。目前覆盖钉死源码树
注册的 184 个 Remote 方法中的 103 个——精确计数、未接线余量与经复核的
「仅声明」/「有意不接线」名称见 [docs/spec.md §4.6](docs/spec.md#46-wire-coverage)，两者的一致性由
`verify_wire_pin` 门禁守护；该门禁还会让一个「仅声明」却被线上层实际调用的名称失败。

## 模块边界

pub 工作区位于 `flutter/` 下：

```text
flutter/app                        WebView 外壳：主机页面与标题栏、通知、主机注册表、主题。
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

构建期默认主机是 `http://127.0.0.1:3080`；可用 `--dart-define=DSH_BASE_URL=...`
覆盖（仅模拟器可用的 `10.0.2.2` 路由见 [§连接主机](#3-连接主机)）。

外壳就是应用的主界面：`main.dart` 把 `ShellRoot` 挂在 `ShellLifecycle` 里，
`AppNotificationCenter` 直接跑在 adapter 的 socket 上，不依赖任何页面被挂载。
主机页面就是 UI，因此本仓库不再提供屏幕渲染器或设计截图；标题栏与通知面由
widget 测试证明（[docs/testing.md](docs/testing.md)）。

完整命令清单与聚合验证门禁见 [AGENTS.md §Commands](AGENTS.md#commands)；
PATH 上需要 Flutter 3.47.1 stable。真实主机端到端测试是可选开启的——见下方
[§可选真实主机端到端](#可选真实主机端到端)。

### 可选真实主机端到端

```sh
cd flutter
DSH_E2E_URL=http://127.0.0.1:3080 flutter test packages/harness_adapter/test/local_dsh_e2e_test.dart
```

0.2.0 主机的 `/api` 只对持有它签发的、绑定访问 authority 的浏览器 cookie 的
调用方应答；该 cookie 由 `dsh web` 打印的 URL token 换取，目标主机属于这一类
时用 `DSH_E2E_COOKIE` 传入：

```sh
curl -s -c jar "http://127.0.0.1:3080/?token=<dsh web 打印的 token>"
cd flutter
DSH_E2E_URL=http://127.0.0.1:3080 \
  DSH_E2E_COOKIE="$(awk 'NF>=7 && $6 ~ /^dsh/ {print $6"="$7}' jar)" \
  flutter test packages/harness_adapter/test/local_dsh_e2e_test.dart
```

该冒烟覆盖预览所依赖的整条线面——目录列举、`stat`、分页文本 `read`——因此
workspace 文件作用域参数被改名时会在端到端处失败，而不是只在 UI 里显形。

## APK 发布

发布 APK 由内部 forge 流水线
（[`.gitea/workflows/release-apk.yaml`](.gitea/workflows/release-apk.yaml)）构建，
并镜像到 [发布页](../../releases)：每次 `master` 推送都会刷新滚动 `dev`
预发布版，`v<semver>` 标签切出稳定版，两者都附带按 ABI 拆分的签名 APK
（发布密钥库，非调试密钥），每个 APK 各有自己的 `.sha256` 校验文件。命名
遵循 SemVer 2.0；内部发布正文带自动生成的 `## What's Changed` 变更日志，
镜像到 GitHub 的发布则携带产物与版本元数据。GitHub 侧的同名工作流
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
