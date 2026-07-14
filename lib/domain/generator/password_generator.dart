import 'dart:math';

import 'package:password_manager/domain/generator/password_generator_options.dart';

/// Thrown when [PasswordGenerator.generate] is asked to build a password
/// with no usable character set (e.g. every toggle turned off, or
/// [PasswordGeneratorOptions.length] is not positive).
class PasswordGeneratorException implements Exception {
  const PasswordGeneratorException(this.message);
  final String message;

  @override
  String toString() => 'PasswordGeneratorException: $message';
}

/// Character-based password generator (GOALS_v2 §1.2, item 1).
///
/// Uses `dart:math`'s [Random.secure] — a cryptographically secure RNG
/// backed by the platform's CSPRNG — rather than the default [Random],
/// since generated output becomes a vault secret and must not be
/// predictable from, e.g., a leaked seed or a weak PRNG algorithm.
class PasswordGenerator {
  PasswordGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  // A conservative, broadly-typeable symbol set.
  static const String _symbols = r'!@#$%^&*()-_=+[]{};:,.?/';

  /// Characters considered visually ambiguous when
  /// [PasswordGeneratorOptions.excludeAmbiguous] is set: `0/O`, `1/l/I`.
  static const String _ambiguous = '0O1lI';

  /// Builds the pool of characters available under [options], with
  /// ambiguous characters stripped out if requested.
  String _buildPool(PasswordGeneratorOptions options) {
    final buffer = StringBuffer();
    if (options.useUppercase) buffer.write(_uppercase);
    if (options.useLowercase) buffer.write(_lowercase);
    if (options.useDigits) buffer.write(_digits);
    if (options.useSymbols) buffer.write(_symbols);
    var pool = buffer.toString();
    if (options.excludeAmbiguous) {
      pool = pool.split('').where((c) => !_ambiguous.contains(c)).join();
    }
    return pool;
  }

  /// Per-charset pools, used to guarantee at least one character from each
  /// enabled set is present in the result (common, expected UX for a
  /// password generator, and it avoids the (small but real) chance that a
  /// purely random draw omits an enabled set entirely).
  List<String> _enabledPools(PasswordGeneratorOptions options) {
    final pools = <String>[];
    void addIfEnabled(bool enabled, String set) {
      if (!enabled) return;
      final filtered = options.excludeAmbiguous
          ? set.split('').where((c) => !_ambiguous.contains(c)).join()
          : set;
      if (filtered.isNotEmpty) pools.add(filtered);
    }

    addIfEnabled(options.useUppercase, _uppercase);
    addIfEnabled(options.useLowercase, _lowercase);
    addIfEnabled(options.useDigits, _digits);
    addIfEnabled(options.useSymbols, _symbols);
    return pools;
  }

  /// Generates a password per [options].
  ///
  /// Throws [PasswordGeneratorException] if [options] has no enabled
  /// character set, the resulting pool is empty (e.g. all sets excluded via
  /// ambiguous-character filtering), or [PasswordGeneratorOptions.length]
  /// is not positive.
  String generate(PasswordGeneratorOptions options) {
    if (options.length <= 0) {
      throw const PasswordGeneratorException('Length must be positive.');
    }
    if (!options.hasAnyCharacterSet) {
      throw const PasswordGeneratorException(
        'At least one character set must be enabled.',
      );
    }
    final pool = _buildPool(options);
    if (pool.isEmpty) {
      throw const PasswordGeneratorException(
        'No characters available with the current options.',
      );
    }
    final enabledPools = _enabledPools(options);
    if (options.length < enabledPools.length) {
      // Not enough room to guarantee one of each enabled set; fall back to
      // pure random draws from the combined pool.
      return _randomDraw(pool, options.length);
    }

    // Guarantee at least one char from each enabled set, then fill the
    // remainder randomly from the combined pool, then shuffle so the
    // guaranteed characters aren't predictably placed at the front.
    final chars = <String>[
      for (final p in enabledPools) p[_random.nextInt(p.length)],
    ];
    while (chars.length < options.length) {
      chars.add(pool[_random.nextInt(pool.length)]);
    }
    _shuffle(chars);
    return chars.join();
  }

  String _randomDraw(String pool, int length) {
    return List<String>.generate(
      length,
      (_) => pool[_random.nextInt(pool.length)],
    ).join();
  }

  /// Fisher-Yates shuffle using the same secure RNG as generation.
  void _shuffle(List<String> chars) {
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
  }
}
