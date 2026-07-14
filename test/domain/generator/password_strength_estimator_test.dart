import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/domain/generator/password_strength_estimator.dart';

void main() {
  final estimator = PasswordStrengthEstimator(
    commonPasswords: <String>{'password', '123456', 'qwerty', 'letmein'},
  );

  group('PasswordStrengthEstimator', () {
    test('empty password scores very weak with zero bits', () {
      final result = estimator.estimate('');
      expect(result.score, PasswordStrengthScore.veryWeak);
      expect(result.estimatedBits, 0);
    });

    test('known common passwords score very weak and are flagged', () {
      for (final weak in <String>['password', 'PASSWORD', '123456', 'qwerty']) {
        final result = estimator.estimate(weak);
        expect(result.score, PasswordStrengthScore.veryWeak, reason: weak);
        expect(result.isKnownCommonPassword, isTrue, reason: weak);
      }
    });

    test('common password with trailing digits/punctuation still flagged', () {
      final result = estimator.estimate('password1');
      expect(result.isKnownCommonPassword, isTrue);
      expect(result.score, PasswordStrengthScore.veryWeak);
    });

    test('monotonicity: longer passwords of the same shape score no lower', () {
      final short = estimator.estimate('aB3\$aB3\$');
      final long = estimator.estimate('aB3\$aB3\$aB3\$aB3\$aB3\$');
      expect(long.estimatedBits, greaterThan(short.estimatedBits));
      expect(long.score.index, greaterThanOrEqualTo(short.score.index));
    });

    test(
      'monotonicity: more varied character classes score no lower than fewer, at equal length',
      () {
        final lowerOnly = estimator.estimate('abcdefghijklmnop');
        final mixed = estimator.estimate('aB3\$eF6^iJ9&mN0!');
        expect(mixed.estimatedBits, greaterThan(lowerOnly.estimatedBits));
        expect(mixed.score.index, greaterThanOrEqualTo(lowerOnly.score.index));
      },
    );

    test('a long, random-looking mixed-class password scores strong+', () {
      final result = estimator.estimate('xQ7\$mZ2#vT9@pL4!');
      expect(
        result.score.index,
        greaterThanOrEqualTo(PasswordStrengthScore.strong.index),
      );
    });

    test('repeated-character runs are penalized vs. non-repeating of same length', () {
      final repeated = estimator.estimate('aaaaaaaaaaaaaaaa');
      final varied = estimator.estimate('kx7#nq2\$wz9!bt4^');
      expect(varied.estimatedBits, greaterThan(repeated.estimatedBits));
    });

    test('sequential runs (abcd/1234) are penalized', () {
      final sequential = estimator.estimate('abcdefgh1234');
      final nonSequential = estimator.estimate('kx7bnq2twz9c');
      expect(nonSequential.estimatedBits, greaterThan(sequential.estimatedBits));
    });
  });
}
