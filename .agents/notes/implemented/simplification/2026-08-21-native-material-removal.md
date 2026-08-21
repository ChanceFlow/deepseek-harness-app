# Agent Note: 去除 deepsuite 视觉仿冒,回归原生 Material 3

Status: implemented

## Problem

Flutter 客户端在 deepsuite 视觉对齐阶段(plan-deepsuite.md)把 dsh web
前端的 `design-platform.css` 设计令牌整体移植进客户端:`deepsuite_tokens.dart`
(736 行生成色板 + `DeepSuiteStatic/Light/Dark` 静态类)、
`DeepSuiteColors` ThemeExtension(40+ 语义颜色)、`gen_deepsuite_tokens.py`
生成器与 `dsh-design-tokens` 技能。产物是 20+ 个 UI 文件里约 400 处
`ds.*` 颜色引用、自绘 DeepSeek 鱼形 logo(由 SVG path 数据 + CustomPainter
手绘)和大量 deepsuite 语义色(warn 琥珀系、bubble、tip、sidebar fills)。

用户实测反馈:这套仿冒设计语言在 Android 上不"原生",观感与系统应用
脱节,希望全面去除,改用原生控件与图标,达到原生丝滑效果与布局,且
不阻碍既有功能。

## Decision

客户端主题全面回归原生 Material 3:

- `theme.dart` 改为 `ColorScheme.fromSeed(seedColor: Colors.blue)` 生成
  标准 M3 主题(light/dark),删除 `DeepSuiteColors` 扩展、`deepsuite_tokens.dart`
  与 `deepsuite_extension.dart`;不再有任何 dsh-web 设计令牌。
- 全部 400 处 `ds.*` 引用迁移到原生 `ColorScheme` 角色
  (labelTertiary→onSurfaceVariant、bgLayer→surfaceContainer*、
  divider/border→outlineVariant、accent→primary、bubble→primaryContainer、
  warn→error 系、menu→surfaceContainer 等);动效 `kDsDuration` 改为
  M3 标准时长;等宽字体用平台 `monospace`;浮层阴影用 M3 elevation 常量
  `kM3ShadowElevation1/3`。
- 生成器 `gen_deepsuite_tokens.py`、`dsh-design-tokens` 技能、`verify_all.py`
  的 `design-token-drift` 门禁一并移除;AGENTS.md 的 "design tokens are
  generated" 规则替换为 "Native Material 3, no ported web tokens"。
- 品牌 DeepSeek 鱼形 logo 保留:`FishLogo` 仍以 SVG path 数据 + CustomPainter
  渲染(用户明确"品牌 SVG 还是留着"),仅随主题色号取色,不属于仿冒层。

## Alternatives considered

- **Keep DeepSuiteColors as a transition shim.** The UI files would stay
  untouched and only the extension's value sources change; rejected because
  the user asked for a comprehensive removal and a shim is still an imitation
  layer that contradicts the goal.
- **Replace the brand fish with a Material icon.** The user initially picked
  "Material icon replacement" but then explicitly said to keep the brand SVG,
  so the original logo stays.
- **Keep the generator script for later reuse.** Dropping runtime references
  while retaining the script and drift gate would leave dead code and gate
  overhead, against the comprehensive-removal goal.

## Consequences

- UI 全部走标准 M3 颜色角色,主题由种子色统一派生,明暗主题自动适配;
  组件(按钮/菜单/列表/气泡)视觉与 Android 系统应用一致。
- 视觉上不再复刻 dsh web 的深色扁平淡化风格,而是原生 Material 表面层级。
- 删除 ~1200 行生成令牌/扩展代码与一个生成脚本/技能;`verify_all` 少一个
  docs 门禁。
- 品牌标识(鱼 logo、BrandWordmark)与全部功能、布局、交互保持不变;
  chat/settings/workspace/subagents 各屏测试随颜色角色更新。
