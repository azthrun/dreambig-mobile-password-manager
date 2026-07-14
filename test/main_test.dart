// Unit test for `main.dart`'s launch-decision logic (GOALS_v2 §2.6): the
// root/jailbreak gate must be consulted before the real app is ever built,
// and blocking must yield the dedicated CompromisedDeviceApp with no way to
// fall through to the real app. `resolveLaunchWidget` is split out of
// `main()` specifically so this can be tested without calling `runApp`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/security/device_integrity_gate.dart';
import 'package:password_manager/data/security/root_detection_service.dart';
import 'package:password_manager/main.dart';
import 'package:password_manager/presentation/app/app.dart';
import 'package:password_manager/presentation/security/compromised_device_screen.dart';

class _FakeRootDetectionService implements RootDetectionService {
  _FakeRootDetectionService(this._compromised);
  final bool _compromised;

  @override
  Future<bool> isDeviceCompromised() async => _compromised;
}

void main() {
  test(
    'resolveLaunchWidget returns the real app when the integrity gate does '
    'not block launch',
    () async {
      final gate = DeviceIntegrityGate(
        detector: _FakeRootDetectionService(true),
        // Debug-mode override always short-circuits to "not blocked",
        // regardless of the (in this case compromised) detector result —
        // mirrors how a real debug build behaves.
        debugModeOverride: true,
      );

      final widget = await resolveLaunchWidget(gate: gate);

      expect(widget, isA<ProviderScope>());
      expect(
        (widget as ProviderScope).child,
        isA<PasswordManagerApp>(),
      );
    },
  );

  test(
    'resolveLaunchWidget returns CompromisedDeviceApp, never the real app, '
    'when the integrity gate blocks launch',
    () async {
      final gate = DeviceIntegrityGate(
        detector: _FakeRootDetectionService(true),
        debugModeOverride: false,
      );

      final widget = await resolveLaunchWidget(gate: gate);

      expect(widget, isA<CompromisedDeviceApp>());
    },
  );

  test(
    'resolveLaunchWidget returns the real app on a release-shaped build '
    'whose detector finds no compromise',
    () async {
      final gate = DeviceIntegrityGate(
        detector: _FakeRootDetectionService(false),
        debugModeOverride: false,
      );

      final widget = await resolveLaunchWidget(gate: gate);

      expect(widget, isA<ProviderScope>());
    },
  );
}
