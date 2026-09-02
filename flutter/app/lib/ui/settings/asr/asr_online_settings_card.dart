/// Voice-input mode card: on-device vs online transcription, with the
/// selected provider's credential form.
///
/// The card rides the ASR models screen above the model catalog. Mode and
/// provider choices persist immediately; credential fields commit through
/// the Save action so a half-typed secret never reaches the store.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';

import '../../../di/providers.dart';

/// The voice-input mode card.
class AsrOnlineSettingsCard extends StatelessWidget {
  const AsrOnlineSettingsCard({
    required this.cloud,
    required this.onAction,
    super.key,
  });

  /// Current voice-input settings; null while the store loads.
  final OnlineAsrSettings? cloud;
  final void Function(AsrModelsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final OnlineAsrSettings settings = cloud ?? const OnlineAsrSettings();

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.asrVoiceInputModeTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.asrVoiceInputModeDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<VoiceInputMode>(
              segments: <ButtonSegment<VoiceInputMode>>[
                ButtonSegment<VoiceInputMode>(
                  value: VoiceInputMode.offline,
                  label: Text(l10n.asrVoiceInputModeOffline),
                  icon: const Icon(Icons.phone_android_outlined),
                ),
                ButtonSegment<VoiceInputMode>(
                  value: VoiceInputMode.online,
                  label: Text(l10n.asrVoiceInputModeOnline),
                  icon: const Icon(Icons.cloud_outlined),
                ),
              ],
              selected: <VoiceInputMode>{settings.mode},
              onSelectionChanged: (Set<VoiceInputMode> selected) {
                if (selected.isNotEmpty) {
                  onAction(SetVoiceInputModeAction(selected.first));
                }
              },
            ),
            if (cloud != null &&
                settings.mode == VoiceInputMode.online) ...<Widget>[
              const Divider(height: 24),
              // The ancestor RadioGroup owns the group value and change
              // routing; the tiles carry only their own value.
              RadioGroup<OnlineAsrProvider>(
                groupValue: settings.provider,
                onChanged: (OnlineAsrProvider? provider) {
                  if (provider != null) {
                    onAction(SetCloudProviderAction(provider));
                  }
                },
                child: Column(
                  children: <Widget>[
                    RadioListTile<OnlineAsrProvider>(
                      contentPadding: EdgeInsets.zero,
                      value: OnlineAsrProvider.volcengineDoubao,
                      title: Text(l10n.asrOnlineProviderVolcengine),
                      subtitle: Text(
                        l10n.asrOnlineProviderVolcengineHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    RadioListTile<OnlineAsrProvider>(
                      contentPadding: EdgeInsets.zero,
                      value: OnlineAsrProvider.tencentHunyuan,
                      title: Text(l10n.asrOnlineProviderTencent),
                      subtitle: Text(
                        l10n.asrOnlineProviderTencentHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (settings.provider == OnlineAsrProvider.volcengineDoubao)
                _VolcengineForm(
                  key: const ValueKey<OnlineAsrProvider>(
                    OnlineAsrProvider.volcengineDoubao,
                  ),
                  config: settings.volcengine,
                  onAction: onAction,
                )
              else
                _TencentForm(
                  key: const ValueKey<OnlineAsrProvider>(
                    OnlineAsrProvider.tencentHunyuan,
                  ),
                  config: settings.tencent,
                  onAction: onAction,
                ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.asrOnlinePrivacyNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Credential form for Volcengine Doubao.
class _VolcengineForm extends StatefulWidget {
  const _VolcengineForm({
    required this.config,
    required this.onAction,
    super.key,
  });

  final VolcengineDoubaoAsrConfig config;
  final void Function(AsrModelsAction) onAction;

  @override
  State<_VolcengineForm> createState() => _VolcengineFormState();
}

class _VolcengineFormState extends State<_VolcengineForm> {
  late final TextEditingController _apiKey = TextEditingController(
    text: widget.config.apiKey,
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.config.endpoint,
  );

  VolcengineDoubaoAsrConfig _lastSeen = const VolcengineDoubaoAsrConfig();

  @override
  void initState() {
    super.initState();
    _lastSeen = widget.config;
  }

  @override
  void didUpdateWidget(_VolcengineForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A save round-trip (or an external change) lands here; reseed the
    // fields so the form reflects the store. Typed-but-unsaved edits are
    // not clobbered: the values only differ when the store actually moved.
    if (widget.config != _lastSeen) {
      _lastSeen = widget.config;
      _apiKey.text = widget.config.apiKey;
      _endpoint.text = widget.config.endpoint;
    }
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  void _save(AppLocalizations l10n) {
    widget.onAction(
      SaveVolcengineConfigAction(
        widget.config.copyWith(
          apiKey: _apiKey.text.trim(),
          endpoint: _endpoint.text.trim(),
        ),
      ),
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.asrOnlineSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SecretField(
          label: l10n.asrOnlineVolcengineApiKeyLabel,
          hint: l10n.asrOnlineVolcengineApiKeyHint,
          controller: _apiKey,
        ),
        const SizedBox(height: 10),
        _PlainField(
          label: l10n.asrOnlineEndpointLabel,
          hint: VolcengineDoubaoAsrConfig.defaultEndpoint,
          controller: _endpoint,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () => _save(l10n),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}

/// Credential form for Tencent Hunyuan.
class _TencentForm extends StatefulWidget {
  const _TencentForm({required this.config, required this.onAction, super.key});

  final TencentHunyuanAsrConfig config;
  final void Function(AsrModelsAction) onAction;

  @override
  State<_TencentForm> createState() => _TencentFormState();
}

class _TencentFormState extends State<_TencentForm> {
  late final TextEditingController _appId = TextEditingController(
    text: widget.config.appId,
  );
  late final TextEditingController _secretId = TextEditingController(
    text: widget.config.secretId,
  );
  late final TextEditingController _secretKey = TextEditingController(
    text: widget.config.secretKey,
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.config.endpoint,
  );

  TencentHunyuanAsrConfig _lastSeen = const TencentHunyuanAsrConfig();

  @override
  void initState() {
    super.initState();
    _lastSeen = widget.config;
  }

  @override
  void didUpdateWidget(_TencentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != _lastSeen) {
      _lastSeen = widget.config;
      _appId.text = widget.config.appId;
      _secretId.text = widget.config.secretId;
      _secretKey.text = widget.config.secretKey;
      _endpoint.text = widget.config.endpoint;
    }
  }

  @override
  void dispose() {
    _appId.dispose();
    _secretId.dispose();
    _secretKey.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  void _save(AppLocalizations l10n) {
    widget.onAction(
      SaveTencentConfigAction(
        widget.config.copyWith(
          appId: _appId.text.trim(),
          secretId: _secretId.text.trim(),
          secretKey: _secretKey.text.trim(),
          endpoint: _endpoint.text.trim(),
        ),
      ),
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.asrOnlineSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PlainField(label: l10n.asrOnlineTencentAppIdLabel, controller: _appId),
        const SizedBox(height: 10),
        _PlainField(
          label: l10n.asrOnlineTencentSecretIdLabel,
          controller: _secretId,
        ),
        const SizedBox(height: 10),
        _SecretField(
          label: l10n.asrOnlineTencentSecretKeyLabel,
          controller: _secretKey,
        ),
        const SizedBox(height: 10),
        _PlainField(
          label: l10n.asrOnlineEndpointLabel,
          hint: TencentHunyuanAsrConfig.defaultEndpoint,
          controller: _endpoint,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.asrOnlineTencentLimit,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () => _save(l10n),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}

/// One labeled text field for non-secret values.
class _PlainField extends StatelessWidget {
  const _PlainField({required this.label, required this.controller, this.hint});

  final String label;
  final String? hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/// One labeled secret field with a visibility toggle.
class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 18,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
