import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Checks whether this install is running on a rooted (Android) or
/// jailbroken (iOS) device.
///
/// GOALS_v2 §2.6 requires root/jailbreak detection but explicitly gates
/// *whether it runs at all* by build type (see `DeviceIntegrityGate`) — this
/// class is only the detector, not the gate. It is deliberately hand-rolled
/// (known-indicator-file/path checks) rather than pulling in a third-party
/// package (e.g. `flutter_jailbreak_detection`, `safe_device`), consistent
/// with AGENTS.md's "avoid adding dependencies unless clearly justified":
/// this repo isn't shipping to a real device fleet yet, so a heuristic
/// file-presence check is enough to satisfy the requirement and exercise
/// the build-time gating around it; swapping in a more thorough package
/// later is a one-file change (this class stays behind
/// [RootDetectionService], so nothing else in the app depends on how the
/// check itself is implemented).
///
/// **This is a heuristic, not a guarantee.** Root/jailbreak detection is
/// fundamentally an arms race (magisk hide, etc. can defeat file-presence
/// checks) — it raises the bar, it doesn't make bypass impossible.
abstract class RootDetectionService {
  /// Returns true if the device shows signs of being rooted/jailbroken.
  Future<bool> isDeviceCompromised();
}

/// Real, file-presence-based implementation.
class DeviceRootDetectionService implements RootDetectionService {
  DeviceRootDetectionService({
    List<String>? androidIndicatorPaths,
    List<String>? iosIndicatorPaths,
    bool Function(String path)? pathExists,
    TargetPlatform? platform,
  }) : _androidIndicatorPaths =
           androidIndicatorPaths ?? _defaultAndroidIndicatorPaths,
       _iosIndicatorPaths = iosIndicatorPaths ?? _defaultIosIndicatorPaths,
       _pathExists = pathExists ?? _defaultPathExists,
       _platform = platform ?? defaultTargetPlatform;

  /// Well-known files/binaries that are present on rooted Android devices
  /// (su binaries, common root-manager APKs, Magisk) but not on stock,
  /// non-rooted installs.
  static const List<String> _defaultAndroidIndicatorPaths = <String>[
    '/system/app/Superuser.apk',
    '/sbin/su',
    '/system/bin/su',
    '/system/xbin/su',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/data/local/su',
    '/su/bin/su',
    '/system/xbin/busybox',
    '/data/adb/magisk',
  ];

  /// Well-known paths present on jailbroken iOS devices (Cydia and common
  /// jailbreak-tweak package managers/paths).
  static const List<String> _defaultIosIndicatorPaths = <String>[
    '/Applications/Cydia.app',
    '/Library/MobileSubstrate/MobileSubstrate.dylib',
    '/bin/bash',
    '/usr/sbin/sshd',
    '/etc/apt',
    '/private/var/lib/apt',
  ];

  final List<String> _androidIndicatorPaths;
  final List<String> _iosIndicatorPaths;
  final bool Function(String path) _pathExists;
  final TargetPlatform _platform;

  static bool _defaultPathExists(String path) {
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      // A filesystem read failing (e.g. sandboxing) is not itself evidence
      // of compromise — fail closed on "not detected" for this indicator
      // rather than throwing and crashing the check entirely.
      return false;
    }
  }

  @override
  Future<bool> isDeviceCompromised() async {
    final indicators = switch (_platform) {
      TargetPlatform.android => _androidIndicatorPaths,
      TargetPlatform.iOS => _iosIndicatorPaths,
      _ => const <String>[],
    };
    return indicators.any(_pathExists);
  }
}
