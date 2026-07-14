import 'package:local_auth/local_auth.dart';

/// Abstraction over platform biometrics.
///
/// Per GOALS_v2 §1.3, biometric unlock is an *additional, local*
/// convenience only: it gates access to a vault key that's already been
/// derived and is already sitting in secure storage. It must never become
/// an alternate root of key derivation.
abstract class BiometricAuthenticator {
  Future<bool> isAvailable();

  Future<bool> authenticate({required String reason});
}

/// [local_auth]-backed implementation used by the running app.
class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator([LocalAuthentication? localAuth])
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> isAvailable() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// In-memory fake for tests.
class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({
    this.available = true,
    this.shouldSucceed = true,
  });

  bool available;
  bool shouldSucceed;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => shouldSucceed;
}
