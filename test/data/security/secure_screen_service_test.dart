// Unit tests for `SecureScreenService` (GOALS_v2 §2.5). Uses
// `FakeSecureScreenChannel` rather than a real platform channel — the real
// one has no Android host to answer it in this test sandbox and would hang
// rather than fail fast (see `SecureScreenChannel`'s doc comment in
// lib/data/security/secure_screen_service.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/security/secure_screen_service.dart';

void main() {
  group('SecureScreenService', () {
    test('setSecure(true) delegates to the channel with enabled=true', () async {
      final channel = FakeSecureScreenChannel();
      final service = SecureScreenService(channel: channel);

      await service.setSecure(true);

      expect(channel.lastSecureValue, true);
      expect(channel.calls, <bool>[true]);
    });

    test('setSecure(false) delegates to the channel with enabled=false', () async {
      final channel = FakeSecureScreenChannel();
      final service = SecureScreenService(channel: channel);

      await service.setSecure(true);
      await service.setSecure(false);

      expect(channel.lastSecureValue, false);
      expect(channel.calls, <bool>[true, false]);
    });
  });
}
