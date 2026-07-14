import 'dart:math';
import 'dart:typed_data';

import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/domain/crypto/vault_item_cipher.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/domain/models/vault_item_revision.dart';
import 'package:password_manager/domain/models/vault_item_type.dart';

/// CRUD + soft-delete/trash + revision-history operations over a single
/// signed-in account's vault items (GOALS_v2 §1.1).
///
/// Implementations are constructed scoped to one `userId`/vault key pair
/// (see `LocalVaultRepository`); there is deliberately no method that takes
/// a userId as a parameter, so a caller cannot accidentally cross-query
/// another account's data through this interface.
abstract class VaultRepository {
  /// Active (not soft-deleted) items, newest-updated first.
  Future<List<VaultItem>> listActive();

  /// Soft-deleted items still within the recovery window
  /// ([kVaultItemTrashRetention]), newest-deleted first.
  Future<List<VaultItem>> listTrash();

  Future<VaultItem?> getById(String id);

  Future<VaultItem> createCredential(CredentialData data);

  /// Overwrites [id]'s current data, snapshotting the prior version into
  /// [VaultItem.revisions] and issuing a new eTag.
  Future<VaultItem> updateCredential(String id, CredentialData data);

  /// Marks [id] as deleted with the current timestamp; it moves to trash
  /// rather than being removed immediately.
  Future<void> softDelete(String id);

  /// Restores a trashed item, provided it's still within the recovery
  /// window. Returns null if the item doesn't exist, isn't trashed, or has
  /// aged out of the window.
  Future<VaultItem?> restore(String id);

  /// Reverts [id]'s current data to a specific prior revision (identified
  /// by that revision's eTag), snapshotting the current data as a new
  /// revision first — so restoring is itself non-destructive.
  Future<VaultItem?> restoreRevision(String id, String revisionETag);
}

/// Local, encrypted-at-rest implementation backed by [VaultLocalStore] +
/// [VaultItemCipher].
///
/// Constructed per-session with a fixed [userId] and [vaultKey] pulled from
/// `AuthState` (never re-derived here) — see `vaultRepositoryProvider` in
/// `lib/presentation/app/providers.dart`.
class LocalVaultRepository implements VaultRepository {
  LocalVaultRepository({
    required this.userId,
    required Uint8List vaultKey,
    required VaultLocalStore store,
    VaultItemCipher? cipher,
    Random? random,
    DateTime Function()? now,
    // Kept as ordinary (not initializing-formal) params so callers use the
    // clearer public names `vaultKey`/`store` rather than the private
    // field names.
    // ignore: prefer_initializing_formals
  }) : _vaultKey = vaultKey,
       // ignore: prefer_initializing_formals
       _store = store,
       _cipher = cipher ?? VaultItemCipher(),
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  final String userId;
  final Uint8List _vaultKey;
  final VaultLocalStore _store;
  final VaultItemCipher _cipher;
  final Random _random;
  final DateTime Function() _now;

  String _newId(String prefix) =>
      '$prefix-${_now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<VaultItem> _decode(StoredVaultItemRecord record) async {
    final decrypted = await _cipher.decryptJson(_vaultKey, record.payload);
    final decoded = VaultItem.payloadFromJson(decrypted);
    return VaultItem(
      id: record.id,
      userId: record.userId,
      type: decoded.type,
      eTag: record.eTag,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      data: decoded.data,
      revisions: decoded.revisions,
    );
  }

  Future<StoredVaultItemRecord> _encode(VaultItem item) async {
    final payload = await _cipher.encryptJson(
      _vaultKey,
      item.toEncryptablePayload(),
    );
    return StoredVaultItemRecord(
      id: item.id,
      userId: item.userId,
      eTag: item.eTag,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      deletedAt: item.deletedAt,
      payload: payload,
    );
  }

  Future<List<VaultItem>> _loadAllDecoded() async {
    final records = await _store.loadAll(userId);
    // Defense in depth: even though the store is already partitioned by
    // userId, never trust a record whose embedded userId doesn't match —
    // this is the "structurally enforced" half of own-account scoping.
    final owned = records.where((r) => r.userId == userId);
    final items = await Future.wait(owned.map(_decode));
    return items;
  }

  Future<void> _persist(List<VaultItem> items) async {
    final records = await Future.wait(items.map(_encode));
    await _store.saveAll(userId, records);
  }

  @override
  Future<List<VaultItem>> listActive() async {
    final items = await _loadAllDecoded();
    final active = items.where((i) => !i.isTrashed).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return active;
  }

  @override
  Future<List<VaultItem>> listTrash() async {
    final now = _now();
    final items = await _loadAllDecoded();
    final trashed =
        items.where((i) => i.isTrashed && !i.isPurgeable(now)).toList()
          ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return trashed;
  }

  @override
  Future<VaultItem?> getById(String id) async {
    final items = await _loadAllDecoded();
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<VaultItem> createCredential(CredentialData data) async {
    final items = await _loadAllDecoded();
    final now = _now();
    final item = VaultItem(
      id: _newId('item'),
      userId: userId,
      type: VaultItemType.credential,
      eTag: _newId('etag'),
      createdAt: now,
      updatedAt: now,
      data: data,
    );
    items.add(item);
    await _persist(items);
    return item;
  }

  @override
  Future<VaultItem> updateCredential(String id, CredentialData data) async {
    final items = await _loadAllDecoded();
    final index = items.indexWhere((i) => i.id == id);
    if (index == -1) {
      throw StateError('No vault item with id $id');
    }
    final existing = items[index];
    final revision = VaultItemRevision(
      eTag: existing.eTag,
      savedAt: existing.updatedAt,
      data: existing.data,
    );
    final updated = existing.copyWith(
      eTag: _newId('etag'),
      updatedAt: _now(),
      data: data,
      revisions: <VaultItemRevision>[revision, ...existing.revisions],
    );
    items[index] = updated;
    await _persist(items);
    return updated;
  }

  @override
  Future<void> softDelete(String id) async {
    final items = await _loadAllDecoded();
    final index = items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    items[index] = items[index].copyWith(deletedAt: _now());
    await _persist(items);
  }

  @override
  Future<VaultItem?> restore(String id) async {
    final now = _now();
    final items = await _loadAllDecoded();
    final index = items.indexWhere((i) => i.id == id);
    if (index == -1) return null;
    final existing = items[index];
    if (!existing.isTrashed || existing.isPurgeable(now)) return null;
    final restored = existing.copyWith(clearDeletedAt: true, updatedAt: now);
    items[index] = restored;
    await _persist(items);
    return restored;
  }

  @override
  Future<VaultItem?> restoreRevision(String id, String revisionETag) async {
    final items = await _loadAllDecoded();
    final index = items.indexWhere((i) => i.id == id);
    if (index == -1) return null;
    final existing = items[index];
    final revisionIndex = existing.revisions.indexWhere(
      (r) => r.eTag == revisionETag,
    );
    if (revisionIndex == -1) return null;
    final targetRevision = existing.revisions[revisionIndex];

    final currentAsRevision = VaultItemRevision(
      eTag: existing.eTag,
      savedAt: existing.updatedAt,
      data: existing.data,
    );
    final remainingRevisions = List<VaultItemRevision>.from(
      existing.revisions,
    )..removeAt(revisionIndex);

    final restored = existing.copyWith(
      eTag: _newId('etag'),
      updatedAt: _now(),
      data: targetRevision.data,
      revisions: <VaultItemRevision>[
        currentAsRevision,
        ...remainingRevisions,
      ],
    );
    items[index] = restored;
    await _persist(items);
    return restored;
  }
}
