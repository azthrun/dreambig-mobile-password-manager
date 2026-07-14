import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/domain/generator/password_generator.dart';
import 'package:password_manager/domain/generator/password_generator_options.dart';

void main() {
  group('PasswordGenerator', () {
    test('generates a password of the requested length', () {
      final generator = PasswordGenerator();
      for (final length in <int>[1, 4, 8, 16, 32, 64]) {
        final password = generator.generate(
          PasswordGeneratorOptions(length: length),
        );
        expect(password.length, length);
      }
    });

    test('only uses characters from the enabled character sets', () {
      final generator = PasswordGenerator();
      const digitsOnly = PasswordGeneratorOptions(
        length: 200,
        useUppercase: false,
        useLowercase: false,
        useDigits: true,
        useSymbols: false,
      );
      final password = generator.generate(digitsOnly);
      expect(RegExp(r'^[0-9]+$').hasMatch(password), isTrue);
    });

    test('lowercase-only pool never contains uppercase/digits/symbols', () {
      final generator = PasswordGenerator();
      const lowerOnly = PasswordGeneratorOptions(
        length: 200,
        useUppercase: false,
        useLowercase: true,
        useDigits: false,
        useSymbols: false,
      );
      final password = generator.generate(lowerOnly);
      expect(RegExp(r'^[a-z]+$').hasMatch(password), isTrue);
    });

    test('long generation includes a character from every enabled set', () {
      final generator = PasswordGenerator();
      const options = PasswordGeneratorOptions(length: 32);
      final password = generator.generate(options);
      expect(password.contains(RegExp('[A-Z]')), isTrue);
      expect(password.contains(RegExp('[a-z]')), isTrue);
      expect(password.contains(RegExp('[0-9]')), isTrue);
      expect(password.contains(RegExp(r'[^a-zA-Z0-9]')), isTrue);
    });

    test('excludeAmbiguous strips 0/O/1/l/I from the result', () {
      final generator = PasswordGenerator();
      const options = PasswordGeneratorOptions(
        length: 500,
        useSymbols: false,
        excludeAmbiguous: true,
      );
      final password = generator.generate(options);
      for (final ambiguous in <String>['0', 'O', '1', 'l', 'I']) {
        expect(password.contains(ambiguous), isFalse);
      }
    });

    test('throws when no character set is enabled', () {
      final generator = PasswordGenerator();
      const options = PasswordGeneratorOptions(
        useUppercase: false,
        useLowercase: false,
        useDigits: false,
        useSymbols: false,
      );
      expect(
        () => generator.generate(options),
        throwsA(isA<PasswordGeneratorException>()),
      );
    });

    test('throws for non-positive length', () {
      final generator = PasswordGenerator();
      expect(
        () => generator.generate(const PasswordGeneratorOptions(length: 0)),
        throwsA(isA<PasswordGeneratorException>()),
      );
    });

    test(
      'statistical sanity: repeated calls are not identical (secure RNG)',
      () {
        final generator = PasswordGenerator();
        const options = PasswordGeneratorOptions(length: 20);
        final results = List<String>.generate(
          50,
          (_) => generator.generate(options),
        );
        // A cryptographically random 20-char password colliding twice in
        // 50 draws is astronomically unlikely; if it happens, the RNG is
        // broken (e.g. accidentally deterministic).
        expect(results.toSet().length, results.length);
      },
    );

    test('supports a caller-supplied RNG (deterministic for testing)', () {
      // Two generators seeded... Random.secure() can't be seeded, but a
      // caller can still substitute any Random implementation via the
      // constructor — verify that seam works by using the default
      // unseeded Random with a fixed seed and checking two instances with
      // the *same* seed produce the same output.
      final generatorA = PasswordGenerator(random: _seededRandom(42));
      final generatorB = PasswordGenerator(random: _seededRandom(42));
      const options = PasswordGeneratorOptions(length: 24);
      expect(
        generatorA.generate(options),
        generatorB.generate(options),
      );
    });
  });
}

// dart:math's Random(seed) is deterministic, unlike Random.secure() — used
// only to test the caller-supplied-RNG seam above.
Random _seededRandom(int seed) => Random(seed);
