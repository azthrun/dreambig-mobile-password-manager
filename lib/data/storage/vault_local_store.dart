import 'dart:convert';
import 'dart:io';

import 'package:password_manager/domain/crypto/vault_item_cipher.dart';
import 'package:path_provider/path_provider.dart';

/// The on-disk representation of a single vault item: plaintext metadata
/// needed for listing/sorting/scoping, plus an opaque encrypted payload
/// covering everything sensitive (identifier, secret, notes, tags,
/// revisions). See `VaultItemCipher` for what's inside [payload].
class StoredVaultItemRecord {
  const StoredVaultItemRecord({
    required this.id,
    required this.userId,
    required this.eTag,
    required this.createdAt,
    required this.updatedAt,
    required this.payload,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String eTag;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final EncryptedVaultPayload payload;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'userId': userId,
    'eTag': eTag,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'payload': payload.toJson(),
  };

  factory StoredVaultItemRecord.fromJson(Map<String, dynamic> json) {
    return StoredVaultItemRecord(
      id: json['id'] as String,
      userId: json['userId'] as String,
      eTag: json['eTag'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      payload: EncryptedVaultPayload.fromJson(
        json['payload'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Local, encrypted-at-rest persistence for vault items.
///
/// **Persistence choice**: a single JSON document per `userId`, containing
/// [StoredVaultItemRecord]s whose sensitive fields are pre-encrypted with
/// the vault key (AES-256-GCM, see `VaultItemCipher`) before this layer
/// ever sees them. Only non-sensitive metadata (id/eTag/timestamps) is
/// plaintext, purely to allow listing/sorting without decrypting
/// everything. This was chosen over `sqflite`/`drift`/`hive` because: (a)
/// it needs zero native plugin surface beyond `path_provider` (which only
/// resolves a directory), keeping it trivially fake-able in pure-Dart unit
/// tests without platform channels — mirroring how `SecureStorageService`
/// is faked; (b) Phase 2's data volume (a personal vault, likely tens to
/// low hundreds of items) doesn't need a query engine, so a flat encrypted
/// document is simpler and has fewer moving parts than introducing a DB
/// dependency; (c) it keeps the "never plaintext SQLite/SharedPreferences"
/// requirement (GOALS_v2 §1.4) trivially true by construction — there's no
/// SQL layer that could accidentally end up with an unencrypted column.
/// If item volume or query needs grow, this interface can be swapped for a
/// `sqflite`-backed implementation (encrypting the same fields per-row)
/// without touching callers.
///
/// One file per [String] `userId` key structurally enforces "own-account-
/// only scoping" (GOALS_v2 §1.1): a caller must supply the target userId to
/// read/write anything, and different accounts' items physically never
/// live in the same file/map entry.
abstract class VaultLocalStore {
  Future<List<StoredVaultItemRecord>> loadAll(String userId);

  Future<void> saveAll(String userId, List<StoredVaultItemRecord> records);

  /// Permanently removes every locally-persisted vault item for [userId].
  ///
  /// Used only by account deletion (GOALS_v2 §1.7), which is unconditional
  /// and irreversible — this is a genuine wipe, not a soft delete like
  /// `VaultRepository.softDelete`.
  Future<void> clear(String userId);
}

/// Real implementation, backed by a JSON file per user in the app's
/// private documents directory (not shared storage, not SharedPreferences).
class FileVaultLocalStore implements VaultLocalStore {
  FileVaultLocalStore({Directory? directory}) : _directoryOverride = directory;

  final Directory? _directoryOverride;

  Future<File> _fileFor(String userId) async {
    final dir = _directoryOverride ?? await getApplicationDocumentsDirectory();
    final safeUserId = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/vault_$safeUserId.json');
  }

  @override
  Future<List<StoredVaultItemRecord>> loadAll(String userId) async {
    final file = await _fileFor(userId);
    if (!await file.exists()) return <StoredVaultItemRecord>[];
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return <StoredVaultItemRecord>[];
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final items = decoded['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .map((e) => StoredVaultItemRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAll(
    String userId,
    List<StoredVaultItemRecord> records,
  ) async {
    final file = await _fileFor(userId);
    await file.parent.create(recursive: true);
    final document = <String, dynamic>{
      'schemaVersion': 1,
      'items': records.map((r) => r.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(document));
  }

  @override
  Future<void> clear(String userId) async {
    final file = await _fileFor(userId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// In-memory fake for unit/widget tests, mirroring `InMemorySecureStorageService`.
///
/// Data is partitioned by `userId` in the map itself, so tests can assert
/// scoping directly (querying with a different userId can never see
/// another user's records).
class InMemoryVaultLocalStore implements VaultLocalStore {
  final Map<String, List<StoredVaultItemRecord>> _byUser =
      <String, List<StoredVaultItemRecord>>{};

  @override
  Future<List<StoredVaultItemRecord>> loadAll(String userId) async {
    return List<StoredVaultItemRecord>.from(
      _byUser[userId] ?? const <StoredVaultItemRecord>[],
    );
  }

  @override
  Future<void> saveAll(
    String userId,
    List<StoredVaultItemRecord> records,
  ) async {
    _byUser[userId] = List<StoredVaultItemRecord>.from(records);
  }

  @override
  Future<void> clear(String userId) async {
    _byUser.remove(userId);
  }
}
