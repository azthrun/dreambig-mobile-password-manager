import 'dart:math' as math;

/// 0 (very weak) .. 4 (very strong), mirroring zxcvbn's score scale for
/// familiarity, though this is *not* zxcvbn — see [PasswordStrengthEstimator]
/// doc comment.
enum PasswordStrengthScore { veryWeak, weak, fair, strong, veryStrong }

class PasswordStrengthResult {
  const PasswordStrengthResult({
    required this.score,
    required this.estimatedBits,
    required this.isKnownCommonPassword,
  });

  final PasswordStrengthScore score;

  /// A rough entropy estimate in bits, after pattern-based penalties. Not
  /// a rigorous information-theoretic measure — see class doc comment.
  final double estimatedBits;

  /// True if the password (or a close variant, e.g. with trailing digits
  /// stripped) matched the bundled common-password list.
  final bool isKnownCommonPassword;
}

/// Heuristic password strength estimator (GOALS_v2 §1.2, item 3).
///
/// **This is not a port of zxcvbn.** A full zxcvbn implementation depends on
/// large frequency-ranked dictionaries (English words, names, common
/// passwords) and pattern-matching machinery (l33t-speak substitution,
/// keyboard-adjacency graphs, date detection, etc.) that aren't reasonably
/// embeddable in this app without a much larger asset bundle and a
/// significant porting effort. Instead this is a documented, clearly-labeled
/// *estimate*:
///
///  1. Reject outright (score 0) if the password matches the bundled
///     common-password list (`assets/wordlists/common_passwords.txt`,
///     curated from a well-known leaked-password corpus), including a
///     cheap variant check that strips trailing digits/punctuation (catches
///     `password1`, `password!`, etc.).
///  2. Otherwise, estimate entropy as `length * log2(character pool size)`,
///     where the pool size is the sum of the character classes actually
///     present (lowercase/uppercase/digits/symbols) — the same model
///     NIST SP 800-63B's guidance and most non-zxcvbn strength meters use.
///  3. Apply penalties for low-entropy *patterns* that a naive pool-size
///     calculation overcounts: long runs of a repeated character (`aaaa`),
///     monotonic sequences (`abcd`, `1234`), and common keyboard-walk
///     substrings (`qwerty`, `asdf`, ...).
///  4. Map the penalized bit estimate to a 0-4 score using thresholds
///     loosely modeled on zxcvbn's guidance (crack-time buckets), for a
///     familiar UI (weak/fair/good/strong meter).
///
/// Called both after generation and live as the user types in the vault
/// item form's secret field, per GOALS_v2 §1.2 ("shown at generation and
/// entry time").
class PasswordStrengthEstimator {
  PasswordStrengthEstimator({required Set<String> commonPasswords})
    : _commonPasswords = commonPasswords.map((p) => p.toLowerCase()).toSet();

  final Set<String> _commonPasswords;

  static const List<String> _keyboardWalks = <String>[
    'qwerty',
    'qwertyuiop',
    'asdf',
    'asdfgh',
    'zxcv',
    'zxcvbn',
    '1qaz',
    'qazwsx',
  ];

  PasswordStrengthResult estimate(String password) {
    if (password.isEmpty) {
      return const PasswordStrengthResult(
        score: PasswordStrengthScore.veryWeak,
        estimatedBits: 0,
        isKnownCommonPassword: false,
      );
    }

    final isCommon = _matchesCommonPassword(password);
    if (isCommon) {
      return const PasswordStrengthResult(
        score: PasswordStrengthScore.veryWeak,
        estimatedBits: 0,
        isKnownCommonPassword: true,
      );
    }

    final poolSize = _poolSize(password);
    final rawBits = poolSize > 1
        ? password.length * (math.log(poolSize) / math.ln2)
        : 0.0;
    final penalty = _patternPenalty(password);
    final bits = math.max(0.0, rawBits - penalty);

    return PasswordStrengthResult(
      score: _scoreFromBits(bits),
      estimatedBits: bits,
      isKnownCommonPassword: false,
    );
  }

  bool _matchesCommonPassword(String password) {
    final lower = password.toLowerCase();
    if (_commonPasswords.contains(lower)) return true;
    // Strip trailing digits/punctuation (e.g. "password1", "password!") and
    // re-check — a very common weak-password pattern that a strict
    // equality check would miss.
    final stripped = lower.replaceAll(RegExp(r'[0-9!@#$%^&*.]+$'), '');
    if (stripped != lower && _commonPasswords.contains(stripped)) return true;
    return false;
  }

  int _poolSize(String password) {
    var size = 0;
    if (password.contains(RegExp('[a-z]'))) size += 26;
    if (password.contains(RegExp('[A-Z]'))) size += 26;
    if (password.contains(RegExp('[0-9]'))) size += 10;
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) size += 33;
    return size;
  }

  /// Bit penalty for low-entropy substrings the naive pool-size formula
  /// overcounts. Deliberately conservative/simple, not exhaustive.
  double _patternPenalty(String password) {
    double penalty = 0;
    final lower = password.toLowerCase();

    // Repeated-character runs, e.g. "aaaa", "1111" — each run beyond length
    // 2 barely adds entropy.
    final repeatMatches = RegExp(r'(.)\1{2,}').allMatches(password);
    for (final m in repeatMatches) {
      penalty += (m.end - m.start) * 3.5;
    }

    // Monotonic ascending/descending runs of 4+ characters, e.g. "abcd",
    // "4321".
    var run = 1;
    for (var i = 1; i < lower.length; i++) {
      final diff = lower.codeUnitAt(i) - lower.codeUnitAt(i - 1);
      if (diff == 1 || diff == -1) {
        run++;
      } else {
        if (run >= 4) penalty += run * 3.0;
        run = 1;
      }
    }
    if (run >= 4) penalty += run * 3.0;

    // Common keyboard-walk substrings.
    for (final walk in _keyboardWalks) {
      if (lower.contains(walk)) penalty += walk.length * 3.0;
    }

    return penalty;
  }

  PasswordStrengthScore _scoreFromBits(double bits) {
    if (bits < 28) return PasswordStrengthScore.veryWeak;
    if (bits < 36) return PasswordStrengthScore.weak;
    if (bits < 60) return PasswordStrengthScore.fair;
    if (bits < 80) return PasswordStrengthScore.strong;
    return PasswordStrengthScore.veryStrong;
  }
}
