import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/auth/recovery_mode.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// Step 2 of sign-up: the explicit, up-front recovery-mode choice required
/// by GOALS_v2 §1.3 (decision #3) — shown *before* the account/vault is
/// created, with both options' consequences spelled out side-by-side so the
/// user makes an informed comparative choice, not a buried setting.
class RecoveryModeScreen extends ConsumerStatefulWidget {
  const RecoveryModeScreen({super.key});

  @override
  ConsumerState<RecoveryModeScreen> createState() =>
      _RecoveryModeScreenState();
}

class _RecoveryModeScreenState extends ConsumerState<RecoveryModeScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _choose(RecoveryMode mode) async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).completeSignUp(mode);
      // Router redirect (needsEmailConfirmation) takes it from here.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.authGenericError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoveryModeTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.recoveryModeIntro,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (_error != null) ...<Widget>[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 640;
                  final localCard = _RecoveryOptionCard(
                    key: const Key('recoveryModeLocalCard'),
                    title: l10n.recoveryModeLocalTitle,
                    description: l10n.recoveryModeLocalDescription,
                    buttonLabel: l10n.recoveryModeChooseLocalButton,
                    buttonKey: const Key('recoveryModeChooseLocalButton'),
                    onChoose: _submitting
                        ? null
                        : () => _choose(RecoveryMode.localOnly),
                  );
                  final remoteCard = _RecoveryOptionCard(
                    key: const Key('recoveryModeRemoteCard'),
                    title: l10n.recoveryModeRemoteTitle,
                    description: l10n.recoveryModeRemoteDescription,
                    buttonLabel: l10n.recoveryModeChooseRemoteButton,
                    buttonKey: const Key('recoveryModeChooseRemoteButton'),
                    onChoose: _submitting
                        ? null
                        : () => _choose(RecoveryMode.remoteBackup),
                  );
                  if (isWide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: localCard),
                          const SizedBox(width: 16),
                          Expanded(child: remoteCard),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: <Widget>[
                      localCard,
                      const SizedBox(height: 16),
                      remoteCard,
                    ],
                  );
                },
              ),
              if (_submitting) ...<Widget>[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryOptionCard extends StatelessWidget {
  const _RecoveryOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonKey,
    required this.onChoose,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final Key buttonKey;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            FilledButton(
              key: buttonKey,
              onPressed: onChoose,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
