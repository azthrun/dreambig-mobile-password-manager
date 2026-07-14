// Unit tests for VaultCsvExporter implementations (GOALS_v2 §3.3). Uses
// InMemoryVaultCsvExporter (mirroring InMemoryVaultLocalStore) to avoid
// touching path_provider's platform channel, plus a temp-directory-backed
// FileVaultCsvExporter test to confirm the real file-writing path works.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/export/vault_csv_exporter.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/domain/models/vault_item_type.dart';

VaultItem _item(String id, {DateTime? deletedAt}) {
  final now = DateTime(2026, 1, 1);
  return VaultItem(
    id: id,
    userId: 'user-1',
    type: VaultItemType.credential,
    eTag: 'etag-$id',
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
    data: CredentialData(identifier: 'id-$id', secret: 'secret-$id'),
  );
}

void main() {
  group('InMemoryVaultCsvExporter', () {
    test('records the encoded CSV content against a returned path', () async {
      final exporter = InMemoryVaultCsvExporter();
      final items = <VaultItem>[_item('1'), _item('2')];

      final path = await exporter.exportActiveItems(items);

      expect(exporter.writtenFiles.containsKey(path), isTrue);
      final content = exporter.writtenFiles[path]!;
      expect(content, contains('id-1,secret-1'));
      expect(content, contains('id-2,secret-2'));
    });

    test('excludes trashed items', () async {
      final exporter = InMemoryVaultCsvExporter();
      final items = <VaultItem>[
        _item('active'),
        _item('trashed', deletedAt: DateTime(2026, 1, 2)),
      ];

      final path = await exporter.exportActiveItems(items);

      final content = exporter.writtenFiles[path]!;
      expect(content, contains('id-active'));
      expect(content, isNot(contains('id-trashed')));
    });

    test('successive exports get distinct paths', () async {
      final exporter = InMemoryVaultCsvExporter();

      final path1 = await exporter.exportActiveItems(<VaultItem>[_item('1')]);
      final path2 = await exporter.exportActiveItems(<VaultItem>[_item('2')]);

      expect(path1, isNot(equals(path2)));
    });
  });

  group('FileVaultCsvExporter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('csv_export_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes a real CSV file and returns its path', () async {
      final exporter = FileVaultCsvExporter(
        directory: tempDir,
        now: () => DateTime(2026, 1, 1, 12, 0, 0),
      );
      final items = <VaultItem>[_item('1')];

      final path = await exporter.exportActiveItems(items);
      final file = File(path);

      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('identifier,secret,siteName,url,notes,tags'));
      expect(content, contains('id-1,secret-1'));
    });
  });
}
