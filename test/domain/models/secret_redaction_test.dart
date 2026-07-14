// GOALS_v2 §2.8: "No secrets, logs, or crash reports ever contain
// plaintext credentials." This is defense-in-depth — if a bug ever causes
// one of these objects to get interpolated into a log line or crash
// report, its `toString()` must not leak the secret it carries.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/domain/auth/auth_state.dart';
import 'package:password_manager/domain/auth/auth_status.dart';
import 'package:password_manager/domain/models/auth_session.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/domain/models/vault_item_revision.dart';
import 'package:password_manager/domain/models/vault_item_type.dart';

const _secretMarker = 'S3cr3t-Marker-Value';
const _accessTokenMarker = 'access-token-marker';
const _refreshTokenMarker = 'refresh-token-marker';

void main() {
  group('toString() secret redaction', () {
    test('CredentialData.toString() never contains the raw secret or notes', () {
      const data = CredentialData(
        identifier: 'alice@example.com',
        secret: _secretMarker,
        siteName: 'Example',
        notes: 'sensitive notes: $_secretMarker',
      );

      final rendered = data.toString();

      expect(rendered, isNot(contains(_secretMarker)));
      expect(rendered, contains('alice@example.com'));
      expect(rendered, contains('<redacted>'));
    });

    test('AuthSession.toString() never contains the raw tokens', () {
      final session = AuthSession(
        userId: 'user-1',
        accessToken: _accessTokenMarker,
        refreshToken: _refreshTokenMarker,
        expiresAt: DateTime.utc(2026, 1, 1),
      );

      final rendered = session.toString();

      expect(rendered, isNot(contains(_accessTokenMarker)));
      expect(rendered, isNot(contains(_refreshTokenMarker)));
      expect(rendered, contains('user-1'));
    });

    test(
      'AuthState.toString() never contains the raw vault key or tokens',
      () {
        final state = AuthState(
          status: AuthStatus.signedInUnlocked,
          email: 'bob@example.com',
          userId: 'user-2',
          accessToken: _accessTokenMarker,
          refreshToken: _refreshTokenMarker,
          vaultKey: Uint8List.fromList(_secretMarker.codeUnits),
        );

        final rendered = state.toString();

        expect(rendered, isNot(contains(_accessTokenMarker)));
        expect(rendered, isNot(contains(_refreshTokenMarker)));
        expect(rendered, isNot(contains(_secretMarker)));
        expect(rendered, contains('bob@example.com'));
      },
    );

    test(
      'a signed-out AuthState.toString() reports null rather than "<redacted>"',
      () {
        const state = AuthState.signedOut();
        expect(state.toString(), contains('accessToken: null'));
        expect(state.toString(), contains('vaultKey: null'));
      },
    );

    test('VaultItem.toString() never contains the raw secret', () {
      final item = VaultItem(
        id: 'item-1',
        userId: 'user-1',
        type: VaultItemType.credential,
        eTag: 'etag-1',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        data: const CredentialData(
          identifier: 'carol@example.com',
          secret: _secretMarker,
        ),
      );

      expect(item.toString(), isNot(contains(_secretMarker)));
    });

    test('VaultItemRevision.toString() never contains the raw secret', () {
      final revision = VaultItemRevision(
        eTag: 'etag-1',
        savedAt: DateTime.utc(2026, 1, 1),
        data: const CredentialData(
          identifier: 'carol@example.com',
          secret: _secretMarker,
        ),
      );

      expect(revision.toString(), isNot(contains(_secretMarker)));
    });
  });
}
