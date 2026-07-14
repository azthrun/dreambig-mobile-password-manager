// Unit tests for the pure CSV-building logic behind vault export
// (GOALS_v2 §3.3): column shape, RFC4180-style escaping of commas/quotes/
// newlines, and that only active (non-trashed) items are included.

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/domain/export/vault_csv_encoder.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/domain/models/vault_item_type.dart';

VaultItem _item({
  required String id,
  required CredentialData data,
  DateTime? deletedAt,
}) {
  final now = DateTime(2026, 1, 1);
  return VaultItem(
    id: id,
    userId: 'user-1',
    type: VaultItemType.credential,
    eTag: 'etag-$id',
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
    data: data,
  );
}

void main() {
  test('encodes a header row followed by one row per active item', () {
    final items = <VaultItem>[
      _item(
        id: '1',
        data: const CredentialData(
          identifier: 'alice@example.com',
          secret: 'hunter2',
          siteName: 'Example',
          url: 'https://example.com',
          notes: 'a note',
          tags: <String>['work', 'personal'],
        ),
      ),
    ];

    final csv = encodeVaultItemsAsCsv(items);
    final lines = csv.split('\r\n');

    expect(lines[0], 'identifier,secret,siteName,url,notes,tags');
    expect(
      lines[1],
      'alice@example.com,hunter2,Example,https://example.com,a note,'
      'work;personal',
    );
    // Trailing CRLF after the last row leaves one empty element.
    expect(lines.last, isEmpty);
  });

  test('excludes soft-deleted (trashed) items even if passed in', () {
    final items = <VaultItem>[
      _item(
        id: 'active',
        data: const CredentialData(identifier: 'a', secret: 's'),
      ),
      _item(
        id: 'trashed',
        data: const CredentialData(identifier: 'b', secret: 't'),
        deletedAt: DateTime(2026, 1, 2),
      ),
    ];

    final csv = encodeVaultItemsAsCsv(items);

    expect(csv, contains('a,s,'));
    expect(csv, isNot(contains('b,t,')));
  });

  test('quotes and escapes fields containing commas', () {
    final items = <VaultItem>[
      _item(
        id: '1',
        data: const CredentialData(
          identifier: 'id',
          secret: 'secret',
          notes: 'contains, a comma',
        ),
      ),
    ];

    final csv = encodeVaultItemsAsCsv(items);

    expect(csv, contains('"contains, a comma"'));
  });

  test('quotes and doubles embedded double quotes', () {
    final items = <VaultItem>[
      _item(
        id: '1',
        data: const CredentialData(
          identifier: 'id',
          secret: 'secret',
          notes: 'has "quoted" text',
        ),
      ),
    ];

    final csv = encodeVaultItemsAsCsv(items);

    expect(csv, contains('"has ""quoted"" text"'));
  });

  test('quotes fields containing embedded newlines', () {
    final items = <VaultItem>[
      _item(
        id: '1',
        data: const CredentialData(
          identifier: 'id',
          secret: 'secret',
          notes: 'line one\nline two',
        ),
      ),
    ];

    final csv = encodeVaultItemsAsCsv(items);

    expect(csv, contains('"line one\nline two"'));
  });

  test(
    'quotes and escapes a field containing a comma, a quote, and a '
    'newline all at once',
    () {
      final items = <VaultItem>[
        _item(
          id: '1',
          data: const CredentialData(
            identifier: 'id',
            secret: 'secret',
            notes: 'line one, has "quotes"\nline two',
          ),
        ),
      ];

      final csv = encodeVaultItemsAsCsv(items);

      expect(
        csv,
        contains('"line one, has ""quotes""\nline two"'),
      );
      // The embedded newline must not have created a spurious extra row.
      expect(csv.split('\r\n').length, 3); // header + 1 data row + trailing.
    },
  );

  test('a field needing no escaping is left unquoted', () {
    final items = <VaultItem>[
      _item(
        id: '1',
        data: const CredentialData(identifier: 'plain', secret: 'plain2'),
      ),
    ];

    final csv = encodeVaultItemsAsCsv(items);
    final dataLine = csv.split('\r\n')[1];

    expect(dataLine.startsWith('plain,plain2,'), isTrue);
  });

  test('empty item list still produces just the header row', () {
    final csv = encodeVaultItemsAsCsv(const <VaultItem>[]);

    expect(csv, 'identifier,secret,siteName,url,notes,tags\r\n');
  });
}
