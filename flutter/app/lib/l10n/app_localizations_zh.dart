// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'DeepSeek Harness';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get create => '创建';

  @override
  String get refresh => '刷新';

  @override
  String get retry => '重试';

  @override
  String get back => '返回';

  @override
  String get close => '关闭';

  @override
  String get dismiss => '忽略';

  @override
  String get delete => '删除';

  @override
  String get rename => '重命名';

  @override
  String get open => '打开';

  @override
  String get defaultBadge => '默认';

  @override
  String get destinationChat => '对话';

  @override
  String get destinationWorkspaces => '工作区';

  @override
  String get destinationSettings => '设置';

  @override
  String get goalTitle => '目标';

  @override
  String get sessionLabel => '会话';

  @override
  String get providersLabel => '提供方';

  @override
  String get noCurrentGoal => '暂无目标';

  @override
  String get goalObjectiveHint => '目标描述';

  @override
  String get maxGoalRoundsHint => '最大轮数（可选）';

  @override
  String get pause => '暂停';

  @override
  String get resume => '继续';

  @override
  String get clear => '清除';

  @override
  String get complete => '完成';

  @override
  String get edit => '编辑';

  @override
  String get goalPhaseActive => '进行中';

  @override
  String get goalPhasePaused => '已暂停';

  @override
  String get goalPhaseBlocked => '受阻';

  @override
  String get goalPhaseComplete => '已完成';

  @override
  String goalStatusLine(String phase, int revision, int started, int max) {
    return '$phase · 版本 $revision · 轮数 $started/$max';
  }

  @override
  String contextUsedPercent(int percent) {
    return '已用上下文 $percent%';
  }

  @override
  String get systemPromptLabel => '系统提示词';

  @override
  String get toolsLabel => '工具';

  @override
  String get conversationLabel => '会话';

  @override
  String contextTokens(String used, String window) {
    return '约 $used / $window';
  }

  @override
  String get heroHeadline => '探索未知';

  @override
  String get heroPreview => '预览';

  @override
  String get heroChooseWorkspace => '选择工作区';

  @override
  String get modelsTitle => '模型';

  @override
  String modelCurrent(String name) {
    return '$name（当前）';
  }

  @override
  String get reasoningEffortLabel => '思考强度';

  @override
  String get todosLabel => '待办';

  @override
  String todoCountDone(int count) {
    return '已完成 $count';
  }

  @override
  String todoCountActive(int count) {
    return '进行中 $count';
  }

  @override
  String todoCountPending(int count) {
    return '待处理 $count';
  }

  @override
  String get backgroundJobsTitle => '后台任务';

  @override
  String jobCountRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个后台任务运行中',
      one: '1 个后台任务运行中',
    );
    return '$_temp0';
  }

  @override
  String jobCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个后台任务',
      one: '1 个后台任务',
    );
    return '$_temp0';
  }

  @override
  String get jobStatusRunning => '运行中';

  @override
  String get jobStatusStopping => '停止中';

  @override
  String get jobStatusCompleted => '已完成';

  @override
  String get jobStatusKilled => '已取消';

  @override
  String get jobStatusFailed => '失败';

  @override
  String jobDurationHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分';
  }

  @override
  String jobDurationMinutesSeconds(int minutes, int seconds) {
    return '$minutes分$seconds秒';
  }

  @override
  String jobDurationSeconds(int seconds) {
    return '$seconds秒';
  }

  @override
  String get copyTooltip => '复制';

  @override
  String get copiedTooltip => '已复制';

  @override
  String get waitingForApproval => '等待审批';

  @override
  String approveToolFallback(String tool) {
    return '批准工具：$tool';
  }

  @override
  String toolRequestsPrivileged(String tool) {
    return '工具 $tool 请求特权执行';
  }

  @override
  String get reject => '拒绝';

  @override
  String get allowOnce => '允许一次';

  @override
  String get agentPresetLabel => '智能体预设';

  @override
  String get agentPresetTooltip => '为即将开始的会话选择智能体预设';

  @override
  String get accessModeLabel => '访问模式';

  @override
  String accessModeTooltip(String label) {
    return '访问模式：$label';
  }

  @override
  String get fullAccessOption => '完全访问';

  @override
  String get enableFullAccessTitle => '启用完全访问？';

  @override
  String get fullAccessRisks =>
      '完全访问会减少确认步骤，让智能体直接执行更多操作，包括敏感操作、文件修改或外部命令。请仅在信任当前任务时使用。';

  @override
  String get acknowledgeRisks => '我了解风险，希望继续';

  @override
  String get enableFullAccess => '启用完全访问';

  @override
  String get modelLabel => '模型';

  @override
  String get effortLabel => '强度';

  @override
  String get providerDefault => '提供方默认';

  @override
  String get presetStandardName => '标准模式';

  @override
  String get presetStandardDescription =>
      '具备文件编辑、shell、文件与网络搜索、技能、规划、目标、子代理与工作流的完整编码智能体。';

  @override
  String get presetCodeName => '代码模式';

  @override
  String get presetCodeDescription =>
      '拥有标准模式的全部能力，并通过代码模式 SDK 暴露工具，让模型可在单个 TypeScript 程序中组合多步操作。';

  @override
  String get presetMinimalName => '极简模式';

  @override
  String get presetMinimalDescription =>
      '仅含持久 bash 与 str_replace_editor 两种工具的编码智能体。';

  @override
  String get presetCordisName => '创作模式';

  @override
  String get presetCordisDescription =>
      '专为创建自定义智能体预设而设计，具备标准模式全部能力，另加运行时检查、插件实验与预设编写指引。';

  @override
  String get toolSearchTitle => '搜索';

  @override
  String get toolReadTitle => '读取';

  @override
  String get toolBashTitle => 'Bash';

  @override
  String get toolWriteTitle => '写入';

  @override
  String get toolEditTitle => '编辑';

  @override
  String get toolCodeTitle => '代码';

  @override
  String get toolCallTitle => '工具调用';

  @override
  String get toolInspectTitle => '检查';

  @override
  String get toolRunCordisPlugin => '运行 Cordis 插件';

  @override
  String get toolStopCordisPlugin => '停止 Cordis 插件';

  @override
  String get toolRemoveCordisPlugin => '移除 Cordis 插件';

  @override
  String get toolPwshTitle => 'Pwsh';

  @override
  String get toolUpdateTodoTitle => '更新待办列表';

  @override
  String toolTodoPlanCompleted(int done, int total) {
    return '已完成 $done/$total';
  }

  @override
  String statsTurnsSteps(int turns, int steps) {
    return '$turns 轮 · $steps 步';
  }

  @override
  String statsLlmDuration(String duration) {
    return 'LLM $duration';
  }

  @override
  String statsToolDuration(String duration) {
    return '工具调用 $duration';
  }

  @override
  String statsTtftAvg(String duration) {
    return 'TTFT 均值 $duration';
  }

  @override
  String statsTokensPerSecond(String rate) {
    return '$rate tok/s';
  }

  @override
  String statsCacheHit(int percent) {
    return '缓存命中 $percent%';
  }

  @override
  String statsInputTokens(String tokens) {
    return '输入 $tokens tok';
  }

  @override
  String statsOutputTokens(String tokens) {
    return '输出 $tokens tok';
  }
}
