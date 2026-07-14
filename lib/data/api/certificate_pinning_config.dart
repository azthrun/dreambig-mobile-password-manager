/// Configuration scaffold for certificate pinning (GOALS_v2 §1.5).
///
/// **This is not a working pin-validation implementation.** There is no real
/// backend/HTTPS endpoint in this repo yet (see IMPLEMENTATION_PLAN.md's
/// backend note), so there is nothing real to pin against. This class only
/// documents the shape a real configuration would take and where it would
/// be consumed, so wiring in a real backend later is a matter of:
///
/// 1. Filling in [pinnedSha256Spki] with the real backend's leaf/intermediate
///    certificate SPKI (Subject Public Key Info) SHA-256 hashes — obtained
///    out-of-band from whoever operates the backend, *not* invented here.
/// 2. Passing this config into a real HTTP client (e.g. `dio` +
///    `dio_certificate_pinning`, or `http`'s [SecurityContext] /
///    a custom [HttpClient.badCertificateCallback] that compares the
///    presented certificate's SPKI hash against [pinnedSha256Spki]) inside
///    `HttpApiClient` (see that class's doc comment for the seam).
/// 3. Deciding a rotation/backup-pin strategy so a routine certificate
///    renewal on the backend doesn't hard-lock out every installed client —
///    typically by pinning both the current and the next intermediate CA,
///    or pinning the CA rather than the leaf.
///
/// The placeholder values below are **not real pins** — they are
/// intentionally obviously-fake (see the `PLACEHOLDER_` prefix) so nobody
/// mistakes this scaffold for a working configuration and ships it as-is.
class CertificatePinningConfig {
  const CertificatePinningConfig({
    required this.host,
    required this.pinnedSha256Spki,
    this.includeSubdomains = false,
  });

  /// The backend host this pin set applies to, e.g. `api.example.com`.
  final String host;

  /// Base64 SHA-256 SPKI pins, in the same `sha256/<base64>` format used by
  /// HPKP/most mobile pinning libraries. At least two entries are expected
  /// in a real config (current cert + backup) to survive routine rotation.
  final List<String> pinnedSha256Spki;

  final bool includeSubdomains;

  /// Clearly-marked placeholder scaffold — **do not use in production**.
  /// Replace [host] and [pinnedSha256Spki] with real values sourced from the
  /// backend operator once a real backend exists, before wiring this into
  /// `HttpApiClient`.
  static const CertificatePinningConfig placeholder = CertificatePinningConfig(
    host: 'PLACEHOLDER_HOST.example.invalid',
    pinnedSha256Spki: <String>[
      'sha256/PLACEHOLDER_PIN_NOT_A_REAL_CERTIFICATE_HASH_1=',
      'sha256/PLACEHOLDER_PIN_NOT_A_REAL_CERTIFICATE_HASH_2=',
    ],
  );
}
