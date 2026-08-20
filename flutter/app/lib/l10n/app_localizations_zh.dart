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
  String goalStatusLine(
    Object max,
    Object phase,
    Object revision,
    Object started,
  ) {
    return '$phase · 版本 $revision · 轮数 $started/$max';
  }

  @override
  String contextUsedPercent(Object percent) {
    return '已用上下文 $percent%';
  }

  @override
  String get systemPromptLabel => '系统提示词';

  @override
  String get toolsLabel => '工具';

  @override
  String get conversationLabel => '会话';

  @override
  String contextTokens(Object used, Object window) {
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
  String modelCurrent(Object name) {
    return '$name（当前）';
  }

  @override
  String get reasoningEffortLabel => '思考强度';

  @override
  String get todosLabel => '待办';

  @override
  String todoCountDone(Object count) {
    return '已完成 $count';
  }

  @override
  String todoCountActive(Object count) {
    return '进行中 $count';
  }

  @override
  String todoCountPending(Object count) {
    return '待处理 $count';
  }

  @override
  String get backgroundJobsTitle => '后台任务';

  @override
  String jobCountRunning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个后台任务运行中',
      one: '1 个后台任务运行中',
    );
    return '$_temp0';
  }

  @override
  String jobCount(num count) {
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
  String jobDurationHoursMinutes(Object hours, Object minutes) {
    return '$hours小时$minutes分';
  }

  @override
  String jobDurationMinutesSeconds(Object minutes, Object seconds) {
    return '$minutes分$seconds秒';
  }

  @override
  String jobDurationSeconds(Object seconds) {
    return '$seconds秒';
  }

  @override
  String get copyTooltip => '复制';

  @override
  String get copiedTooltip => '已复制';

  @override
  String get waitingForApproval => '等待审批';

  @override
  String approveToolFallback(Object tool) {
    return '批准工具：$tool';
  }

  @override
  String toolRequestsPrivileged(Object tool) {
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
  String accessModeTooltip(Object label) {
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
  String toolTodoPlanCompleted(Object done, Object total) {
    return '已完成 $done/$total';
  }

  @override
  String statsTurnsSteps(Object steps, Object turns) {
    return '$turns 轮 · $steps 步';
  }

  @override
  String statsLlmDuration(Object duration) {
    return 'LLM $duration';
  }

  @override
  String statsToolDuration(Object duration) {
    return '工具调用 $duration';
  }

  @override
  String statsTtftAvg(Object duration) {
    return 'TTFT 均值 $duration';
  }

  @override
  String statsTokensPerSecond(Object rate) {
    return '$rate tok/s';
  }

  @override
  String statsCacheHit(Object percent) {
    return '缓存命中 $percent%';
  }

  @override
  String statsInputTokens(Object tokens) {
    return '输入 $tokens tok';
  }

  @override
  String statsOutputTokens(Object tokens) {
    return '输出 $tokens tok';
  }

  @override
  String credentialStateUnavailable(Object error) {
    return '凭据状态不可用：$error';
  }

  @override
  String storeCredentialTitle(Object ref) {
    return '存储 $ref';
  }

  @override
  String namespaceMetaApplies(Object name) {
    return '应用：$name';
  }

  @override
  String namespaceMetaRevision(Object revision) {
    return '修订号：$revision';
  }

  @override
  String credentialMetaSource(Object source) {
    return '来源：$source';
  }

  @override
  String casRevisionLine(Object revision) {
    return 'CAS 修订号 $revision；主机依据 schema 校验';
  }

  @override
  String newSessionInWorkspace(Object title) {
    return '在 $title 中新建会话';
  }

  @override
  String workspaceActionsFor(Object title) {
    return '$title 的工作区操作';
  }

  @override
  String workspaceNameExists(Object name) {
    return '名为 \"$name\" 的工作区已存在。';
  }

  @override
  String deleteWorkspaceConfirm(Object name) {
    return '删除工作区 \"$name\"？其会话保留；连接器将被移除。';
  }

  @override
  String newFolderIn(Object parent) {
    return '在 \"$parent\" 中新建文件夹';
  }

  @override
  String secretsSetCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已设置 $count 个密钥',
      one: '已设置 1 个密钥',
    );
    return '$_temp0';
  }

  @override
  String workspaceSessionCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个会话',
      one: '1 个会话',
    );
    return '$_temp0';
  }

  @override
  String get settingsNavBackends => '后端';

  @override
  String get settingsNavGeneral => '常规';

  @override
  String get settingsNavModels => '模型';

  @override
  String get settingsNavPlugins => '插件';

  @override
  String get settingsNavAgentPresets => '智能体预设';

  @override
  String get settingsNavCredentials => '凭据';

  @override
  String get settingsLoopbackHint =>
      'settings/credentials 仅在宿主机回环可用；请通过 adb reverse 连接';

  @override
  String get backendsIntro => '本设备保持连接的主机端点——每个已配置后端保持在线，活动后端驱动对话与这些主机设置页面。';

  @override
  String get addBackend => '添加后端';

  @override
  String get editBackend => '编辑后端';

  @override
  String get removeActiveBackendFirst => '请先切换离开活动后端再删除。';

  @override
  String get cannotRemoveLastBackend => '无法删除最后一个后端。';

  @override
  String get backendStatusActive => '活动';

  @override
  String get backendStatusStandby => '待机';

  @override
  String get hostSettingsUnavailable => '主机设置不可用';

  @override
  String get hostSettingsUnavailableBody => '活动后端未响应。请在后端页面重新指向或切换后端。';

  @override
  String get hostWritesLabel => '主机写入';

  @override
  String get hostWritesDescription => '主机是否接受设置与凭据写入。';

  @override
  String get writableValue => '可写';

  @override
  String get readOnlyValue => '只读';

  @override
  String get settingsDocumentLabel => '设置文档';

  @override
  String get settingsDocumentDescription => '各命名空间是否由用户设置文档支撑。';

  @override
  String get presentValue => '存在';

  @override
  String get noneValue => '无';

  @override
  String get generalIntro => '新会话默认项与主机设置平面。';

  @override
  String get busyPreferenceLabel => '繁忙时的行为';

  @override
  String get busyPreferenceDescription => '仅在智能体运行期间生效。';

  @override
  String get busyBehaviorQueue => '排队';

  @override
  String get busyBehaviorSteer => '转向';

  @override
  String get agentPresetPreferenceLabel => '智能体预设';

  @override
  String get agentPresetPreferenceDescription =>
      '适用于从现在起启动的会话。运行中的会话保持其启动时的预设。';

  @override
  String get agentPresetsIntro => '预设是一个会话的智能体运行的插件组合——其工具、提示词与能力。';

  @override
  String get presetGroupBuiltIn => '内置';

  @override
  String get presetGroupCustom => '自定义';

  @override
  String get presetsFooter => '预设由宿主机编写：请在桌面端设置中复制、编辑与删除。';

  @override
  String get noDescription => '无描述。';

  @override
  String get presetBrokenBadge => '加载失败';

  @override
  String get presetInUseBadge => '使用中';

  @override
  String get pluginsIntro => '配置并检查此部署中安装的插件。';

  @override
  String get noPluginSettings => '此部署未暴露任何插件设置。';

  @override
  String get modelsIntro => '输入 API 密钥以使用下列提供方的模型。';

  @override
  String get settingsReadOnlyNotice => '此部署中的设置文档为只读。';

  @override
  String get modelsFooter => '自定义提供方由宿主机管理：此客户端仅覆盖 DeepSeek API 密钥。';

  @override
  String get apiKeyConfigured => 'API 密钥已配置';

  @override
  String get apiKeyMissing => 'API 密钥缺失';

  @override
  String get credentialsIntro => '由主机命名空间引用的密钥引用。';

  @override
  String get noCredentialsReferenced => '未引用任何凭据。';

  @override
  String get patchKey => '补丁键';

  @override
  String get replaceSection => '替换区块';

  @override
  String get topLevelKey => '顶层键';

  @override
  String get wholeUserLayerJson => '完整用户层 JSON 对象';

  @override
  String get jsonValue => 'JSON 值';

  @override
  String get jsonKeyValueExampleHint => '{ \"key\": value }';

  @override
  String get jsonValueExampleHint => 'true / 42 / \"text\" / {…}';

  @override
  String get discard => '放弃';

  @override
  String get stateConfigured => '已配置';

  @override
  String get stateNotSet => '未设置';

  @override
  String get credentialReadOnlyHint => '此连接为只读；无法在此客户端更改已存储的值。';

  @override
  String get unset => '清除';

  @override
  String get secretValueLabel => '密钥值';

  @override
  String get secretValueHint => '密钥值';

  @override
  String get secretValueHintLine => '存储在宿主机上；值永远不会随响应返回。';

  @override
  String get backendLabel => '标签';

  @override
  String get backendLabelHint => '笔记本电脑主机、构建机…';

  @override
  String get backendBaseUrlLabel => '基础 URL';

  @override
  String get backendBaseUrlHint => 'http://10.0.2.2:3080';

  @override
  String get baseUrlDerivationHint => 'RPC 与事件路径由此基础 URL 派生。';

  @override
  String get baseUrlValidHint => '带主机的 http 或 https，例如 http://10.0.2.2:3080';

  @override
  String get remove => '移除';

  @override
  String get add => '添加';

  @override
  String get userLayerLabel => '用户层';

  @override
  String get credentialMetaConfigured => '已配置';

  @override
  String get credentialMetaNotConfigured => '未配置';

  @override
  String get credentialMetaWritable => '可写';

  @override
  String get credentialMetaReadOnly => '只读';

  @override
  String get workspacesNavTitle => '工作区';

  @override
  String get searchWorkspacesHint => '搜索工作区…';

  @override
  String get noMatchingWorkspaces => '无匹配结果';

  @override
  String get noWorkspacesYet => '暂无工作区';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get deleteWorkspace => '删除工作区';

  @override
  String get renameWorkspace => '重命名工作区';

  @override
  String get renameWorkspaceTitle => '重命名工作区';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get untitledFolderHint => '未命名文件夹';

  @override
  String get homeCrumb => '首页';

  @override
  String get selectWorkspaceDirectoryTitle => '选择工作区目录';

  @override
  String get editPathTooltip => '编辑路径';

  @override
  String get unableToLoadDirectory => '无法加载目录';

  @override
  String get noFolders => '无文件夹';

  @override
  String get tooManyFoldersHint => '文件夹过多，仅显示开头部分。';

  @override
  String get showHiddenFiles => '显示隐藏文件';

  @override
  String get pathLabel => '路径';
}
