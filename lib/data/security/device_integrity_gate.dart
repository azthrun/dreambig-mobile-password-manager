import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:password_manager/data/security/root_detection_service.dart';

/// Decides whether app launch should be blocked due to root/jailbreak
/// detection, per GOALS_v2 §2.6's decision: "required, gated by build-time
/// DEBUG/RELEASE attribute; skipped on DEBUG, always blocks with no
/// override on RELEASE".
///
/// **Why this is genuinely build-time, not a runtime-toggleable flag.**
/// [kDebugMode] is a `const bool` from `package:flutter/foundation.dart`
/// that the Dart compiler bakes in differently per build mode: `flutter run`
/// / debug builds compile it to `true`, while `flutter build --release`
/// compiles it to `false` — via tree-shaking, `kReleaseMode`/`kDebugMode`
/// branches are actually *removed* from a release binary at compile time,
/// not merely defaulted. There is no settings screen, remote config, or
/// environment variable in this app that can flip it in a shipped release
/// artifact; the only way to get `kDebugMode == true` is to build the app
/// in debug mode in the first place. [debugModeOverride] exists purely so
/// unit tests can exercise both branches of [shouldBlockLaunch] without
/// needing two separately-compiled test binaries — production code (see
/// `main.dart`) never passes it, so it always uses the real compiled-in
/// [kDebugMode].
class DeviceIntegrityGate {
  DeviceIntegrityGate({
    required RootDetectionService detector,
    bool? debugModeOverride,
  }) : _detector = detector,
       _isDebugBuild = debugModeOverride ?? kDebugMode;

  final RootDetectionService _detector;
  final bool _isDebugBuild;

  /// True if app usage should be blocked. On a debug build this returns
  /// `false` unconditionally without even running [RootDetectionService] —
  /// development/QA on rooted test devices and emulators must not be
  /// blocked. On a release build, the detector always runs and its result
  /// is authoritative with no bypass.
  Future<bool> shouldBlockLaunch() async {
    if (_isDebugBuild) return false;
    return _detector.isDeviceCompromised();
  }
}
