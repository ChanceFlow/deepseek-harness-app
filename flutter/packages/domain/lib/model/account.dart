/// Account facts the host reports: credential presence, the Platform
/// profile, wallet balances, and granted bonuses the Platform has not yet
/// recorded as displayed.
///
/// Every type mirrors one projection of the pinned account service
/// (`reference/deepseek-harness/packages/credentials/deepseek-account/src/
/// types.ts` — `AccountView`, `AccountDetails`, `AccountBonusBatch`), never a
/// Platform wire shape: the host already sanitized profile fields and
/// localized the bonus copy, so nothing here carries a credential.
///
/// Absence is absence. A host with no stored account grant answers `null`
/// for a profile, balance, or bonus read, and this layer keeps that as null
/// rather than an empty wallet list or a zero balance — a surface then says
/// the host reports no account instead of inventing facts.
library;

/// Whether the host holds an account credential.
///
/// The value is not a claim that the server validated the credential; the
/// host's own projection says exactly this much.
enum AccountSignInStatus { signedOut, credentialStored }

/// Browser destinations the host derives from its Platform configuration.
///
/// They never carry a token: the host mints them from the configured origin.
final class AccountLinks {
  const AccountLinks({required this.usageUrl, required this.topUpUrl});

  /// The Platform usage page.
  final String usageUrl;

  /// The Platform top-up page.
  final String topUpUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountLinks &&
          other.usageUrl == usageUrl &&
          other.topUpUrl == topUpUrl);

  @override
  int get hashCode => Object.hash(usageUrl, topUpUrl);
}

/// Phase of the host's latest local sign-in attempt.
enum AccountSignInPhase {
  initializing,
  waitingBrowser,
  exchanging,
  committing,
  succeeded,
  cancelled,
  expired,
  failed,
}

/// The host's latest sign-in attempt, including terminal outcomes until the
/// next attempt starts.
final class AccountSignInAttempt {
  const AccountSignInAttempt({
    required this.id,
    required this.phase,
    this.authorizeUrl,
    this.expiresAt,
    this.errorCode,
  });

  /// Identity of one local attempt, unrelated to any Platform request id.
  final String id;

  final AccountSignInPhase phase;

  /// The authorization page the host offers while an attempt waits on the
  /// browser; absent in other phases.
  final String? authorizeUrl;

  /// Milliseconds since the epoch at which the attempt expires; absent while
  /// the host has not scheduled an expiry.
  final int? expiresAt;

  /// The host's safe failure code (`network`, `protocol`, `expired`,
  /// `storage`); absent unless the attempt failed.
  final String? errorCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountSignInAttempt &&
          other.id == id &&
          other.phase == phase &&
          other.authorizeUrl == authorizeUrl &&
          other.expiresAt == expiresAt &&
          other.errorCode == errorCode);

  @override
  int get hashCode =>
      Object.hash(id, phase, authorizeUrl, expiresAt, errorCode);
}

/// The host's safe account projection (`account/getState`).
final class AccountState {
  const AccountState({
    required this.status,
    required this.links,
    required this.attempt,
  });

  final AccountSignInStatus status;

  final AccountLinks links;

  /// The latest attempt, or null when the host holds none.
  final AccountSignInAttempt? attempt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountState &&
          other.status == status &&
          other.links == links &&
          other.attempt == attempt);

  @override
  int get hashCode => Object.hash(status, links, attempt);
}

/// Display identity the Platform supplied; fields stay masked exactly as the
/// host projected them.
final class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.name,
    required this.contact,
    this.avatarUrl,
  });

  /// Platform account id, or null when the endpoint returned none.
  final String? id;

  /// Display name, or null when Platform configured none.
  final String? name;

  /// Masked contact (mobile, then email), or null when Platform exposed
  /// neither.
  final String? contact;

  /// Profile image URL, or null when none is configured.
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountProfile &&
          other.id == id &&
          other.name == name &&
          other.contact == contact &&
          other.avatarUrl == avatarUrl);

  @override
  int get hashCode => Object.hash(id, name, contact, avatarUrl);
}

/// The currencies the Platform wallet reports.
enum AccountCurrency { cny, usd }

/// One recharge or bonus wallet; the amount is a decimal string the Platform
/// authored.
final class AccountWallet {
  const AccountWallet({required this.currency, required this.balance});

  final AccountCurrency currency;

  /// Decimal amount as the Platform wrote it. Kept verbatim: re-rounding it
  /// on the phone would report a number the account does not hold.
  final String balance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountWallet &&
          other.currency == currency &&
          other.balance == balance);

  @override
  int get hashCode => Object.hash(currency, balance);
}

/// Outcome of one profile read (`account/getProfile`); a null repository
/// answer is the host having no account grant at all, which is neither of
/// these.
sealed class AccountProfileResult {
  const AccountProfileResult();
}

/// The host answered a profile.
final class AccountProfileReady extends AccountProfileResult {
  const AccountProfileReady(this.profile);

  final AccountProfile profile;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountProfileReady && other.profile == profile);

  @override
  int get hashCode => profile.hashCode;
}

/// The host could not read the profile. A failure is not a zero or an empty
/// profile, and the page says so instead of rendering placeholders.
final class AccountProfileFailed extends AccountProfileResult {
  const AccountProfileFailed();

  @override
  bool operator ==(Object other) => other is AccountProfileFailed;

  @override
  int get hashCode => 0;
}

/// Outcome of one balance read (`account/getBalance`); a null repository
/// answer is the host having no account grant at all.
sealed class AccountBalanceResult {
  const AccountBalanceResult();
}

/// The host answered the recharge and granted wallets separately, so a
/// surface renders them as the two facts they are.
final class AccountBalanceReady extends AccountBalanceResult {
  const AccountBalanceReady({
    required this.wallets,
    required this.bonusWallets,
  });

  /// Recharge wallet balances, in Platform order.
  final List<AccountWallet> wallets;

  /// Granted (bonus) wallet balances, in Platform order.
  final List<AccountWallet> bonusWallets;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountBalanceReady &&
          _listEquals(other.wallets, wallets) &&
          _listEquals(other.bonusWallets, bonusWallets));

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(wallets), Object.hashAll(bonusWallets));
}

/// The host could not read the balance. Never rendered as zero.
final class AccountBalanceFailed extends AccountBalanceResult {
  const AccountBalanceFailed();

  @override
  bool operator ==(Object other) => other is AccountBalanceFailed;

  @override
  int get hashCode => 0;
}

/// One granted bonus the Platform has not recorded as displayed.
final class AccountBonusGrant {
  const AccountBonusGrant({
    required this.orderId,
    required this.campaign,
    required this.amount,
    required this.currency,
    required this.grantedAt,
    required this.expiresAt,
    required this.message,
  });

  /// Stable bonus order identity, shared across devices and sign-ins.
  final String orderId;

  final String campaign;

  /// Granted decimal amount, preserving Platform precision; this is the
  /// grant, never the remaining balance.
  final String amount;

  final AccountCurrency currency;

  /// Grant time as Platform supplied it.
  final String grantedAt;

  /// Expiry as Platform supplied it.
  final String expiresAt;

  /// Server-authored plain text, already localized for the requesting UI.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountBonusGrant &&
          other.orderId == orderId &&
          other.campaign == campaign &&
          other.amount == amount &&
          other.currency == currency &&
          other.grantedAt == grantedAt &&
          other.expiresAt == expiresAt &&
          other.message == message);

  @override
  int get hashCode => Object.hash(
    orderId,
    campaign,
    amount,
    currency,
    grantedAt,
    expiresAt,
    message,
  );
}

/// Unnotified bonuses with the account they belong to, in Platform order.
final class AccountBonusBatch {
  const AccountBonusBatch({required this.accountId, required this.bonuses});

  /// The account every grant in [bonuses] belongs to; the acknowledgement
  /// names it so a grant is never recorded against another account.
  final String accountId;

  final List<AccountBonusGrant> bonuses;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountBonusBatch &&
          other.accountId == accountId &&
          _listEquals(other.bonuses, bonuses));

  @override
  int get hashCode => Object.hash(accountId, Object.hashAll(bonuses));
}

/// Identity of the requesting UI for one account call.
///
/// The host turns these three fields into the Platform request headers, so
/// the caller supplies the UI facts only it knows — the build's version and
/// the active language — and never a credential.
final class AccountClientIdentity {
  const AccountClientIdentity({
    required this.version,
    required this.locale,
    required this.timezoneOffsetSeconds,
  });

  /// Client build version.
  final String version;

  /// Active UI language; the host reduces it to the Platform wire locale.
  final String locale;

  /// Offset from UTC in seconds, positive east of Greenwich — the sign
  /// `DateTime.timeZoneOffset` already reports.
  final int timezoneOffsetSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountClientIdentity &&
          other.version == version &&
          other.locale == locale &&
          other.timezoneOffsetSeconds == timezoneOffsetSeconds);

  @override
  int get hashCode => Object.hash(version, locale, timezoneOffsetSeconds);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
