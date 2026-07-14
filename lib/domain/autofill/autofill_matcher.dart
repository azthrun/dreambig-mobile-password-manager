import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/models/vault_item.dart';

/// Matches vault items against an autofill request's target — an Android
/// app's package name and/or the web domain of the page being filled —
/// per GOALS_v2 §1.8.
///
/// **Own-items-only scoping**: this deliberately takes a [VaultRepository]
/// rather than any lower-level store. `VaultRepository.listActive()` is
/// already scoped to a single signed-in account's non-trashed items (see
/// that class's doc comment, and Phase 7's reviewer note that this is the
/// pattern Phase 8 should reuse) — routing every autofill suggestion
/// through it is what gives autofill the same "own items only" guarantee
/// as the rest of the vault UI (GOALS_v2 §1.8, mirroring §1.1). There is
/// no path from this matcher to another account's data or to trashed
/// items, because there's no path to them through [VaultRepository]
/// itself.
///
/// This class is deliberately pure Dart with no platform-channel
/// dependency, so it's fully unit-testable regardless of the surrounding
/// native Android autofill plumbing (`AutofillBridgeService`,
/// `PasswordManagerAutofillService.kt`) being impossible to exercise in
/// this sandbox.
class AutofillMatcher {
  const AutofillMatcher(this._repository);

  final VaultRepository _repository;

  /// Returns the subset of the signed-in account's active vault items that
  /// match [webDomain] (compared against [CredentialData.url]'s host) or
  /// loosely match [packageName] (see [_looksLikePackageMatch]).
  ///
  /// Returns an empty list — never "match everything" — if both
  /// [packageName] and [webDomain] are null/blank, and equally returns an
  /// empty list if there's simply nothing in the vault that matches; a
  /// request with no identifiable target, or no matching item, should
  /// surface no suggestions.
  Future<List<VaultItem>> findMatches({
    String? packageName,
    String? webDomain,
  }) async {
    final normalizedDomain = _normalizeHost(webDomain);
    final normalizedPackage = _normalizePackage(packageName);
    if (normalizedDomain == null && normalizedPackage == null) {
      return const <VaultItem>[];
    }

    final items = await _repository.listActive();
    return items.where((item) {
      final data = item.data;
      if (normalizedDomain != null) {
        final itemHost = _normalizeHost(data.url);
        if (itemHost != null && _hostsMatch(itemHost, normalizedDomain)) {
          return true;
        }
      }
      if (normalizedPackage != null &&
          _looksLikePackageMatch(normalizedPackage, data.siteName, data.url)) {
        return true;
      }
      return false;
    }).toList();
  }

  static String? _normalizePackage(String? packageName) {
    if (packageName == null) return null;
    final trimmed = packageName.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Extracts and lower-cases the host from a vault item's stored URL (or a
  /// requesting web domain), stripping a leading `www.` so
  /// `https://www.example.com/login` and `example.com` compare equal.
  /// Returns null if [url] is blank or has no parseable host.
  static String? _normalizeHost(String? url) {
    if (url == null) return null;
    final trimmed = url.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final host = Uri.tryParse(withScheme)?.host ?? '';
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// Exact host match, or either side being a subdomain of the other (e.g.
  /// a saved `accounts.example.com` item should still surface for a
  /// top-level `example.com` autofill request and vice versa).
  static bool _hostsMatch(String a, String b) {
    if (a == b) return true;
    return a.endsWith('.$b') || b.endsWith('.$a');
  }

  /// **Heuristic, not a verified match.** Real Android autofill
  /// app-to-website association is normally backed by Digital Asset Links
  /// (a server-hosted `assetlinks.json` proving an app and a domain belong
  /// to the same developer); standing that up requires server-side surface
  /// this app doesn't have yet, so this instead does a best-effort textual
  /// comparison — do any of the package name's reverse-DNS segments
  /// (longer than 3 characters, to skip generic segments like
  /// `com`/`app`/`org`/`co`) appear in the item's site name or URL. This
  /// can both under-match (a legitimate app whose package name doesn't
  /// resemble the site name) and over-match (an unrelated app/site sharing
  /// a common word) — documented here as a Phase 1 limitation rather than
  /// silently pretending to be a verified association.
  static bool _looksLikePackageMatch(
    String packageName,
    String siteName,
    String url,
  ) {
    final segments = packageName
        .split('.')
        .where((segment) => segment.length > 3)
        .toList();
    if (segments.isEmpty) return false;
    final haystack = '${siteName.toLowerCase()} ${url.toLowerCase()}';
    return segments.any(haystack.contains);
  }
}
