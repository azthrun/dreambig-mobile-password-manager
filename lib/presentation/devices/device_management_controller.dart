import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/models/registered_device.dart';
import 'package:password_manager/l10n/generated/app_localizations_en.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// Drives the device management screen (GOALS_v2 §1.4): lists every device
/// registered to the signed-in account (active/pending/revoked) and exposes
/// approve/revoke actions against [apiClientProvider].
class DeviceManagementController extends AsyncNotifier<List<RegisteredDevice>> {
  String? get _accessToken => ref.read(authControllerProvider).accessToken;

  @override
  Future<List<RegisteredDevice>> build() async {
    final token = _accessToken;
    if (token == null) return const <RegisteredDevice>[];
    return ref.read(apiClientProvider).listDevices(accessToken: token);
  }

  Future<void> refresh() async {
    final token = _accessToken;
    if (token == null) {
      state = const AsyncValue<List<RegisteredDevice>>.data(
        <RegisteredDevice>[],
      );
      return;
    }
    state = await AsyncValue.guard(
      () => ref.read(apiClientProvider).listDevices(accessToken: token),
    );
  }

  /// Approves a pending device — the "new-device authorization by an
  /// already-trusted device" flow (GOALS_v2 §1.4). Only reachable from a
  /// session that is itself already signed in/active, matching
  /// `ApiClient.approveDevice`'s contract.
  Future<void> approve(String deviceId) async {
    final token = _accessToken;
    if (token == null) return;
    await ref.read(apiClientProvider).approveDevice(
      accessToken: token,
      deviceId: deviceId,
    );
    await refresh();
  }

  Future<void> revoke(String deviceId) async {
    final token = _accessToken;
    if (token == null) return;
    await ref.read(apiClientProvider).revokeDevice(
      accessToken: token,
      deviceId: deviceId,
    );
    await refresh();
  }

  /// Registers a second, ephemeral device identity under the same account
  /// so the pending-approval flow can be exercised end-to-end.
  ///
  /// **Single-device testing limitation**: this app cannot run on two
  /// physical devices within one test/demo session, so there is no real
  /// second install to register here. This method stands in for that
  /// second install by generating a throwaway device id/public key and
  /// calling the exact same `ApiClient.registerDevice` a real second
  /// install would call — it lands `pending` exactly like a genuine new
  /// device would, so `approve`/`revoke` above can be exercised against a
  /// realistic pending entry. It never touches this install's own device
  /// identity/keypair (`DeviceIdentityService`) and does not fabricate a
  /// private key anywhere.
  Future<void> simulateNewDeviceRegistration() async {
    final token = _accessToken;
    if (token == null) return;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    await ref.read(apiClientProvider).registerDevice(
      accessToken: token,
      deviceId: 'device-simulated-$suffix',
      publicKey: 'simulated-public-key-$suffix',
      deviceName: AppLocalizationsEn().deviceSimulatedDeviceName,
    );
    await refresh();
  }
}

final AsyncNotifierProvider<DeviceManagementController, List<RegisteredDevice>>
deviceManagementControllerProvider =
    AsyncNotifierProvider<
      DeviceManagementController,
      List<RegisteredDevice>
    >(DeviceManagementController.new);
