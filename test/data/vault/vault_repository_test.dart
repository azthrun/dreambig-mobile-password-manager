// Unit tests for LocalVaultRepository: CRUD, soft-delete/trash window,
// revision history, and own-account-only scoping (GOALS_v2 §1.1).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/models/credential_data.dart';

Uint8List _testVaultKey([int seed = 1]) {
  return Uint8List.fromList(List<int>.generate(32, (i) => (i + seed) % 256));
}

LocalVaultRepository _repoFor(
  String userId, {
  VaultLocalStore? store,
  DateTime Function()? now,
  Uint8List? vaultKey,
}) {
  return LocalVaultRepository(
    userId: userId,
    vaultKey: vaultKey ?? _testVaultKey(),
    store: store ?? InMemoryVaultLocalStore(),
    now: now,
  );
}

const CredentialData _sampleData = CredentialData(
  identifier: 'alice@example.com',
  secret: 'hunter2',
  siteName: 'Example',
  url: 'https://example.com',
  notes: 'note',
  tags: <String>['work'],
);

void main() {
  group('CRUD', () {
    test('createCredential persists and is retrievable', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);

      expect(created.id, isNotEmpty);
      expect(created.eTag, isNotEmpty);
      expect(created.data.identifier, 'alice@example.com');
      expect(created.data.secret, 'hunter2');

      final fetched = await repo.getById(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.data.secret, 'hunter2');
      expect(fetched.data.tags, <String>['work']);
    });

    test('listActive returns created items, newest-updated first', () async {
      var tick = 0;
      final repo = _repoFor(
        'user-1',
        now: () => DateTime(2026, 1, 1).add(Duration(minutes: tick++)),
      );
      final first = await repo.createCredential(
        _sampleData.copyWith(identifier: 'first'),
      );
      final second = await repo.createCredential(
        _sampleData.copyWith(identifier: 'second'),
      );

      final active = await repo.listActive();
      expect(active.map((i) => i.id).toList(), <String>[second.id, first.id]);
    });

    test('updateCredential overwrites data and bumps eTag', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      final updated = await repo.updateCredential(
        created.id,
        _sampleData.copyWith(secret: 'new-secret'),
      );

      expect(updated.eTag, isNot(created.eTag));
      expect(updated.data.secret, 'new-secret');

      final fetched = await repo.getById(created.id);
      expect(fetched!.data.secret, 'new-secret');
    });

    test('data persisted across repository instances sharing a store', () async {
      final store = InMemoryVaultLocalStore();
      final repo1 = _repoFor('user-1', store: store);
      final created = await repo1.createCredential(_sampleData);

      final repo2 = _repoFor('user-1', store: store);
      final fetched = await repo2.getById(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.data.identifier, _sampleData.identifier);
    });
  });

  group('Soft delete + trash window', () {
    test('softDelete removes item from active list and adds it to trash', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);

      await repo.softDelete(created.id);

      final active = await repo.listActive();
      expect(active, isEmpty);

      final trash = await repo.listTrash();
      expect(trash.map((i) => i.id), contains(created.id));
      expect(trash.single.isTrashed, isTrue);
    });

    test('restore within the recovery window brings the item back to active', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      await repo.softDelete(created.id);

      final restored = await repo.restore(created.id);
      expect(restored, isNotNull);
      expect(restored!.isTrashed, isFalse);

      final active = await repo.listActive();
      expect(active.map((i) => i.id), contains(created.id));
      final trash = await repo.listTrash();
      expect(trash, isEmpty);
    });

    test('item older than 30 days is excluded from trash and cannot be restored', () async {
      final deletedAt = DateTime(2026, 1, 1);
      var current = deletedAt;
      final repo = _repoFor('user-1', now: () => current);

      final created = await repo.createCredential(_sampleData);
      current = deletedAt;
      await repo.softDelete(created.id);

      // Still within window.
      current = deletedAt.add(const Duration(days: 29));
      expect((await repo.listTrash()).map((i) => i.id), contains(created.id));

      // Past the 30-day recovery window.
      current = deletedAt.add(const Duration(days: 31));
      final trash = await repo.listTrash();
      expect(trash, isEmpty);

      final restoreResult = await repo.restore(created.id);
      expect(restoreResult, isNull);
    });

    test('item at exactly the 30-day boundary is still purgeable-excluded (inclusive edge)', () async {
      final deletedAt = DateTime(2026, 1, 1);
      var current = deletedAt;
      final repo = _repoFor('user-1', now: () => current);

      final created = await repo.createCredential(_sampleData);
      current = deletedAt;
      await repo.softDelete(created.id);

      // Exactly 30 days later: difference == retention, not strictly greater
      // than it, so isPurgeable is false and the item must still be
      // recoverable (isPurgeable uses a strict `>` comparison).
      current = deletedAt.add(const Duration(days: 30));
      final trash = await repo.listTrash();
      expect(trash.map((i) => i.id), contains(created.id));

      final restoreResult = await repo.restore(created.id);
      expect(restoreResult, isNotNull);
    });

    test('restore returns null for an item that was never deleted', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      final result = await repo.restore(created.id);
      expect(result, isNull);
    });
  });

  group('Revision history', () {
    test('update captures the prior version as a revision', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      final firstETag = created.eTag;

      final updated = await repo.updateCredential(
        created.id,
        _sampleData.copyWith(secret: 'second-secret'),
      );

      expect(updated.revisions, hasLength(1));
      expect(updated.revisions.first.eTag, firstETag);
      expect(updated.revisions.first.data.secret, 'hunter2');
    });

    test('multiple updates accumulate revisions, most-recent-first', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      await repo.updateCredential(
        created.id,
        _sampleData.copyWith(secret: 'v2'),
      );
      final v3 = await repo.updateCredential(
        created.id,
        _sampleData.copyWith(secret: 'v3'),
      );

      expect(v3.revisions, hasLength(2));
      expect(v3.revisions[0].data.secret, 'v2');
      expect(v3.revisions[1].data.secret, 'hunter2');
    });

    test('restoreRevision reverts to a prior version and preserves history', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      final v2 = await repo.updateCredential(
        created.id,
        _sampleData.copyWith(secret: 'v2'),
      );
      final firstRevisionETag = v2.revisions.single.eTag; // the v1 snapshot

      final restored = await repo.restoreRevision(created.id, firstRevisionETag);
      expect(restored, isNotNull);
      expect(restored!.data.secret, 'hunter2');
      // The overwritten v2 is now itself preserved as a revision.
      expect(
        restored.revisions.map((r) => r.data.secret),
        contains('v2'),
      );
    });

    test('restoreRevision returns null for an unknown eTag', () async {
      final repo = _repoFor('user-1');
      final created = await repo.createCredential(_sampleData);
      final result = await repo.restoreRevision(created.id, 'nonexistent');
      expect(result, isNull);
    });
  });

  group('Own-account-only scoping', () {
    test('a repository for one user never sees another user\'s items', () async {
      final store = InMemoryVaultLocalStore();
      final repoA = _repoFor('user-a', store: store);
      final repoB = _repoFor('user-b', store: store);

      final itemA = await repoA.createCredential(
        _sampleData.copyWith(identifier: 'a-item'),
      );
      await repoB.createCredential(_sampleData.copyWith(identifier: 'b-item'));

      final activeA = await repoA.listActive();
      final activeB = await repoB.listActive();

      expect(activeA.map((i) => i.data.identifier), <String>['a-item']);
      expect(activeB.map((i) => i.data.identifier), <String>['b-item']);

      // Cross-account lookup by id must fail even though the store is shared.
      expect(await repoB.getById(itemA.id), isNull);
    });

    test('records with a mismatched userId embedded are ignored defensively', () async {
      final store = InMemoryVaultLocalStore();
      final repoA = _repoFor('user-a', store: store);
      await repoA.createCredential(_sampleData);

      // Simulate a corrupted/misrouted record ending up filed under
      // 'user-a' but claiming to belong to 'user-b'.
      final cipher = await repoA.getById((await repoA.listActive()).single.id);
      expect(cipher, isNotNull);

      final tampered = StoredVaultItemRecord(
        id: 'tampered',
        userId: 'user-b',
        eTag: 'etag-x',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        payload: (await store.loadAll('user-a')).first.payload,
      );
      final existing = await store.loadAll('user-a');
      await store.saveAll('user-a', <StoredVaultItemRecord>[
        ...existing,
        tampered,
      ]);

      final repoAAgain = _repoFor('user-a', store: store);
      final active = await repoAAgain.listActive();
      expect(active.map((i) => i.id), isNot(contains('tampered')));
    });
  });
}
