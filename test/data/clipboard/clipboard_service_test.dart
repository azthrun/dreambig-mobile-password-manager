// Unit tests for clipboard auto-clear hygiene (GOALS_v2 §2.4).
//
// Uses `InMemoryClipboardAdapter` rather than the real `Clipboard` platform
// channel: the real channel forwards to the host OS pasteboard and never
// responds in this project's test sandbox, hanging indefinitely instead of
// failing — see `ClipboardAdapter`'s doc comment in
// lib/data/clipboard/clipboard_service.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/clipboard/clipboard_service.dart';

void main() {
  group('ClipboardService', () {
    test('copySecret writes the value to the clipboard immediately', () async {
      final adapter = InMemoryClipboardAdapter();
      final service = ClipboardService(
        adapter: adapter,
        clearAfter: const Duration(seconds: 10),
      );
      addTearDown(service.dispose);

      await service.copySecret('hunter2');

      expect(await adapter.getText(), 'hunter2');
    });

    test('auto-clears the clipboard after the configured timeout', () async {
      final adapter = InMemoryClipboardAdapter();
      final service = ClipboardService(
        adapter: adapter,
        clearAfter: const Duration(milliseconds: 20),
      );
      addTearDown(service.dispose);

      await service.copySecret('hunter2');
      expect(await adapter.getText(), 'hunter2');

      // Wait past the timeout for the clear timer to fire.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(await adapter.getText(), '');
    });

    test(
      'does not clobber a different value the user copied in the meantime',
      () async {
        final adapter = InMemoryClipboardAdapter();
        final service = ClipboardService(
          adapter: adapter,
          clearAfter: const Duration(milliseconds: 20),
        );
        addTearDown(service.dispose);

        await service.copySecret('hunter2');
        // Simulate the user copying something else before the timeout
        // fires — the service should never have any way to distinguish
        // this from "still holds what we copied" except by re-reading the
        // clipboard, which is exactly what it does.
        await adapter.setText('some other clipboard content');

        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(await adapter.getText(), 'some other clipboard content');
      },
    );

    test(
      'clearNowIfHoldingSecret clears immediately without waiting for the timeout',
      () async {
        final adapter = InMemoryClipboardAdapter();
        final service = ClipboardService(
          adapter: adapter,
          clearAfter: const Duration(minutes: 5),
        );
        addTearDown(service.dispose);

        await service.copySecret('hunter2');
        await service.clearNowIfHoldingSecret();

        expect(await adapter.getText(), '');
      },
    );

    test(
      'clearNowIfHoldingSecret does not clobber a different clipboard value',
      () async {
        final adapter = InMemoryClipboardAdapter();
        final service = ClipboardService(
          adapter: adapter,
          clearAfter: const Duration(minutes: 5),
        );
        addTearDown(service.dispose);

        await service.copySecret('hunter2');
        await adapter.setText('unrelated value');
        await service.clearNowIfHoldingSecret();

        expect(await adapter.getText(), 'unrelated value');
      },
    );

    test(
      'a second copySecret call resets the timer relative to the new value',
      () async {
        final adapter = InMemoryClipboardAdapter();
        final service = ClipboardService(
          adapter: adapter,
          clearAfter: const Duration(milliseconds: 60),
        );
        addTearDown(service.dispose);

        await service.copySecret('first');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await service.copySecret('second');

        // Only 30ms have elapsed since the second copy — well under its
        // own 60ms timeout — so it should still be present.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(await adapter.getText(), 'second');

        // Now let the second value's own timeout elapse.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(await adapter.getText(), '');
      },
    );
  });
}
