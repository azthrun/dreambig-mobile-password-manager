// Unit tests for AutofillBridgeService's method channel contract
// (GOALS_v2 §1.8): simulates the native side invoking `getSuggestions`
// through the `password_manager/autofill` channel and checks the response
// shape and the register/unregister lifecycle, without any real Android
// host — this test drives the channel exactly the way
// `TestDefaultBinaryMessengerBinding` is meant to be used for testing a
// `setMethodCallHandler`-based service from the Dart side.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/autofill/autofill_bridge_service.dart';
import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/autofill/autofill_matcher.dart';
import 'package:password_manager/domain/models/credential_data.dart';

const MethodCodec _codec = StandardMethodCodec();

Future<Object?> _invokeFromNative(String method, Map<String, Object?>? args) async {
  final envelope = _codec.encodeMethodCall(MethodCall(method, args));
  ByteData? response;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(AutofillBridgeService.channelName, envelope, (
        reply,
      ) {
        response = reply;
      });
  if (response == null) return null;
  return _codec.decodeEnvelope(response!);
}

Uint8List _testVaultKey() =>
    Uint8List.fromList(List<int>.generate(32, (i) => i));

Future<VaultRepository> _repoWithOneMatch() async {
  final repo = LocalVaultRepository(
    userId: 'user-1',
    vaultKey: _testVaultKey(),
    store: InMemoryVaultLocalStore(),
  );
  await repo.createCredential(
    const CredentialData(
      identifier: 'alice@example.com',
      secret: 'hunter2',
      siteName: 'Example',
      url: 'https://example.com',
    ),
  );
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Leave no handler registered between tests, mirroring
    // `AutoLockWrapper` unregistering on lock/sign-out.
    const MethodChannel(
      AutofillBridgeService.channelName,
    ).setMethodCallHandler(null);
  });

  test(
    'getSuggestions returns matching items as maps once registered',
    () async {
      final repo = await _repoWithOneMatch();
      final service = AutofillBridgeService();
      service.register(AutofillMatcher(repo));

      final result = await _invokeFromNative('getSuggestions', {
        'packageName': null,
        'webDomain': 'example.com',
      });

      expect(result, isA<List<Object?>>());
      final list = (result as List<Object?>).cast<Map<Object?, Object?>>();
      expect(list, hasLength(1));
      expect(list.single['identifier'], 'alice@example.com');
      expect(list.single['secret'], 'hunter2');
      expect(list.single['siteName'], 'Example');
    },
  );

  test('getSuggestions returns an empty list when nothing matches', () async {
    final repo = await _repoWithOneMatch();
    final service = AutofillBridgeService();
    service.register(AutofillMatcher(repo));

    final result = await _invokeFromNative('getSuggestions', {
      'packageName': null,
      'webDomain': 'unrelated.com',
    });

    expect(result, isA<List<Object?>>());
    expect(result as List<Object?>, isEmpty);
  });

  test('unregister leaves no handler answering native calls', () async {
    final repo = await _repoWithOneMatch();
    final service = AutofillBridgeService();
    service.register(AutofillMatcher(repo));
    service.unregister();

    // With no handler registered, the framework's message dispatch simply
    // yields no reply — the same "no plugin implementation" shape a
    // native caller sees before any Dart session has ever registered a
    // handler (see `AutofillBridge.kt`'s doc comment: this is exactly the
    // signal it treats as "fall back to the unlock suggestion").
    final result = await _invokeFromNative('getSuggestions', {
      'webDomain': 'example.com',
    });

    expect(result, isNull);
  });

  test(
    'an unknown method call is swallowed as a MissingPluginException '
    '(no reply), not answered with a bogus result',
    () async {
      final repo = await _repoWithOneMatch();
      final service = AutofillBridgeService();
      service.register(AutofillMatcher(repo));

      final result = await _invokeFromNative('someOtherMethod', const {});

      expect(result, isNull);
    },
  );
}
