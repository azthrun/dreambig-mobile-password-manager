import 'package:password_manager/domain/models/device_status.dart';

/// A device that has registered an asymmetric keypair with the backend for
/// end-to-end encryption purposes (GOALS_v2 §1.4).
///
/// Only [publicKey] ever leaves the device; the matching private key stays
/// in platform secure storage (`DeviceKeyStore`) and never appears on this
/// model or anywhere else that could reach `ApiClient`.
class RegisteredDevice {
  const RegisteredDevice({
    required this.deviceId,
    required this.publicKey,
    required this.deviceName,
    required this.status,
    required this.registeredAt,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String publicKey;

  /// Human-readable label shown in the device management screen (e.g.
  /// "Android device") — never used for access control.
  final String deviceName;

  final DeviceStatus status;
  final DateTime registeredAt;
  final DateTime lastSeenAt;

  RegisteredDevice copyWith({DeviceStatus? status, DateTime? lastSeenAt}) {
    return RegisteredDevice(
      deviceId: deviceId,
      publicKey: publicKey,
      deviceName: deviceName,
      status: status ?? this.status,
      registeredAt: registeredAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
