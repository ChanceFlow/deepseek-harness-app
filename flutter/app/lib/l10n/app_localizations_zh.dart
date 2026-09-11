// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'DSH Mobile';

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
  String get reconnect => '重新连接';

  @override
  String connectionHostUnreachable(String host) {
    return '无法连接到 $host';
  }

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
  String get noCurrentGoal => '暂无进行中的目标';

  @override
  String get goalObjectiveHint => '目标描述';

  @override
  String get maxGoalRoundsHint => '最大轮数（可选）';

  @override
  String get pause => '暂停目标';

  @override
  String get resume => '恢复目标';

  @override
  String get clear => '清除目标';

  @override
  String get complete => '完成目标';

  @override
  String get edit => '编辑目标';

  @override
  String get goalPhaseActive => '进行中的目标';

  @override
  String get goalPhasePaused => '已暂停的目标';

  @override
  String get goalPhaseBlocked => '受阻的目标';

  @override
  String get goalPhaseComplete => '已完成的目标';

  @override
  String goalStatusLine(int max, String phase, int revision, int started) {
    return '$phase · 版本 $revision · 轮数 $started/$max';
  }

  @override
  String contextUsedPercent(int percent) {
    return '上下文已用 $percent%';
  }

  @override
  String get contextLabel => '上下文';

  @override
  String get systemPromptLabel => '系统提示词';

  @override
  String get toolsLabel => '工具';

  @override
  String get conversationLabel => '对话消息';

  @override
  String contextTokens(String used, String window) {
    return '约 $used / $window';
  }

  @override
  String get heroHeadline => '探索未至之境';

  @override
  String get heroPreview => '预览版';

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
    return '$count 进行中';
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
  String get jobStatusStopping => '正在停止';

  @override
  String get jobStatusCompleted => '已完成';

  @override
  String get jobStatusKilled => '已取消';

  @override
  String get jobStatusFailed => '已失败';

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
  String get codeStreamingLabel => '接收中';

  @override
  String get forkFromHere => '从这里分叉';

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
    return '工具 $tool 请求越权执行';
  }

  @override
  String get reject => '拒绝';

  @override
  String get allowOnce => '允许一次';

  @override
  String get agentPresetLabel => 'Agent 预设';

  @override
  String get agentPresetTooltip => '即将开始的这个会话所用的 Agent 预设';

  @override
  String get accessModeLabel => '访问模式';

  @override
  String accessModeTooltip(String label) {
    return '访问模式：$label';
  }

  @override
  String get fullAccessOption => '完全访问';

  @override
  String get enableFullAccessTitle => '确认启用 Full access？';

  @override
  String get fullAccessRisks =>
      '启用 Full access 后，agent 将减少确认步骤，并且可以直接执行更多操作，包括敏感操作、文件修改或外部命令。仅建议在你信任当前任务时使用。';

  @override
  String get acknowledgeRisks => '我已了解风险，并愿意继续';

  @override
  String get enableFullAccess => '启用完全访问';

  @override
  String get modelLabel => '模型';

  @override
  String get effortLabel => '推理等级';

  @override
  String get providerDefault => 'Default';

  @override
  String get presetStandardName => '标准模式';

  @override
  String get presetStandardDescription =>
      '功能完整的编码 Agent，支持文件编辑、Shell、文件与网页检索、Skills、计划、目标、子代理和工作流。';

  @override
  String get presetCodeName => 'PTC 模式';

  @override
  String get presetCodeDescription =>
      '具备标准模式的全部能力，并通过 Code Mode SDK 呈现工具，让模型用一个 TypeScript 程序组合多步操作。';

  @override
  String get presetMinimalName => '极简模式';

  @override
  String get presetMinimalDescription =>
      '仅提供持久 bash 与 str_replace_editor 的双工具编码 Agent。';

  @override
  String get presetCordisName => '创造模式';

  @override
  String get presetCordisDescription =>
      '用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。';

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
  String get toolUpdateTodoTitle => '更新任务清单';

  @override
  String toolTodoPlanCompleted(int done, int total) {
    return '$done/$total 已完成';
  }

  @override
  String thoughtDuration(String duration) {
    return '已思考 $duration';
  }

  @override
  String thinkingDuration(String duration) {
    return '思考中 · $duration';
  }

  @override
  String exploredFilesAndSearches(int files, int searches) {
    return '浏览了 $files 个文件，$searches 次搜索';
  }

  @override
  String exploredFiles(int count) {
    return '浏览了 $count 个文件';
  }

  @override
  String exploringFiles(int count) {
    return '正在浏览 $count 个文件';
  }

  @override
  String searchedCount(int count) {
    return '$count 次搜索';
  }

  @override
  String modifiedFiles(int count) {
    return '修改了 $count 个文件';
  }

  @override
  String ranCommands(int count) {
    return '运行了 $count 条命令';
  }

  @override
  String runningCommands(int count) {
    return '正在运行 $count 条命令';
  }

  @override
  String toolGroupOperations(int count) {
    return '$count 个操作';
  }

  @override
  String toolWorkingSteps(int count) {
    return '执行中 ($count 步)';
  }

  @override
  String statsTurnsSteps(int steps, int turns) {
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

  @override
  String credentialStateUnavailable(String error) {
    return '凭据状态不可用：$error';
  }

  @override
  String storeCredentialTitle(String ref) {
    return '存储 $ref';
  }

  @override
  String namespaceMetaApplies(String name) {
    return '应用：$name';
  }

  @override
  String namespaceMetaRevision(int revision) {
    return '修订号：$revision';
  }

  @override
  String credentialMetaSource(String source) {
    return '来源：$source';
  }

  @override
  String casRevisionLine(int revision) {
    return 'CAS 修订号 $revision；主机依据 schema 校验';
  }

  @override
  String newSessionInWorkspace(String title) {
    return '在 $title 中新建会话';
  }

  @override
  String workspaceActionsFor(String title) {
    return '$title 的工作区操作';
  }

  @override
  String sessionActionsFor(String title) {
    return '$title 的会话操作';
  }

  @override
  String workspaceNameExists(String name) {
    return '已存在名为“$name”的工作区。';
  }

  @override
  String deleteWorkspaceConfirm(String name, String ungroupedLabel) {
    return '将把“$name”从工作区列表中移除。文件夹与会话记录会保留，其会话将显示在“$ungroupedLabel”下。';
  }

  @override
  String newFolderIn(String parent) {
    return '在 \"$parent\" 中新建文件夹';
  }

  @override
  String secretsSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已设置 $count 个密钥',
      one: '已设置 1 个密钥',
    );
    return '$_temp0';
  }

  @override
  String workspaceSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个会话',
      one: '1 个会话',
    );
    return '$_temp0';
  }

  @override
  String get settingsCategoryApp => '应用';

  @override
  String get settingsCategoryHost => '主机';

  @override
  String get settingsSectionHost => '主机与连接';

  @override
  String get settingsSectionApp => '应用偏好';

  @override
  String get settingsSectionChat => '会话与智能体';

  @override
  String get settingsSectionModels => '模型与凭据';

  @override
  String get settingsSectionPlugins => '插件与高级设置';

  @override
  String get manageHosts => '管理';

  @override
  String get appSettingsIntro => '存储在本设备上的偏好——无论是否连接主机，全局生效。';

  @override
  String get languageLabel => '语言';

  @override
  String get languageDescription => '应用界面语言；“跟随系统”时沿用设备语言。';

  @override
  String get languageOptionSystem => '跟随系统';

  @override
  String get languageOptionZh => '中文';

  @override
  String get languageOptionEn => 'English';

  @override
  String get settingsNavGeneral => '通用设置';

  @override
  String get settingsNavModels => '模型';

  @override
  String get settingsNavPlugins => '插件';

  @override
  String get settingsNavAgentPresets => 'Agent 预设';

  @override
  String get settingsNavCredentials => '凭据';

  @override
  String get settingsScopeTitle => '选择主机';

  @override
  String get settingsScopeHint => '这些设置页面将描述所选主机——独立于对话当前使用的主机。';

  @override
  String get settingsScopeFollowActive => '跟随当前主机';

  @override
  String get settingsLoopbackHint =>
      'settings/credentials 仅在宿主机回环可用；请通过 adb reverse 连接';

  @override
  String get setChatHost => '设为对话主机';

  @override
  String get addBackend => '添加主机';

  @override
  String get editBackend => '编辑主机';

  @override
  String get removeActiveBackendFirst => '请先切换到其他主机，再移除当前主机。';

  @override
  String get cannotRemoveLastBackend => '无法移除最后一个主机。';

  @override
  String get backendErrorInvalidJson => '主机配置文件包含无效的 JSON。';

  @override
  String get backendErrorMalformedEntry => '主机配置文件包含格式不正确的数据。';

  @override
  String backendErrorBadBaseUrl(String baseUrl) {
    return '无效的主机地址：$baseUrl';
  }

  @override
  String get backendErrorInvalidBaseUrl => '无效的主机地址。';

  @override
  String get backendErrorEmptyList => '主机配置列表为空。';

  @override
  String get backendErrorReadFailed => '读取主机配置文件失败。';

  @override
  String get backendErrorWriteFailed => '保存主机配置文件失败。';

  @override
  String get backendErrorEmptyLabel => '主机名称不能为空。';

  @override
  String backendErrorUnknownBackend(String id) {
    return '未知主机：$id';
  }

  @override
  String get backendErrorUnknown => '未知主机。';

  @override
  String get backendErrorLoadFailed => '无法加载宿主配置。';

  @override
  String get backendErrorDisabled => '请先启用该主机，然后再将其激活。';

  @override
  String backendErrorDuplicateId(String id) {
    return '已存在 ID 为“$id”的主机。';
  }

  @override
  String get backendStatusActive => '当前';

  @override
  String get backendStatusStandby => '待机';

  @override
  String get backendStatusDisabled => '已停用';

  @override
  String get backendEnableTooltip => '启用该主机';

  @override
  String get backendDisableTooltip => '停用该主机';

  @override
  String get hostSettingsUnavailable => '主机设置不可用';

  @override
  String get hostSettingsUnavailableBody => '该主机未响应。请重新指向它，或选择其他主机。';

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
  String get busyPreferenceLabel => '繁忙时 Enter 键行为';

  @override
  String get busyPreferenceDescription => '仅在智能体运行时生效；Cmd/Ctrl+Enter 使用另一行为';

  @override
  String get busyBehaviorQueue => '排队发送';

  @override
  String get busyBehaviorSteer => '插话发送';

  @override
  String get agentPresetPreferenceLabel => '智能体预设';

  @override
  String get agentPresetPreferenceDescription => '对此后新建的会话生效。运行中的会话保持它开始时的预设。';

  @override
  String get agentPresetsIntro =>
      '预设即一个会话的 Agent 所运行的插件组装 —— 它的工具、提示词与能力。复制一份既有预设改成自己的，或用「创造模式」让 Agent 帮你创建。';

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
  String get presetInUseBadge => '当前使用';

  @override
  String get pluginsIntro => '配置并检查此部署中安装的插件。';

  @override
  String get noPluginSettings => '此部署未暴露任何插件设置。';

  @override
  String get settingsSectionPluginInventory => '插件清单';

  @override
  String get pluginInventoryIntro => '此主机加载的插件，以及每个 Agent 预设组成的插件组合。';

  @override
  String get pluginInventoryReadOnlyNotice => '只读。插件的启用、停用与配置请在主机上进行。';

  @override
  String get pluginInventorySearchHint => '搜索模块名或条目 ID';

  @override
  String get pluginInventoryLoading => '正在读取插件…';

  @override
  String get pluginInventoryEmpty => '此主机未暴露任何插件。';

  @override
  String get pluginInventoryNoMatch => '没有匹配的插件。';

  @override
  String get pluginInventoryLoadFailed => '暂时无法读取插件。';

  @override
  String get pluginInventoryEnabledTag => '已启用';

  @override
  String get pluginInventoryDisabledTag => '已停用';

  @override
  String get pluginInventoryConditionalTag => '条件启用';

  @override
  String get pluginInventoryFailedTag => '启动失败';

  @override
  String get pluginInventoryPresetGroupTitle => '会话插件';

  @override
  String get pluginInventoryPresetGroupIntro => '由 Agent 预设按会话组成。';

  @override
  String get pluginInventoryGlobalGroupTitle => '全局插件';

  @override
  String get pluginInventoryGlobalGroupIntro => '系统与所有会话共用。';

  @override
  String pluginInventoryPluginCount(int count) {
    return '$count 个插件';
  }

  @override
  String pluginInventoryFailedCount(int count) {
    return '$count 个失败';
  }

  @override
  String get pluginInventoryDefaultBadge => '默认';

  @override
  String get pluginInventoryPresetBrokenLabel => '无法读取组合';

  @override
  String get pluginInventoryModuleLabel => '完整名称';

  @override
  String get pluginInventoryStatusLabel => '运行状态';

  @override
  String get pluginInventoryConditionLabel => '禁用条件';

  @override
  String get pluginInventoryPhasePending => '等待依赖';

  @override
  String get pluginInventoryPhaseLoading => '加载中';

  @override
  String get pluginInventoryPhaseActive => '运行中';

  @override
  String get pluginInventoryPhaseFailed => '启动失败';

  @override
  String get pluginInventoryPhaseUnloading => '卸载中';

  @override
  String get modelsIntro => '输入 API 密钥以使用下列提供方的模型。';

  @override
  String get settingsReadOnlyNotice => '此部署中的设置文档为只读。';

  @override
  String get modelsFooter => '提供方凭据保存在宿主机；下方的「提供方」区段可直接在本机增删与填写密钥。';

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
  String get backendBaseUrlHint => 'http://127.0.0.1:3080';

  @override
  String get baseUrlDerivationHint => 'RPC 与事件路径由此基础 URL 派生。';

  @override
  String get baseUrlValidHint => '带主机的 http 或 https，例如 http://127.0.0.1:3080';

  @override
  String get backendTrustCertificateTitle => '信任此主机的证书';

  @override
  String get backendTrustCertificateDescription =>
      '即使 Android 无法验证也接受此主机的 TLS 证书，适用于自签名或内部 CA 的网关。仅影响此主机；能拦截该连接的人可借此冒充它。除非你掌控该网关，否则请保持关闭。';

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

  @override
  String get ungroupedLabel => '未分组';

  @override
  String get openSidebar => '打开侧边栏';

  @override
  String get collapseSidebar => '收起侧边栏';

  @override
  String get newSession => '新会话';

  @override
  String get searchSessions => '搜索会话';

  @override
  String get searchSessionsHint => '搜索会话…';

  @override
  String get noSessionsYet => '暂无会话';

  @override
  String get noMatchingSessions => '无匹配会话';

  @override
  String get relativeTimeNow => '刚刚';

  @override
  String relativeTimeMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String relativeTimeHours(int hours) {
    return '$hours 小时';
  }

  @override
  String relativeTimeDays(int days) {
    return '$days 天';
  }

  @override
  String relativeTimeMonths(int months) {
    return '$months 个月';
  }

  @override
  String relativeTimeYears(int years) {
    return '$years 年';
  }

  @override
  String sessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个会话',
      one: '1 个会话',
    );
    return '$_temp0';
  }

  @override
  String get showLess => '收起';

  @override
  String showAll(int count) {
    return '显示全部 $count 个';
  }

  @override
  String get noWorkspacesRegistered => '尚未注册工作区。';

  @override
  String get noWorkspacesRegisteredBody => '请先使用工作区页签注册一个目录，或选择默认以创建未记账会话。';

  @override
  String get chooseWorkspaceOrDefault => '选择工作区或保留默认。';

  @override
  String get subagentsTitle => '子代理';

  @override
  String get selectParentSession => '选择父会话';

  @override
  String get noSubagents => '暂无子代理';

  @override
  String get loadingSubagents => '正在加载子代理…';

  @override
  String get unableToLoadSubagents => '无法加载子代理';

  @override
  String get messageSelectedSubagentHint => '给选中的子代理发消息';

  @override
  String get sending => '发送中';

  @override
  String get send => '发送';

  @override
  String get stopTooltip => '停止';

  @override
  String get modeOneShot => '一次性';

  @override
  String get modeContinuable => '可继续';

  @override
  String get activityRunning => '正在运行';

  @override
  String get activityNotRunning => '当前未运行';

  @override
  String get diagnosticCorrupt => '会话记录损坏';

  @override
  String get diagnosticUnsupported => '子代理记录版本不受支持';

  @override
  String get diagnosticUnavailable => '会话记录暂不可用';

  @override
  String get oneShotRecordTitle => '一次性子代理记录';

  @override
  String get parentUnavailableTitle => '此子代理暂时只读';

  @override
  String get oneShotRecordBody => '一次性任务不接受后续消息；请在此查看完整执行记录。';

  @override
  String get parentUnavailableBody => '父会话当前不在线，重新打开父会话后即可继续发送消息。';

  @override
  String backendVersion(String version) {
    return 'v$version';
  }

  @override
  String get outlineTooltip => '大纲';

  @override
  String get subagentsTooltip => '子代理';

  @override
  String get sessionMenuTooltip => '会话菜单';

  @override
  String get renameSession => '重命名会话';

  @override
  String get forkSession => '派生会话';

  @override
  String get archiveSession => '归档会话';

  @override
  String get archiveSessionBody => '会话日志与其工作区席位保留；此行将从所有分组界面隐藏。';

  @override
  String get archive => '归档';

  @override
  String get expandAll => '全部展开';

  @override
  String get planBadge => '方案';

  @override
  String imagePlaceholderSuffix(String name) {
    return ' · $name';
  }

  @override
  String imageLoadingPlaceholder(
    int bytes,
    int height,
    String suffix,
    int width,
  ) {
    return '图片 $width×$height（$bytes 字节）$suffix';
  }

  @override
  String get semanticsRunning => '运行中';

  @override
  String get semanticsFailed => '失败';

  @override
  String get inputLabel => '输入';

  @override
  String get diffLabel => '改动';

  @override
  String get viewDiff => '变更对比';

  @override
  String get viewFullFile => '完整文件';

  @override
  String get outputLabel => '输出';

  @override
  String get runStatusRunning => '运行中…';

  @override
  String get turnStatusWorking => '正在深入研究…';

  @override
  String get runStatusDone => '已完成';

  @override
  String get runStatusFailed => '失败';

  @override
  String get pauseGoal => '暂停目标';

  @override
  String get resumeGoal => '继续目标';

  @override
  String get clearGoal => '清除目标';

  @override
  String get openGoal => '打开目标';

  @override
  String queuedMessagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条排队消息',
      one: '1 条排队消息',
    );
    return '$_temp0';
  }

  @override
  String get editQueuedMessageHint => '编辑排队消息';

  @override
  String get saveQueuedMessage => '保存排队消息';

  @override
  String get cancelEdit => '取消编辑';

  @override
  String get steer => '插话发送';

  @override
  String get steeringPending => '插话发送';

  @override
  String get removeQueuedMessage => '删除排队消息';

  @override
  String approveTool(String tool) {
    return '批准工具：$tool';
  }

  @override
  String get allow => '允许';

  @override
  String get answer => '回答';

  @override
  String get planReview => '计划待审';

  @override
  String get skipped => '已跳过';

  @override
  String get answerInstead => '改为回答';

  @override
  String get typeYourAnswerHint => '输入你的答案';

  @override
  String get skip => '跳过本题';

  @override
  String get questionPrev => '上一题';

  @override
  String get questionNext => '下一题';

  @override
  String get questionCancel => '放弃整组问题';

  @override
  String get questionRecommended => '推荐';

  @override
  String get questionErrorIncomplete => '请先完成这道问题。';

  @override
  String get questionErrorUnanswered => '请选择一个选项或填写自定义答案。';

  @override
  String get questionSubmit => '提交';

  @override
  String get questionSubmitNext => '下一题';

  @override
  String get planApprove => '确认执行';

  @override
  String get planDecline => '拒绝';

  @override
  String get planDiscuss => '去聊天里说';

  @override
  String get planPlaceholder => '描述你的任务以生成计划';

  @override
  String get messagePlaceholder => '给智能体发消息';

  @override
  String removeImage(String name) {
    return '移除 $name';
  }

  @override
  String get delivery => '投递';

  @override
  String get commandsTooltip => '命令';

  @override
  String get attachImages => '附加图片';

  @override
  String get pickFromGallery => '从相册选择';

  @override
  String unknownImageType(String name) {
    return '不支持的图片类型：$name';
  }

  @override
  String beforeFirstTurnHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条消息',
    );
    return '首轮之前 · $_temp0';
  }

  @override
  String turnHeader(int count, int toolCount, int turn) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条消息',
    );
    String _temp1 = intl.Intl.pluralLogic(
      toolCount,
      locale: localeName,
      other: '$toolCount 个工具',
    );
    return '第 $turn 轮 · $_temp0 · $_temp1';
  }

  @override
  String turnFailedCount(int count) {
    return '$count 个失败';
  }

  @override
  String get contextCompacted => '上下文已压缩';

  @override
  String get compactionRunning => '正在压缩…';

  @override
  String compactionCompleted(int items, int tokens) {
    return '已压缩 $items 条历史记录（约 $tokens tokens）';
  }

  @override
  String get compactionViewSummary => '点击查看压缩摘要';

  @override
  String get compactionSummaryUnavailable => '压缩摘要不可用';

  @override
  String get recallLabel => '跨会话召回';

  @override
  String get contextInjectionLabel => '上下文注入';

  @override
  String get chatGoalPhaseActive => '进行中';

  @override
  String get chatGoalPhasePaused => '已暂停';

  @override
  String get chatGoalPhaseBlocked => '受阻';

  @override
  String get chatLoadOlder => '加载更早';

  @override
  String get chatLoadingOlder => '正在加载更早记录…';

  @override
  String get chatBeginningOfHistory => '已到达会话起点';

  @override
  String get chatLoadOlderRetry => '加载更早记录失败，点击重试';

  @override
  String get queue => '排队发送';

  @override
  String get thinkLabel => '思考';

  @override
  String get commandPlanDescription => '进入或退出方案模式';

  @override
  String get commandGoalDescription => '设置或查看长期任务的执行目标';

  @override
  String get commandCompactDescription => '压缩较早的会话历史';

  @override
  String get commandPermissionDescription => '切换权限预设（沙箱模式 + 审批策略）';

  @override
  String get commandFeedbackDescription => '记录关于本会话的反馈';

  @override
  String get commandExportDescription => '将会话日志下载为 ZIP 压缩包';

  @override
  String get sessionLogExportTooltip => '下载会话日志';

  @override
  String sessionLogExportSaved(String location) {
    return '会话日志已保存到 $location';
  }

  @override
  String get sessionLogExportFailed => '无法导出会话日志';

  @override
  String commandImagesUnsupported(String command) {
    return '/$command 不接受图片附件，请先移除图片';
  }

  @override
  String get parentSession => '父会话';

  @override
  String get addWorkspace => '添加工作区';

  @override
  String get searchTooltip => '搜索';

  @override
  String get namespaceReadOnlyHint => '此连接上的主机为只读；命名空间编辑不可用。';

  @override
  String turnNumberLabel(int turn) {
    return '第 $turn 轮';
  }

  @override
  String get attachmentName => '附件';

  @override
  String imageRejectionUnsupported(String name, String type) {
    return '$name：不支持的图片类型 $type';
  }

  @override
  String imageRejectionTooLarge(String name, int maxBytes) {
    return '$name：超过 $maxBytes 字节上限';
  }

  @override
  String imageRejectionNoRoom(int room) {
    return '一条消息最多还能添加 $room 张图片';
  }

  @override
  String get commandFailed => '命令失败';

  @override
  String turnFailed(String detail) {
    return '本轮运行失败：$detail';
  }

  @override
  String get unknownModelFailure => '未知模型错误';

  @override
  String get turnStopped => '回合已停止';

  @override
  String get turnInterrupted => '回合已中断';

  @override
  String get turnBlocked => '回合受阻';

  @override
  String get turnMaxTokens => '已达到输出 token 上限';

  @override
  String get turnCompleteTitle => '回合完成';

  @override
  String get turnCompletionChannel => '回合完成通知';

  @override
  String get turnCompletionChannelDescription => '在对话回合运行完成时通知。';

  @override
  String get otherTurnCompleteTitle => '其他会话有新回合';

  @override
  String get approvalRequestedTitle => '有待审批的请求';

  @override
  String get planReviewRequestedTitle => '有待审阅的 plan';

  @override
  String get approvalChannel => '审批请求';

  @override
  String get approvalChannelDescription => '会话等待你审批权限请求时通知。';

  @override
  String get planReviewChannel => 'plan 审阅';

  @override
  String get planReviewChannelDescription => '会话等待你审阅 plan 时通知。';

  @override
  String get notificationDismissTooltip => '关闭通知';

  @override
  String get workingChannel => '工作中的会话';

  @override
  String get workingChannelDescription => '会话正在执行或等待你处理时，显示不发声的常驻通知。';

  @override
  String get workingNotificationBody => '正在执行…';

  @override
  String get waitingApprovalBody => '等待你审批';

  @override
  String get waitingPlanReviewBody => '等待你审阅 plan';

  @override
  String get waitingAnswerBody => '等待你的回答';

  @override
  String get jumpToBottomTooltip => '跳到底部';

  @override
  String get settingsSectionAsr => '语音识别';

  @override
  String get asrModelsTitle => '语音识别模型';

  @override
  String get asrModelsDescription => '下载与管理端侧离线语音识别模型，提供低延迟高隐私的语音输入能力。';

  @override
  String asrInstalledCount(int installed, int total) {
    return '已装 $installed/$total';
  }

  @override
  String get asrDefaultSource => '默认下载源';

  @override
  String get asrDefaultSourceDesc => '选择首选模型镜像下载源';

  @override
  String get asrAllowCellular => '允许移动网络下载';

  @override
  String get asrAllowCellularDesc => '允许使用移动流量下载模型（大文件可能消耗较多流量）';

  @override
  String get asrModelStatusIdle => '未下载';

  @override
  String get asrModelStatusDownloading => '下载中';

  @override
  String get asrModelStatusDownloaded => '已安装';

  @override
  String get asrModelStatusFailed => '下载失败';

  @override
  String get asrModelStatusCanceled => '已取消';

  @override
  String get asrModelDiscontinued => '已下架 · 仅本地可用';

  @override
  String get asrDownloadButton => '下载';

  @override
  String get asrCancelButton => '取消';

  @override
  String get asrDeleteButton => '删除';

  @override
  String get asrRetryButton => '重试';

  @override
  String asrSwitchSourceRetry(String source) {
    return '从 $source 重试';
  }

  @override
  String get asrDeleteConfirmTitle => '删除模型';

  @override
  String asrDeleteConfirmBody(String modelName) {
    return '确定要删除 $modelName 吗？删除后将释放存储空间，可随时重新下载。';
  }

  @override
  String asrDiskUsage(String size) {
    return '占用空间: $size';
  }

  @override
  String asrSourceLabel(String source) {
    return '来源: $source';
  }

  @override
  String get asrLanguagesLabel => '支持语言';

  @override
  String get asrLicenseLabel => '开源协议';

  @override
  String asrSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String get voiceInputTooltip => '语音输入';

  @override
  String get voiceInputNoModelTitle => '需要语音识别模型';

  @override
  String get voiceInputNoModelBody => '请在设置中下载离线语音识别模型，即可开启端侧语音输入。';

  @override
  String get voiceInputGoToSettings => '前往设置';

  @override
  String get voiceInputCancel => '取消';

  @override
  String get voiceInputDone => '完成';

  @override
  String get voiceInputSlideToSend => '松开发送 · 上滑取消';

  @override
  String get voiceInputReleaseToCancel => '松开取消';

  @override
  String get voiceInputTapToFinish => '点按麦克风结束';

  @override
  String get voiceInputInitializing => '正在准备…';

  @override
  String get voiceInputFinalizing => '正在转写…';

  @override
  String get voiceInputPermissionDenied => '需要麦克风权限才能进行语音输入。';

  @override
  String get voiceInputRecordFailed => '无法启动语音录制，请检查麦克风是否可用后重试。';

  @override
  String get voiceInputSilentInput => '未检测到麦克风输入信号，请检查系统麦克风开关及是否有其他应用占用麦克风。';

  @override
  String get voiceInputInputFailed => '语音输入意外中断，请重试。';

  @override
  String get voiceInputModelUnsupported => '所选语音模型暂不受支持，请在设置中重新选择可用的语音模型。';

  @override
  String get asrActiveModel => '当前活跃模型';

  @override
  String get asrActiveModelDesc => '用于聊天中语音识别的模型。';

  @override
  String get asrNoModelInstalled => '无（请在下方下载模型）';

  @override
  String get asrVoiceInputModeTitle => '语音输入方式';

  @override
  String get asrVoiceInputModeDesc => '选择语音识别在端侧离线执行，或调用在线语音服务。';

  @override
  String get asrVoiceInputModeOffline => '离线端侧';

  @override
  String get asrVoiceInputModeOnline => '在线服务';

  @override
  String get asrOnlineProviderVolcengine => '火山引擎 · 豆包';

  @override
  String get asrOnlineProviderVolcengineHint => '豆包流式语音识别，X-Api-Key 鉴权。';

  @override
  String get asrOnlineProviderTencent => '腾讯云 · 混元';

  @override
  String get asrOnlineProviderTencentHint =>
      '实时语音识别 Hy-ASR-3.0-preview，密钥签名鉴权。';

  @override
  String get asrOnlineVolcengineApiKeyLabel => 'API Key';

  @override
  String get asrOnlineVolcengineApiKeyHint => '在火山引擎语音控制台获取';

  @override
  String get asrOnlineTencentAppIdLabel => 'AppID';

  @override
  String get asrOnlineTencentSecretIdLabel => 'SecretId';

  @override
  String get asrOnlineTencentSecretKeyLabel => 'SecretKey';

  @override
  String get asrOnlineEndpointLabel => '接入点（可选）';

  @override
  String get asrOnlineTencentLimit => '混元内测版仅支持 16k 单声道 PCM，单次识别不超过 1 分钟。';

  @override
  String get asrOnlinePrivacyNote => '密钥仅保存在本机，语音只会发送到所选服务商。';

  @override
  String get asrOnlineSaved => '语音输入设置已保存';

  @override
  String get voiceInputCloudSetupTitle => '需要配置在线语音识别';

  @override
  String get voiceInputCloudSetupBody => '请在设置中填写在线语音服务的密钥，即可开启在线语音输入。';

  @override
  String get voiceInputCloudNotConfigured => '在线语音输入需要先配置密钥，请前往 设置 → 语音识别。';

  @override
  String get voiceInputCloudConnectFailed => '无法连接在线语音服务，请检查网络与密钥后重试。';

  @override
  String get voiceInputCloudFailed => '在线语音识别失败，请检查密钥配置后重试。';

  @override
  String get errorLogsTitle => '错误日志';

  @override
  String get errorLogsDescription => '查看并导出应用运行错误记录';

  @override
  String get errorLogsEmptyTitle => '暂无错误日志';

  @override
  String get errorLogsEmptySubtitle => '应用运行良好，未捕获到任何错误。';

  @override
  String get errorLogsFilterAll => '全部';

  @override
  String get errorLogsFilterFatal => '崩溃';

  @override
  String get errorLogsFilterError => '错误';

  @override
  String get errorLogsFilterWarn => '警告';

  @override
  String get errorLogsSearchHint => '搜索错误信息或堆栈…';

  @override
  String get errorLogsCopyAll => '复制全部';

  @override
  String get errorLogsCopyAllSuccess => '已复制全部错误日志到剪贴板';

  @override
  String get errorLogsCopyEntry => '复制';

  @override
  String get errorLogsCopyEntrySuccess => '已复制该错误详情到剪贴板';

  @override
  String get errorLogsClear => '清空';

  @override
  String get errorLogsClearConfirmTitle => '清空错误日志';

  @override
  String get errorLogsClearConfirmMessage => '确定要清空所有已记录的错误日志吗？此操作无法撤销。';

  @override
  String get errorLogsClearSuccess => '错误日志已清空';

  @override
  String get errorLogsStackTrace => '堆栈信息';

  @override
  String get errorLogsBreadcrumbs => '关联运行日志';

  @override
  String get errorLogsContext => '上下文信息';

  @override
  String get errorLogsSystemInfo => '系统与构建信息';

  @override
  String get errorLogsCopySystemInfo => '复制系统信息';

  @override
  String get errorLogsSystemInfoCopied => '已复制系统信息到剪贴板';

  @override
  String errorLogsCountBadge(int count) {
    return '$count 条错误';
  }

  @override
  String get errorLogsNoSearchResults => '未找到匹配的错误日志。';

  @override
  String get previewFile => '预览';

  @override
  String get copyPath => '复制路径';

  @override
  String get copyContent => '复制内容';

  @override
  String get copiedFeedback => '已复制到剪贴板';

  @override
  String get filePreviewFailed => '加载文件预览失败';

  @override
  String get filePreviewBinary => '该文件不是文本，无法预览。';

  @override
  String get filePreviewEmpty => '该文件为空。';

  @override
  String filePreviewTruncated(int count) {
    return '仅预览前 $count 行';
  }

  @override
  String get sessionAlreadyOwnedError => '当前会话正被宿主其他进程或命令行独占写入。';

  @override
  String get chatActionFailed => '该操作未能完成。';

  @override
  String get chatLoadFailed => '无法加载此会话。';

  @override
  String get systemPromptUpdated => '系统提示词已更新';

  @override
  String get trajectoryTitle => '轨迹';

  @override
  String get trajectorySearchHint => '搜索轨迹';

  @override
  String get trajectorySearchClear => '清除搜索';

  @override
  String trajectorySearchMatches(int matches, int total) {
    return '匹配 $matches / $total';
  }

  @override
  String get trajectoryLoadOlder => '加载更早记录';

  @override
  String get trajectoryLoadingOlder => '正在加载更早记录…';

  @override
  String get trajectoryLoadOlderFailed => '加载更早记录失败，请重试。';

  @override
  String get trajectoryNoMatches => '已加载的记录中没有匹配项。';

  @override
  String get trajectoryEmpty => '此会话暂无轨迹记录。';

  @override
  String get trajectoryBeforeFirstTurn => '首轮之前';

  @override
  String trajectoryTurnLabel(int turn) {
    return '第 $turn 轮';
  }

  @override
  String trajectoryTurnSummary(int records, int tools) {
    String _temp0 = intl.Intl.pluralLogic(
      records,
      locale: localeName,
      other: '$records 条记录',
    );
    String _temp1 = intl.Intl.pluralLogic(
      tools,
      locale: localeName,
      other: '$tools 个工具',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String trajectoryStepLabel(int step) {
    return '步骤 $step';
  }

  @override
  String trajectoryStepRecordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条记录',
    );
    return '$_temp0';
  }

  @override
  String get trajectoryKindUser => '用户';

  @override
  String get trajectoryKindContext => '上下文';

  @override
  String get trajectoryKindAssistant => '助手';

  @override
  String get trajectoryKindTool => '工具';

  @override
  String get trajectoryKindCompaction => '已压缩';

  @override
  String get trajectoryKindCommand => '命令';

  @override
  String get trajectoryKindError => '错误';

  @override
  String get trajectoryStatusStreaming => '接收中';

  @override
  String get trajectoryFactTurn => '轮次';

  @override
  String get trajectoryFactStep => '步骤';

  @override
  String get trajectoryFactKind => '类型';

  @override
  String get trajectoryFactStatus => '状态';

  @override
  String get trajectoryFactStarted => '开始时间';

  @override
  String get trajectoryFactFirstToken => '首 token';

  @override
  String get trajectoryFactDuration => '时长';

  @override
  String get trajectoryFactParentCall => '父调用';

  @override
  String get trajectoryFactOutsideStep => '不属于任何步骤';

  @override
  String get trajectoryFactUnavailable => '不可用';

  @override
  String get trajectoryTimingNotRecorded => '未记录';

  @override
  String get trajectoryDurationNotRecorded => '会话日志未记录该记录的结束时间。';

  @override
  String get trajectoryUsageSection => 'Token 用量';

  @override
  String get trajectoryUsageNotReported => '宿主未上报该记录的用量。';

  @override
  String get trajectoryUsageInput => '输入';

  @override
  String get trajectoryUsageCachedRead => '缓存读取';

  @override
  String get trajectoryUsageCacheWrite => '缓存写入';

  @override
  String get trajectoryUsageOutput => '输出';

  @override
  String get trajectoryUsageReasoning => '推理';

  @override
  String get trajectoryInputSection => '输入';

  @override
  String get trajectoryOutputSection => '输出';

  @override
  String trajectoryTokenCount(int value) {
    return '$value tok';
  }

  @override
  String trajectoryTurnUsage(String input, String output) {
    return '输入 $input · 输出 $output';
  }

  @override
  String get trajectoryEntryTooltip => '轨迹';

  @override
  String get settingsSectionProviders => '提供方';

  @override
  String get providersIntro => '添加提供方、录入其 API 密钥，并发现它提供的模型。';

  @override
  String get providersReadOnlyNotice => '此部署中的设置文档为只读。';

  @override
  String providersLoadFailed(String error) {
    return '无法加载提供方：$error';
  }

  @override
  String providerCredentialUnavailable(String error) {
    return '凭证状态不可用：$error';
  }

  @override
  String get providerStateLive => '在线';

  @override
  String get providerStateDormant => '休眠';

  @override
  String get providerDeclared => '手工声明';

  @override
  String providerNeedsRepair(String error) {
    return '需要修复：$error';
  }

  @override
  String get providersEmpty => '此宿主没有可配置的提供方。';

  @override
  String get addProvider => '添加提供方';

  @override
  String get addProviderFamilyLabel => '设置命名空间';

  @override
  String get addProviderRouteLabel => '路由 ID';

  @override
  String get addProviderRouteHint => 'acme-gateway';

  @override
  String get addProviderRouteInvalid => '请使用小写字母、数字和单个连字符，并以字母开头。';

  @override
  String get addProviderRouteTaken => '该路由已存在。';

  @override
  String get addProviderDisplayNameLabel => '显示名称（可选）';

  @override
  String get addProviderBaseUrlLabel => 'Base URL（可选）';

  @override
  String get addProviderBaseUrlInvalid => '请输入 http:// 或 https:// 开头的地址。';

  @override
  String get addProviderProtocolLabel => '协议（可选）';

  @override
  String get addProviderModelsLabel => '模型 ID，每行一个（可选）';

  @override
  String get addProviderModelsHint => '适配器尚不认识的提供方至少需要一个模型。';

  @override
  String providerRouteLine(String route) {
    return '路由 $route';
  }

  @override
  String providerKeyRefLine(String ref) {
    return '密钥引用 $ref';
  }

  @override
  String get providerKeyHint => '该值会写入宿主凭证库，之后不再显示。';

  @override
  String get providerRemoveAction => '移除提供方';

  @override
  String providerRemoveConfirm(String name) {
    return '移除 $name？';
  }

  @override
  String get providerRemoveBody => '将删除已存储的配置档；已存储的 API 密钥会保留。';

  @override
  String get discoverModels => '发现模型';

  @override
  String get discoverModelsEmpty => '该端点未公布任何模型。';

  @override
  String discoverModelsFailed(String error) {
    return '模型发现失败：$error';
  }

  @override
  String get discoveredModelsTitle => '公布的模型';

  @override
  String modelContextWindowLine(int tokens) {
    return '上下文 $tokens';
  }

  @override
  String modelMaxTokensLine(int tokens) {
    return '最大输出 $tokens';
  }

  @override
  String get providerFooter => '提供方路由与配置档存放在宿主的设置文档中，密钥走宿主凭证通道。';

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get aboutVersionLabel => '应用版本';

  @override
  String aboutVersionLine(String version, String build) {
    return '$version（构建 $build）';
  }

  @override
  String get aboutDocs => '文档';

  @override
  String get aboutFeedback => '报告问题或发送反馈';

  @override
  String get aboutLinkFailed => '无法打开该链接。';

  @override
  String get producedFilesLabel => '本轮文件改动';

  @override
  String producedFilesMore(int count) {
    return '+ $count 个文件';
  }

  @override
  String producedFilesOpen(String name) {
    return '打开 $name';
  }

  @override
  String messageTokensPerSecond(String tps) {
    return '$tps tok/s';
  }

  @override
  String messageTokenUsage(String tokens) {
    return '$tokens tok';
  }

  @override
  String get settingsAppearanceTitle => '外观';

  @override
  String get settingsAppearanceLight => '浅色';

  @override
  String get settingsAppearanceDark => '深色';

  @override
  String get settingsAppearanceOled => '纯黑';

  @override
  String get settingsAppearanceSystem => '跟随系统';

  @override
  String get settingsAppearanceUnavailable => '主机主题设置不可用。';

  @override
  String get settingsAppearanceSaveFailed => '无法保存主题选择。';

  @override
  String get cordisApprovalHeader => '插件审批';

  @override
  String get cordisPurposeLabel => '用途';

  @override
  String get cordisPluginIdLabel => '插件 ID';

  @override
  String get cordisPackageIdLabel => '包 ID';

  @override
  String get cordisModeRun => '运行';

  @override
  String get cordisModeUpdate => '更新';

  @override
  String get cordisRejectOnlyNotice =>
      '此手机只能拒绝：批准需要浏览器插件运行时来上报它创建的激活，而本客户端没有该运行时。拒绝会释放被阻塞的工具调用，两半都不执行。';

  @override
  String get cordisAnswerFailed => '主机未接受该插件决定。';

  @override
  String get backendTestConnection => '测试连接';

  @override
  String get backendProbeRunning => '正在测试连接…';

  @override
  String get backendProbeReachable => '可访问。主机按 dsh 契约作出了应答。';

  @override
  String get backendProbeUnreachable =>
      '该地址没有 dsh 应答。请检查基础 URL、网关是否已启动，以及手机能否访问它。';

  @override
  String get backendProbeCertificateNotTrusted =>
      'TLS 握手失败。主机的证书不受信任——如果该网关由你控制，请打开上方的“信任此主机的证书”。';

  @override
  String get backendProbeAuthenticationRequired =>
      '该网关要求本客户端没有的配对或凭据（部署层认证，或 dsh web 打印在 URL 中的令牌）。本客户端不执行任何认证。';

  @override
  String get backendProbeNotDshSurface =>
      '有服务作了应答，但它不是 dsh 主机：该地址没有 dsh RPC 路由。';

  @override
  String backendProbeUnexpectedStatus(int status) {
    return '主机返回了 HTTP $status，这不是 dsh 契约使用的状态。';
  }

  @override
  String get backendProbeUnenvelopedResponse => '主机有应答，但返回的不是 dsh JSON-RPC 响应。';

  @override
  String get backendProbeUnknown => '无法判定该连接失败的类型。';

  @override
  String get backendProbeAmbiguousTls =>
      '该失败是 TLS 握手错误；可能是系统不信任的证书，也可能是其他 TLS 不匹配。';

  @override
  String get backendProbeSaveNotBlocked => '保存不会被阻止——主机可以在配置期间离线。';

  @override
  String workflowMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个成员',
      one: '1 个成员',
    );
    return '$_temp0';
  }

  @override
  String get workflowRunEmpty => '没有启动成员';

  @override
  String get workflowPhaseUnassigned => '未分阶段';

  @override
  String get workflowPhaseEmpty => '空阶段名';

  @override
  String get workflowMemberEmpty => '空成员名';

  @override
  String workflowMemberOpen(String name) {
    return '打开 $name';
  }

  @override
  String get workflowStatusRunning => '运行中';

  @override
  String get workflowStatusCompleted => '已完成';

  @override
  String get workflowStatusFailed => '失败';

  @override
  String get workflowStatusCancelled => '已取消';

  @override
  String get workflowStatusInterrupted => '已中断';

  @override
  String workflowStatusCountRunning(int count) {
    return '运行中 $count';
  }

  @override
  String workflowStatusCountCompleted(int count) {
    return '已完成 $count';
  }

  @override
  String workflowStatusCountFailed(int count) {
    return '失败 $count';
  }

  @override
  String workflowStatusCountCancelled(int count) {
    return '已取消 $count';
  }

  @override
  String workflowStatusCountInterrupted(int count) {
    return '已中断 $count';
  }

  @override
  String get hookAuditPending => '处理中';

  @override
  String hookAuditDecision(String decision) {
    return '$decision';
  }

  @override
  String hookAuditDurationMs(int durationMs) {
    return '$durationMs 毫秒';
  }

  @override
  String get hookAuditPoint => '触发点';

  @override
  String get hookAuditDialect => '方言';

  @override
  String get hookDialectClaudeCode => 'Claude Code';

  @override
  String get hookDialectCodex => 'Codex';

  @override
  String get hookAuditMatcher => '匹配器';

  @override
  String get hookAuditDecisionLabel => '决定';

  @override
  String get hookAuditExitCode => '退出码';

  @override
  String get hookAuditUnknown => '主机未上报';

  @override
  String get hookAuditStderr => '标准错误';

  @override
  String get hookAuditNoStderr => '无';

  @override
  String get sandboxModeUnknownTooltip => '该会话尚未上报沙箱模式，实际生效的是主机的部署默认值。';

  @override
  String sandboxModeTooltip(String mode) {
    return '沙箱：$mode';
  }

  @override
  String get sandboxModeReadOnly => '只读';

  @override
  String get sandboxModeWorkspaceWrite => '工作区可写';

  @override
  String get sandboxModeDangerFullAccess => '完全访问';

  @override
  String get scheduleStripTitle => '提醒';

  @override
  String scheduleReminderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个提醒',
      one: '1 个提醒',
    );
    return '$_temp0';
  }

  @override
  String get scheduleUnknown => '该主机未上报';

  @override
  String get scheduleEmpty => '当前没有';

  @override
  String scheduleNextAt(String at) {
    return '下一个 $at';
  }

  @override
  String scheduleOverdueCount(int count) {
    return '$count 个已逾期';
  }

  @override
  String scheduleMoreCount(int count) {
    return '另有 $count 个';
  }

  @override
  String get scheduleFrequencyOnce => '单次';

  @override
  String scheduleFrequencyEvery(int value, String unit) {
    return '每 $value $unit';
  }

  @override
  String get scheduleUnitDay => '天';

  @override
  String get scheduleUnitDays => '天';

  @override
  String get scheduleUnitHour => '小时';

  @override
  String get scheduleUnitHours => '小时';

  @override
  String get scheduleUnitMinute => '分钟';

  @override
  String get scheduleUnitMinutes => '分钟';

  @override
  String get scheduleUnitSecond => '秒';

  @override
  String get scheduleUnitSeconds => '秒';
}
