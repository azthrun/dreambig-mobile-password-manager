import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/certificate_pinning_config.dart';
import 'package:password_manager/data/api/encrypted_envelope.dart';
import 'package:password_manager/domain/models/auth_session.dart';
import 'package:password_manager/domain/models/registered_device.dart';
import 'package:password_manager/domain/models/vault_item_summary.dart';

/// Documented **seam** for a future real, HTTPS-backed [ApiClient]
/// implementation. Deliberately not a working implementation — there is no
/// real backend for this repo to talk to yet (see
/// IMPLEMENTATION_PLAN.md's backend note and GOALS_v2 §1.5). Building a real
/// HTTP client against nothing would be premature and untestable.
///
/// This class exists so the *shape* of that future work is unambiguous:
///
/// - Every method signature already matches [ApiClient] exactly (Dart's
///   `implements` enforces this at compile time), so swapping
///   `apiClientProvider` in `lib/presentation/app/providers.dart` from
///   `FakeApiClient` to `HttpApiClient` is the entire migration — no call
///   site anywhere else in the app changes.
/// - Vault payloads already arrive here as [EncryptedEnvelope]
///   (`payload.toWireJson()`), ready to drop directly onto an HTTPS request
///   body — see that class's doc comment.
/// - [_pinningConfig] shows where [CertificatePinningConfig] would be
///   threaded into whatever HTTP client library is chosen (e.g. `dio` with
///   `dio_certificate_pinning`, or `http`'s [SecurityContext] /
///   [HttpClient.badCertificateCallback]) — see that class's doc comment
///   for why its pins are placeholders, not real values, right now.
///
/// When a real backend exists, replace every `throw UnimplementedError`
/// below with the actual HTTPS call (auth header injection, JSON
/// (de)serialization, error-code-to-exception mapping, retry/backoff, etc.)
/// — none of that can be written meaningfully against a backend that
/// doesn't exist, which is why it isn't attempted here.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    required Uri baseUrl,
    CertificatePinningConfig? pinningConfig,
  }) : _baseUrl = baseUrl,
       _pinningConfig = pinningConfig ?? CertificatePinningConfig.placeholder;

  // ignore: unused_field
  final Uri _baseUrl;

  // ignore: unused_field
  final CertificatePinningConfig _pinningConfig;

  Never _notImplemented(String method) {
    throw UnimplementedError(
      'HttpApiClient.$method: no real backend exists yet for this repo '
      '(see IMPLEMENTATION_PLAN.md). This is a documented seam, not a '
      'working implementation — use FakeApiClient until a real backend is '
      'specified.',
    );
  }

  @override
  Future<AuthSession> signUp({
    required String email,
    required String authKey,
  }) => _notImplemented('signUp');

  @override
  Future<void> confirmEmail({
    required String email,
    required String confirmationCode,
  }) => _notImplemented('confirmEmail');

  @override
  Future<AuthSession> signIn({
    required String email,
    required String authKey,
    required String deviceId,
  }) => _notImplemented('signIn');

  @override
  Future<void> signOut({required String accessToken}) =>
      _notImplemented('signOut');

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) =>
      _notImplemented('refreshSession');

  @override
  Future<RegisteredDevice> registerDevice({
    required String accessToken,
    required String deviceId,
    required String publicKey,
    required String deviceName,
  }) => _notImplemented('registerDevice');

  @override
  Future<List<RegisteredDevice>> listDevices({required String accessToken}) =>
      _notImplemented('listDevices');

  @override
  Future<void> approveDevice({
    required String accessToken,
    required String deviceId,
  }) => _notImplemented('approveDevice');

  @override
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) => _notImplemented('revokeDevice');

  @override
  Future<List<VaultItemSummary>> fetchVaultItemSummaries({
    required String accessToken,
  }) => _notImplemented('fetchVaultItemSummaries');

  @override
  Future<VaultItemSummary> pushVaultItem({
    required String accessToken,
    required String itemId,
    required EncryptedEnvelope payload,
    required String? expectedETag,
  }) => _notImplemented('pushVaultItem');

  @override
  Future<void> deleteAccount({required String accessToken}) =>
      _notImplemented('deleteAccount');
}
