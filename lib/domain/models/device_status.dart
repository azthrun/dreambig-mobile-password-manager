/// Lifecycle status of a [RegisteredDevice] (GOALS_v2 §1.4).
///
/// A brand-new device registration lands as [pending] unless it is the
/// very first device registered for the account (nothing exists yet to
/// authorize it against, so it is auto-trusted). An already-[active]
/// device can promote a [pending] one to [active] via
/// `ApiClient.approveDevice` ("new-device authorization by an
/// already-trusted device"). [revoked] devices keep their history entry
/// (rather than being deleted) so the device management screen can still
/// show that a lost/stolen device was revoked.
enum DeviceStatus {
  pending,
  active,
  revoked;

  bool get isActive => this == DeviceStatus.active;
  bool get isPending => this == DeviceStatus.pending;
  bool get isRevoked => this == DeviceStatus.revoked;
}
