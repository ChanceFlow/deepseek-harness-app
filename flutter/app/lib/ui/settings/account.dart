/// `Settings` → Account: the host's account projection.
///
/// The page renders exactly the facts the host reports and no derived ones:
/// the sign-in state, the Platform profile, the recharge and granted wallet
/// balances, and any granted bonus the Platform has not yet recorded as
/// displayed. A host that composes no account plane, holds no credential, or
/// could not read one field says so in that field's own line — the page never
/// prints a zero balance or an empty name it did not receive.
///
/// The reads mirror the reference account settings plugin
/// (`reference/deepseek-harness/packages/client/ui-settings-account/src/client/
/// index.ts`): the state read is the gate, then the profile, balance and bonus
/// reads are independent, so one failure cannot blank the others. The reference
/// also acknowledges a bonus order only once its card has passed a presented
/// frame, and so does this page: the acknowledgement is queued as a post-frame
/// callback for the frame that carries the notice.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/account.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../di/providers.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';

/// `Settings` → Account. Always navigable: a deployment without the account
/// service gets a page that states it rather than a dead row.
class SettingsAccountPage extends ConsumerStatefulWidget {
  const SettingsAccountPage({super.key});

  @override
  ConsumerState<SettingsAccountPage> createState() =>
      _SettingsAccountPageState();
}

class _SettingsAccountPageState extends ConsumerState<SettingsAccountPage> {
  AccountState? _state;
  AccountProfileResult? _profile;
  AccountBalanceResult? _balance;
  AccountBonusBatch? _bonuses;

  bool _loading = true;
  bool _unavailable = false;

  /// The bonus read itself failed (a host error), which is not the same fact
  /// as the host reporting no unseen bonus.
  bool _bonusesReadFailed = false;

  /// The acknowledgement did not land, so the notice is still unseen on the
  /// server; the card offers the retry instead of pretending it settled.
  bool _ackFailed = false;

  /// Orders this page already acknowledged or tried to, so one mount cannot
  /// acknowledge twice. [retryAck] removes an order before trying again.
  final Set<String> _ackAttempted = <String>{};

  /// Orders the reader closed; their notice no longer renders.
  final Set<String> _dismissed = <String>{};

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The client identity carries the active language, which is an inherited
    // fact, so the load starts here rather than in initState.
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  /// Identity of this UI for one account call, sampled at call time so a
  /// language switch carries into the next read.
  AccountClientIdentity _clientIdentity() {
    final Locale locale = Localizations.localeOf(context);
    return AccountClientIdentity(
      version: kDshAppVersion,
      // The host reduces the language to `zh_CN` / `en_US`, so the tagged form
      // is enough.
      locale: locale.toLanguageTag(),
      // `DateTime.timeZoneOffset` is already seconds east of Greenwich, the
      // sign the Platform client header wants.
      timezoneOffsetSeconds: DateTime.now().timeZoneOffset.inSeconds,
    );
  }

  Future<void> _load() async {
    final String backendId = ref.read(settingsBackendScopeProvider);
    if (backendId.isEmpty) {
      setState(() {
        _loading = false;
        _unavailable = true;
      });
      return;
    }
    final ChatRepository repository = ref.read(
      chatRepositoryProvider(backendId),
    );
    final AccountClientIdentity client = _clientIdentity();
    try {
      final AccountState state = await repository.loadAccountState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
        _unavailable = false;
      });
    } catch (_) {
      // A deployment that composes no account service answers an RPC failure
      // rather than an empty projection.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unavailable = true;
      });
      return;
    }
    if (_state?.status != AccountSignInStatus.credentialStored) return;
    // The three detail reads are independent in the reference too, so each
    // settles into its own line.
    await Future.wait<void>(<Future<void>>[
      _readProfile(repository, client),
      _readBalance(repository, client),
      _readBonuses(repository, client),
    ]);
  }

  Future<void> _readProfile(
    ChatRepository repository,
    AccountClientIdentity client,
  ) async {
    try {
      final AccountProfileResult? result = await repository.loadAccountProfile(
        client,
      );
      if (!mounted) return;
      setState(() => _profile = result);
    } catch (_) {
      if (!mounted) return;
      // A failed read stays distinct from a null answer: the card says the
      // profile could not be read, which is all the host reported.
      setState(() => _profile = const AccountProfileFailed());
    }
  }

  Future<void> _readBalance(
    ChatRepository repository,
    AccountClientIdentity client,
  ) async {
    try {
      final AccountBalanceResult? result = await repository.loadAccountBalance(
        client,
      );
      if (!mounted) return;
      setState(() => _balance = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _balance = const AccountBalanceFailed());
    }
  }

  Future<void> _readBonuses(
    ChatRepository repository,
    AccountClientIdentity client,
  ) async {
    try {
      final AccountBonusBatch? batch = await repository.loadUnnotifiedBonuses(
        client,
      );
      if (!mounted) return;
      setState(() {
        _bonuses = batch;
        _bonusesReadFailed = false;
      });
      _scheduleAck();
    } catch (_) {
      if (!mounted) return;
      setState(() => _bonusesReadFailed = true);
    }
  }

  /// The bonus this page renders: the first the reader has not closed, in the
  /// server's own order.
  AccountBonusGrant? get _shownGrant {
    final AccountBonusBatch? batch = _bonuses;
    if (batch == null) return null;
    for (final AccountBonusGrant grant in batch.bonuses) {
      if (!_dismissed.contains(grant.orderId)) return grant;
    }
    return null;
  }

  /// Queue the acknowledgement for the notice this page is about to paint.
  ///
  /// The reference records an order only after its card reported a presented
  /// frame; the phone's equivalent boundary is the frame carrying the notice,
  /// so the call is a post-frame callback and never fires for a bonus the page
  /// did not render. A bonus the read offered after the frame the page already
  /// painted is acknowledged by [retryAck] or by closing the card.
  void _scheduleAck() {
    final AccountBonusBatch? batch = _bonuses;
    final AccountBonusGrant? grant = _shownGrant;
    if (batch == null || grant == null) return;
    if (_ackAttempted.contains(grant.orderId)) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      unawaited(_acknowledge(batch.accountId, grant.orderId));
    });
  }

  Future<void> _acknowledge(String accountId, String orderId) async {
    if (!_ackAttempted.add(orderId)) return;
    final String backendId = ref.read(settingsBackendScopeProvider);
    if (backendId.isEmpty) return;
    final ChatRepository repository = ref.read(
      chatRepositoryProvider(backendId),
    );
    try {
      final bool settled = await repository.ackBonusNotified(
        _clientIdentity(),
        accountId: accountId,
        orderId: orderId,
      );
      if (!mounted) return;
      // The host answers false when it cannot settle the order (no grant, or
      // the account changed); nothing was recorded, so the card says so.
      setState(() => _ackFailed = !settled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ackFailed = true);
    }
  }

  /// Closing the card counts as having seen it, exactly as in the reference,
  /// so it queues the acknowledgement before hiding the notice.
  void _dismissNotice(AccountBonusGrant grant, String accountId) {
    setState(() => _dismissed.add(grant.orderId));
    unawaited(_acknowledge(accountId, grant.orderId));
    // A batch may carry several grants; closing one paints the next, and that
    // card earns its own presented-frame acknowledgement.
    _scheduleAck();
  }

  void _retryAck() {
    final AccountBonusBatch? batch = _bonuses;
    final AccountBonusGrant? grant = _shownGrant;
    if (batch == null || grant == null) return;
    _ackAttempted.remove(grant.orderId);
    setState(() => _ackFailed = false);
    unawaited(_acknowledge(batch.accountId, grant.orderId));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final AccountState? state = _state;
    final bool signedIn = state?.status == AccountSignInStatus.credentialStored;
    return SettingsPageScaffold(
      title: l10n.settingsNavAccount,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsNavAccount,
          intro: l10n.accountIntro,
          showTitle: false,
        ),
        if (_unavailable)
          SettingsSectionCard(
            children: <Widget>[
              _AccountNotice(
                headline: l10n.accountUnavailable,
                body: l10n.accountUnavailableBody,
              ),
            ],
          )
        else if (_loading || state == null)
          SettingsSectionCard(
            children: <Widget>[_AccountLoadingLine(text: l10n.accountLoading)],
          )
        else ...<Widget>[
          _identityCard(l10n, state),
          if (signedIn) ...<Widget>[
            const SizedBox(height: 12),
            _balanceCard(l10n),
            ..._bonusSection(l10n),
          ],
        ],
      ],
    );
  }

  Widget _identityCard(AppLocalizations l10n, AccountState state) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool signedIn = state.status == AccountSignInStatus.credentialStored;
    final AccountProfileResult? result = _profile;
    final AccountProfile? profile = result is AccountProfileReady
        ? result.profile
        : null;
    final String title = signedIn
        ? profile?.name ?? profile?.contact ?? l10n.accountSignedIn
        : l10n.accountSignedOut;
    final String body;
    if (!signedIn) {
      body = l10n.accountSignedOutBody;
    } else if (profile == null) {
      body = l10n.accountProfileUnavailable;
    } else {
      body = _profileFacts(l10n, profile);
    }
    return SettingsSectionCard(
      children: <Widget>[
        ListTile(
          leading: Icon(
            Icons.account_circle_outlined,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// The profile's own facts beside its name: the masked contact and the
  /// Platform id, joined the way the other Settings cards join metadata.
  String _profileFacts(AppLocalizations l10n, AccountProfile profile) {
    final List<String> facts = <String>[
      if (profile.contact case final String contact) contact,
      if (profile.id case final String id) l10n.accountProfileId(id),
    ];
    return facts.isEmpty ? l10n.accountSignedIn : facts.join(' · ');
  }

  Widget _balanceCard(AppLocalizations l10n) {
    return SettingsSectionCard(
      children: <Widget>[
        _factRow(l10n.accountBalance, _walletLine(l10n, bonus: false)),
        const SettingsCardDivider(),
        _factRow(l10n.accountBonusBalance, _walletLine(l10n, bonus: true)),
      ],
    );
  }

  /// One wallet line: the amounts the host reported, or which of the four
  /// states this read settled in. The amounts print the server's own decimal
  /// strings, because re-rounding them here would report a figure the account
  /// does not hold.
  String _walletLine(AppLocalizations l10n, {required bool bonus}) {
    final AccountBalanceResult? balance = _balance;
    if (balance is! AccountBalanceReady) {
      return balance == null
          ? l10n.accountBalanceAbsent
          : l10n.accountBalanceUnavailable;
    }
    final List<AccountWallet> wallets = bonus
        ? balance.bonusWallets
        : balance.wallets;
    if (wallets.isEmpty) {
      return bonus ? l10n.accountBonusNone : l10n.accountBalanceNone;
    }
    return wallets
        .map(
          (AccountWallet wallet) =>
              '${_currencySymbol(wallet.currency)}${wallet.balance}',
        )
        .join(' · ');
  }

  List<Widget> _bonusSection(AppLocalizations l10n) {
    if (_bonusesReadFailed) {
      return <Widget>[
        const SizedBox(height: 12),
        SettingsSectionCard(
          children: <Widget>[
            _AccountNotice(
              headline: l10n.accountUnseenBonus,
              body: l10n.accountBonusUnavailable,
            ),
          ],
        ),
      ];
    }
    final AccountBonusBatch? batch = _bonuses;
    if (batch == null) {
      return <Widget>[
        const SizedBox(height: 12),
        SettingsSectionCard(
          children: <Widget>[
            _AccountNotice(
              headline: l10n.accountUnseenBonus,
              body: l10n.accountBonusAbsent,
            ),
          ],
        ),
      ];
    }
    final AccountBonusGrant? grant = _shownGrant;
    if (grant == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 12),
      SettingsSectionHeading(title: l10n.accountUnseenBonus),
      SettingsSectionCard(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: _bonusBody(l10n, grant),
          ),
          const SettingsCardDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Row(
              children: <Widget>[
                if (_ackFailed) ...<Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        l10n.accountBonusAckFailed,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _retryAck,
                    child: Text(l10n.accountBonusAckRetry),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => _dismissNotice(grant, batch.accountId),
                  child: Text(l10n.accountBonusAck),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _bonusBody(AppLocalizations l10n, AccountBonusGrant grant) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.accountBonusTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_currencySymbol(grant.currency)}${grant.amount}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Server-authored copy, already localized for the language this read
        // carried; the phone never rewrites it.
        Text(grant.message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Text(
          l10n.accountBonusWindow(grant.grantedAt, grant.expiresAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _factRow(String label, String value) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Platform wallet symbols. The amount itself is printed verbatim.
String _currencySymbol(AccountCurrency currency) => switch (currency) {
  AccountCurrency.cny => '¥',
  AccountCurrency.usd => r'$',
};

class _AccountLoadingLine extends StatelessWidget {
  const _AccountLoadingLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }
}

/// One stated absence: what the host did not report, and why that is not a
/// zero or an empty value.
class _AccountNotice extends StatelessWidget {
  const _AccountNotice({required this.headline, required this.body});

  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            headline,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
