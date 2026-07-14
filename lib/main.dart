import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/data/security/device_integrity_gate.dart';
import 'package:password_manager/data/security/root_detection_service.dart';
import 'package:password_manager/presentation/app/app.dart';
import 'package:password_manager/presentation/security/compromised_device_screen.dart';

/// Decides which root widget to launch (GOALS_v2 §2.6): the real app, or the
/// blocking [CompromisedDeviceApp] if [DeviceIntegrityGate] flags this
/// install as compromised. Split out from [main] so the decision itself is
/// independently testable without ever calling `runApp`.
Future<Widget> resolveLaunchWidget({DeviceIntegrityGate? gate}) async {
  final integrityGate =
      gate ?? DeviceIntegrityGate(detector: DeviceRootDetectionService());
  final blocked = await integrityGate.shouldBlockLaunch();
  if (blocked) {
    return const CompromisedDeviceApp();
  }
  return const ProviderScope(child: PasswordManagerApp());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final widget = await resolveLaunchWidget();
  runApp(widget);
}
