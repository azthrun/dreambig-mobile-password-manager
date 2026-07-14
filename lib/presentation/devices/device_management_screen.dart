import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/models/device_status.dart';
import 'package:password_manager/domain/models/registered_device.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/devices/device_management_controller.dart';

/// Device management screen (GOALS_v2 §1.4): lists every device registered
/// to the signed-in account and lets the user approve a pending device or
/// revoke any device (including this one, or a lost/stolen one).
///
/// Single-device testing limitation: exercising the "new-device
/// authorization by an already-trusted device" flow for real requires a
/// second physical device. The [_SimulateDeviceButton] stands in for that
/// second device by registering a throwaway pending entry through the same
/// `ApiClient.registerDevice` call a genuine second install would make —
/// see `DeviceManagementController.simulateNewDeviceRegistration`'s doc
/// comment.
class DeviceManagementScreen extends ConsumerWidget {
  const DeviceManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devicesAsync = ref.watch(deviceManagementControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deviceManagementTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('deviceSimulateNewDeviceButton'),
            icon: const Icon(Icons.add_to_home_screen),
            tooltip: l10n.deviceSimulateNewDeviceButton,
            onPressed: () => ref
                .read(deviceManagementControllerProvider.notifier)
                .simulateNewDeviceRegistration(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.deviceSimulateNewDeviceNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: devicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  Center(child: Text(l10n.genericErrorLabel)),
              data: (devices) {
                if (devices.isEmpty) {
                  return Center(child: Text(l10n.deviceManagementEmptyState));
                }
                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return _DeviceTile(device: device, l10n: l10n);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device, required this.l10n});

  final RegisteredDevice device;
  final AppLocalizations l10n;

  String _statusLabel() {
    switch (device.status) {
      case DeviceStatus.active:
        return l10n.deviceStatusActive;
      case DeviceStatus.pending:
        return l10n.deviceStatusPending;
      case DeviceStatus.revoked:
        return l10n.deviceStatusRevoked;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(deviceManagementControllerProvider.notifier);
    return ListTile(
      key: Key('deviceListItem-${device.deviceId}'),
      leading: const Icon(Icons.devices),
      title: Text(device.deviceName),
      subtitle: Text(
        '${_statusLabel()} • ${l10n.deviceRegisteredOn(device.registeredAt.toLocal().toString())}',
      ),
      trailing: Wrap(
        spacing: 8,
        children: <Widget>[
          if (device.status.isPending)
            TextButton(
              key: Key('deviceApproveButton-${device.deviceId}'),
              onPressed: () => controller.approve(device.deviceId),
              child: Text(l10n.deviceApproveButton),
            ),
          if (!device.status.isRevoked)
            TextButton(
              key: Key('deviceRevokeButton-${device.deviceId}'),
              onPressed: () => controller.revoke(device.deviceId),
              child: Text(l10n.deviceRevokeButton),
            ),
        ],
      ),
    );
  }
}
