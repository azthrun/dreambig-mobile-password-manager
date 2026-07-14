import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/presentation/app/providers.dart';

/// Shared "copy secret to clipboard" affordance for the vault item detail
/// screen and the generator screen (GOALS_v2 §2.4) — a single place that
/// wires `ClipboardService.copySecret` up to a button and a follow-up
/// snackbar warning the user the clipboard will auto-clear, so both call
/// sites get identical clipboard-hygiene behavior and messaging.
class CopyToClipboardButton extends ConsumerWidget {
  const CopyToClipboardButton({
    super.key,
    required this.value,
    required this.tooltip,
    required this.copiedMessage,
    this.icon = Icons.copy,
  });

  /// The secret value to copy — never logged, never exposed via any other
  /// side channel here.
  final String value;
  final String tooltip;
  final String copiedMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: value.isEmpty
          ? null
          : () async {
              await ref.read(clipboardServiceProvider).copySecret(value);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(copiedMessage)),
              );
            },
    );
  }
}
