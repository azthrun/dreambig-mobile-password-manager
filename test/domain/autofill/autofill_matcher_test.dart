// Unit tests for AutofillMatcher: URL/package-name matching heuristics and
// own-items-only scoping (GOALS_v2 §1.8), driven entirely through a fake
// VaultRepository so no platform channel or real storage is touched.

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/autofill/autofill_matcher.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/domain/models/vault_item_type.dart';

/// A minimal fake implementing the [VaultRepository] contract, so
/// [AutofillMatcher] can be tested purely against whatever [listActive]
/// exposes — mirroring `LocalVaultRepository.listActive()`'s "own,
/// non-trashed items only" contract without touching real storage or
/// encryption. The mutation methods are unused by [AutofillMatcher] and
/// deliberately throw if ever called, so a test would fail loudly if the
/// matcher started depending on anything beyond read access.
class FakeVaultRepository implements VaultRepository {
  FakeVaultRepository(this.items);

  final List<VaultItem> items;

  @override
  Future<List<VaultItem>> listActive() async => items;

  @override
  Future<List<VaultItem>> listTrash() =>
      throw UnimplementedError('AutofillMatcher must not call listTrash');

  @override
  Future<VaultItem?> getById(String id) =>
      throw UnimplementedError('AutofillMatcher must not call getById');

  @override
  Future<VaultItem> createCredential(CredentialData data) =>
      throw UnimplementedError();

  @override
  Future<VaultItem> updateCredential(String id, CredentialData data) =>
      throw UnimplementedError();

  @override
  Future<void> softDelete(String id) => throw UnimplementedError();

  @override
  Future<VaultItem?> restore(String id) => throw UnimplementedError();

  @override
  Future<VaultItem?> restoreRevision(String id, String revisionETag) =>
      throw UnimplementedError();
}

VaultItem _item({
  required String id,
  required String userId,
  String identifier = 'user@example.com',
  String secret = 'hunter2',
  String siteName = '',
  String url = '',
}) {
  final now = DateTime(2026, 1, 1);
  return VaultItem(
    id: id,
    userId: userId,
    type: VaultItemType.credential,
    eTag: 'etag-$id',
    createdAt: now,
    updatedAt: now,
    data: CredentialData(
      identifier: identifier,
      secret: secret,
      siteName: siteName,
      url: url,
    ),
  );
}

void main() {
  group('web domain matching', () {
    test('matches an item whose url has the same host', () async {
      final item = _item(
        id: '1',
        userId: 'u1',
        siteName: 'Example',
        url: 'https://example.com/login',
      );
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(webDomain: 'example.com');

      expect(matches, [item]);
    });

    test('matches ignoring scheme, path, and a leading www.', () async {
      final item = _item(
        id: '1',
        userId: 'u1',
        url: 'www.example.com',
      );
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(
        webDomain: 'https://www.example.com/path?x=1',
      );

      expect(matches, [item]);
    });

    test('matches a saved subdomain against a bare top-level request', () async {
      final item = _item(
        id: '1',
        userId: 'u1',
        url: 'https://accounts.example.com',
      );
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(webDomain: 'example.com');

      expect(matches, [item]);
    });

    test('matches a bare top-level saved item against a subdomain request', () async {
      final item = _item(id: '1', userId: 'u1', url: 'https://example.com');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(
        webDomain: 'login.example.com',
      );

      expect(matches, [item]);
    });

    test('does not match an unrelated domain', () async {
      final item = _item(id: '1', userId: 'u1', url: 'https://example.com');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(webDomain: 'other.com');

      expect(matches, isEmpty);
    });

    test('items with a blank url never match by domain', () async {
      final item = _item(id: '1', userId: 'u1', url: '');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(webDomain: 'example.com');

      expect(matches, isEmpty);
    });
  });

  group('package name matching', () {
    test('matches when a package segment appears in the site name', () async {
      final item = _item(id: '1', userId: 'u1', siteName: 'Example App');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(
        packageName: 'com.example.app',
      );

      expect(matches, [item]);
    });

    test('matches when a package segment appears in the url', () async {
      final item = _item(id: '1', userId: 'u1', url: 'https://example.com');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(
        packageName: 'com.example.androidapp',
      );

      expect(matches, [item]);
    });

    test('does not match an unrelated package', () async {
      final item = _item(id: '1', userId: 'u1', siteName: 'Example App');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(
        packageName: 'com.totallydifferent.thing',
      );

      expect(matches, isEmpty);
    });

    test('ignores short generic segments like "com"/"app"', () async {
      // Neither segment should independently trigger a match against a
      // site name that merely contains the word "app".
      final item = _item(id: '1', userId: 'u1', siteName: 'My App Notes');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(packageName: 'com.app.co');

      expect(matches, isEmpty);
    });
  });

  group('no target / no session', () {
    test('returns no matches when neither package nor domain is given', () async {
      final item = _item(id: '1', userId: 'u1', url: 'https://example.com');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches();

      expect(matches, isEmpty);
    });

    test('returns no matches when package/domain are blank strings', () async {
      final item = _item(id: '1', userId: 'u1', url: 'https://example.com');
      final matcher = AutofillMatcher(FakeVaultRepository([item]));

      final matches = await matcher.findMatches(
        packageName: '   ',
        webDomain: '',
      );

      expect(matches, isEmpty);
    });

    test('returns no matches when the vault has no active items', () async {
      final matcher = AutofillMatcher(FakeVaultRepository(const []));

      final matches = await matcher.findMatches(webDomain: 'example.com');

      expect(matches, isEmpty);
    });
  });

  group('own-items-only scoping', () {
    test(
      'only ever surfaces what the repository exposes via listActive '
      '(the same own-account/non-trashed scoping LocalVaultRepository '
      'enforces structurally) — this matcher never sees a userId to '
      'filter by, by design',
      () async {
        // The fake repository here stands in for a repository already
        // constructed scoped to one signed-in account (mirroring
        // `LocalVaultRepository`'s per-session construction) — so items
        // "belonging" to a different user simply never appear in what
        // listActive() returns, and this matcher has no way to reach them.
        final ownItem = _item(
          id: 'own-1',
          userId: 'user-1',
          url: 'https://example.com',
        );
        final matcher = AutofillMatcher(FakeVaultRepository([ownItem]));

        final matches = await matcher.findMatches(webDomain: 'example.com');

        expect(matches, [ownItem]);
        expect(matches.every((item) => item.userId == 'user-1'), isTrue);
      },
    );

    test('an empty listActive() (no session / vault locked) yields no matches', () async {
      final matcher = AutofillMatcher(FakeVaultRepository(const []));

      final matches = await matcher.findMatches(
        packageName: 'com.example.app',
        webDomain: 'example.com',
      );

      expect(matches, isEmpty);
    });
  });
}
