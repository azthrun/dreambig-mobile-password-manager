import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/generator/password_strength_estimator.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/app/providers.dart';

/// Live strength meter (GOALS_v2 §1.2, item 3), reused both by the
/// generator screen (post-generation) and the vault item form (as the user
/// types a manual password) — "shown at generation and entry time" per the
/// requirement.
///
/// Renders nothing while [password] is empty or the estimator's backing
/// wordlist asset is still loading, so it never flashes an empty/loading
/// bar during normal use.
class PasswordStrengthIndicator extends ConsumerWidget {
  const PasswordStrengthIndicator({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (password.isEmpty) return const SizedBox.shrink();
    final estimatorAsync = ref.watch(passwordStrengthEstimatorProvider);
    return estimatorAsync.when(
      data: (estimator) => _buildIndicator(context, estimator),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildIndicator(BuildContext context, PasswordStrengthEstimator estimator) {
    final l10n = AppLocalizations.of(context);
    final result = estimator.estimate(password);
    final scoreIndex = result.score.index;
    final fraction = (scoreIndex + 1) / PasswordStrengthScore.values.length;
    final color = _colorFor(result.score);
    final label = _labelFor(l10n, result.score);

    // The colored bar is a purely visual reinforcement of the text label
    // right below it — strength is never conveyed by color alone, and the
    // label text already says everything the bar would ("Strength: Weak").
    // Grouping just {bar, label} under one excludeSemantics Semantics node
    // means a screen reader announces the single clean "Strength: Weak"
    // string once, instead of a bare "N% progress bar" *and then* hearing
    // "Weak" again as the label Text's own separate node (double
    // announcement). The note and common-password-warning texts below carry
    // information the label doesn't, so they're deliberately left outside
    // this group as normal, independently announced Text nodes.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: l10n.generatorStrengthLabel(label),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    key: const Key('passwordStrengthBar'),
                    value: fraction,
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.generatorStrengthLabel(label),
                  key: const Key('passwordStrengthLabel'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            l10n.generatorStrengthEstimateNote,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          if (result.isKnownCommonPassword)
            Text(
              l10n.generatorStrengthCommonPasswordWarning,
              key: const Key('passwordStrengthCommonWarning'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  Color _colorFor(PasswordStrengthScore score) {
    switch (score) {
      case PasswordStrengthScore.veryWeak:
        return Colors.red;
      case PasswordStrengthScore.weak:
        return Colors.deepOrange;
      case PasswordStrengthScore.fair:
        return Colors.amber.shade800;
      case PasswordStrengthScore.strong:
        return Colors.lightGreen.shade700;
      case PasswordStrengthScore.veryStrong:
        return Colors.green.shade700;
    }
  }

  String _labelFor(AppLocalizations l10n, PasswordStrengthScore score) {
    switch (score) {
      case PasswordStrengthScore.veryWeak:
        return l10n.generatorStrengthVeryWeak;
      case PasswordStrengthScore.weak:
        return l10n.generatorStrengthWeak;
      case PasswordStrengthScore.fair:
        return l10n.generatorStrengthFair;
      case PasswordStrengthScore.strong:
        return l10n.generatorStrengthStrong;
      case PasswordStrengthScore.veryStrong:
        return l10n.generatorStrengthVeryStrong;
    }
  }
}
