/// Account settings page: the host's sign-in state, profile, wallet balances
/// and unseen granted bonus drive the page, and the acknowledgement is sent
/// once the notice has been rendered.
///
/// A host that reports nothing is asserted through the same real entry path:
/// the page states the absence instead of printing a zero balance or an empty
/// name.
library;

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/account.dart';
import 'package:app/ui/settings/settings_backend_scope.dart';
import 'package:domain/model/account.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const String _backendId = 'default';

class _FixedScope extends SettingsBackendScope {
  @override
  String build() => _backendId;
}

/// The account half of [ChatRepository]; every other member stays unimplemented
/// so an accidental call fails loudly.
class _FakeAccountRepository extends Fake implements ChatRepository {
  _FakeAccountRepository({
    required this.readState,
    this.profile,
    this.balance,
    this.bonuses,
    this.ackResult = true,
  });

  /// The state read; throwing stands for a deployment that composes no
  /// account service.
  final Future<AccountState> Function() readState;

  AccountProfileResult? profile;
  AccountBalanceResult? balance;
  AccountBonusBatch? bonuses;
  bool ackResult;

  int profileReads = 0;
  int balanceReads = 0;
  int bonusReads = 0;
  final List<(String accountId, String orderId)> acks =
      <(String accountId, String orderId)>[];
  final List<AccountClientIdentity> identities = <AccountClientIdentity>[];

  @override
  Future<AccountState> loadAccountState() => readState();

  @override
  Future<AccountProfileResult?> loadAccountProfile(
    AccountClientIdentity client,
  ) async {
    profileReads++;
    identities.add(client);
    return profile;
  }

  @override
  Future<AccountBalanceResult?> loadAccountBalance(
    AccountClientIdentity client,
  ) async {
    balanceReads++;
    identities.add(client);
    return balance;
  }

  @override
  Future<AccountBonusBatch?> loadUnnotifiedBonuses(
    AccountClientIdentity client,
  ) async {
    bonusReads++;
    identities.add(client);
    return bonuses;
  }

  @override
  Future<bool> ackBonusNotified(
    AccountClientIdentity client, {
    required String accountId,
    required String orderId,
  }) async {
    identities.add(client);
    acks.add((accountId, orderId));
    return ackResult;
  }
}

const AccountState _signedIn = AccountState(
  status: AccountSignInStatus.credentialStored,
  links: AccountLinks(
    usageUrl: 'https://platform.example/usage',
    topUpUrl: 'https://platform.example/top_up',
  ),
  attempt: null,
);

const AccountProfile _profile = AccountProfile(
  id: 'user-7',
  name: 'Ada',
  contact: 'a***@example.com',
  avatarUrl: null,
);

const AccountBalanceReady _balance = AccountBalanceReady(
  wallets: <AccountWallet>[
    AccountWallet(currency: AccountCurrency.cny, balance: '12.34'),
  ],
  bonusWallets: <AccountWallet>[
    AccountWallet(currency: AccountCurrency.usd, balance: '0.50'),
  ],
);

const AccountBonusGrant _grant = AccountBonusGrant(
  orderId: 'order-1',
  campaign: 'welcome',
  amount: '5.00',
  currency: AccountCurrency.cny,
  grantedAt: '2026-10-01T00:00:00Z',
  expiresAt: '2026-11-01T00:00:00Z',
  message: 'A 5.00 CNY bonus was credited.',
);

const AccountBonusBatch _batch = AccountBonusBatch(
  accountId: 'user-7',
  bonuses: <AccountBonusGrant>[_grant],
);

_FakeAccountRepository _repository({
  Future<AccountState> Function()? readState,
  AccountProfileResult? profile = const AccountProfileReady(_profile),
  AccountBalanceResult? balance = _balance,
  AccountBonusBatch? bonuses = _batch,
  bool ackResult = true,
}) => _FakeAccountRepository(
  readState: readState ?? () async => _signedIn,
  profile: profile,
  balance: balance,
  bonuses: bonuses,
  ackResult: ackResult,
);

Future<void> _pump(
  WidgetTester tester,
  _FakeAccountRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider(_backendId).overrideWithValue(repository),
        settingsBackendScopeProvider.overrideWith(_FixedScope.new),
      ],
      child: l10nApp(home: const SettingsAccountPage()),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SettingsAccountPage)))!;

void main() {
  testWidgets('renders the host facts and acknowledges the shown bonus', (
    tester,
  ) async {
    final repository = _repository();

    await _pump(tester, repository);

    final AppLocalizations l10n = _l10n(tester);
    // The signed-in identity: the profile name with its own facts beside it.
    expect(find.text('Ada'), findsOneWidget);
    expect(
      find.text('a***@example.com · ${l10n.accountProfileId('user-7')}'),
      findsOneWidget,
    );
    // Both wallets, printed from the server's own decimal strings.
    expect(find.text(l10n.accountBalance), findsOneWidget);
    expect(find.text('¥12.34'), findsOneWidget);
    expect(find.text(l10n.accountBonusBalance), findsOneWidget);
    expect(find.text(r'$0.50'), findsOneWidget);
    // The unseen bonus: server-authored copy plus the grant window.
    expect(find.text(l10n.accountUnseenBonus), findsOneWidget);
    expect(find.text(l10n.accountBonusTitle), findsOneWidget);
    expect(find.text(_grant.message), findsOneWidget);
    expect(find.text('¥5.00'), findsOneWidget);
    expect(
      find.text(l10n.accountBonusWindow(_grant.grantedAt, _grant.expiresAt)),
      findsOneWidget,
    );
    // The acknowledgement names the account and the order it was read for,
    // and it carries the build's version and the active language.
    expect(repository.acks, <(String, String)>[('user-7', 'order-1')]);
    expect(repository.identities, isNotEmpty);
    expect(repository.identities.first.version, kDshAppVersion);
    expect(repository.identities.first.locale, startsWith('en'));
  });

  testWidgets('closing the notice acknowledges it and hides the card', (
    tester,
  ) async {
    final repository = _repository();

    await _pump(tester, repository);
    expect(repository.acks, hasLength(1));

    await tester.tap(find.text(_l10n(tester).accountBonusAck));
    await tester.pumpAndSettle();

    expect(find.text(_grant.message), findsNothing);
    // Closing counts as seeing it, and the order was already acknowledged once.
    expect(repository.acks, hasLength(1));
  });

  testWidgets('an acknowledgement that does not land offers the retry', (
    tester,
  ) async {
    final repository = _repository(ackResult: false);

    await _pump(tester, repository);
    final AppLocalizations l10n = _l10n(tester);
    expect(find.text(l10n.accountBonusAckFailed), findsOneWidget);

    repository.ackResult = true;
    await tester.tap(find.text(l10n.accountBonusAckRetry));
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountBonusAckFailed), findsNothing);
    expect(repository.acks, hasLength(2));
  });

  testWidgets('a deployment without the account service states it', (
    tester,
  ) async {
    await _pump(
      tester,
      _repository(
        readState: () => throw const RepositoryFailure(
          'gateway/invocation-unavailable',
          'no account service',
        ),
      ),
    );

    final AppLocalizations l10n = _l10n(tester);
    expect(find.text(l10n.accountUnavailable), findsOneWidget);
    expect(find.text(l10n.accountUnavailableBody), findsOneWidget);
    expect(find.text(l10n.accountBalance), findsNothing);
  });

  testWidgets('a host with no credential reads no profile or balance', (
    tester,
  ) async {
    final repository = _repository(
      readState: () async => const AccountState(
        status: AccountSignInStatus.signedOut,
        links: AccountLinks(
          usageUrl: 'https://platform.example/usage',
          topUpUrl: 'https://platform.example/top_up',
        ),
        attempt: null,
      ),
    );

    await _pump(tester, repository);

    final AppLocalizations l10n = _l10n(tester);
    expect(find.text(l10n.accountSignedOut), findsOneWidget);
    expect(find.text(l10n.accountSignedOutBody), findsOneWidget);
    expect(repository.profileReads, 0);
    expect(repository.balanceReads, 0);
    expect(repository.bonusReads, 0);
  });

  testWidgets('a failed balance read is stated, never rendered as zero', (
    tester,
  ) async {
    await _pump(
      tester,
      _repository(balance: const AccountBalanceFailed(), bonuses: null),
    );

    final AppLocalizations l10n = _l10n(tester);
    expect(find.text(l10n.accountBalanceUnavailable), findsNWidgets(2));
    expect(find.text(l10n.accountBonusAbsent), findsOneWidget);
    expect(find.textContaining('0.00'), findsNothing);
  });
}
