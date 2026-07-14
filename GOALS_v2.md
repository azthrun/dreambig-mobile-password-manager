# Goals & Requirements v2 — Password Manager (Flutter)

Supersedes [GOALS.md](GOALS.md). All open questions from v1 have been decided; this version bakes those decisions into the requirements and calls out a few implementation-level follow-ups the decisions themselves raise.

## Scope

Build a Flutter mobile app for managing personal passwords. (Sharing is explicitly deferred — see 1.6.)

**Phase 1**: Android only (build/test target). iOS should not be architecturally precluded, but is not tested yet.

---

## 1. Functional Requirements

### 1.1 Vault items
- Users can save credentials: identifier (username/email), secret (password), plus **site/app name, URL, notes, and tags/folder** for organization.
- **Decided**: Phase 1 is **credentials-only** — no secure notes, cards, or identity items. Data schema should still be modeled so other item types can be added later without a breaking migration.
- Users can edit and delete stored items.
  - Deletes are **soft delete with a recovery window** (e.g., 30-day trash), distinct from the permanent hard-delete in 1.7 (full account deletion).
  - Maintain **revision history** per item so users can recover after an overwrite.
- Users can only view/edit items belonging to their own signed-in account. (No shared-item exception in Phase 1 — see 1.6.)

### 1.2 Password generator
- Configurable length, character sets (upper/lower/digits/symbols), and an option to exclude ambiguous characters (`0/O`, `1/l/I`).
- **Passphrase mode** (word-based, Diceware-style).
- **Strength estimate** (e.g., zxcvbn-style scoring) shown at generation and entry time.

### 1.3 Authentication & session
- Sign-in required before use: **email + master secret only** for Phase 1 (no OAuth/SSO).
  - New accounts require **email confirmation** (verification link/code) before the account is usable.
  - **Decided**: the authentication credential and the vault encryption key root must be **fully separated**, not just two derivations of convenience. Concretely: independent KDF derivations (distinct salts/domain-separated contexts, e.g. HKDF with different `info` labels) from the master secret such that **neither key can be computed from the other**, and a server-side breach of the stored authentication key (or its hash) must not leak any information usable to derive the vault encryption key. The **vault encryption key never leaves the device** under any circumstance; only the authentication key is transmitted (and only in stretched/hashed form) to the server.
- Biometric unlock (fingerprint/Face ID) is an *additional, local* convenience layer only — it unlocks the local session, never replaces the master secret as the root of encryption key derivation.
- **Auto-lock** after a configurable inactivity timeout or on app backgrounding, requiring re-authentication to resume.
- **Account recovery — decided**: recovery mode is presented as an **explicit, up-front choice during signup** (before an account/vault is created — not a setting discoverable later, and not a hidden default), with the consequences of each option spelled out in the UI at the moment of choosing:
  1. **Local-only** — master secret and vault key exist only on-device; no recovery possible. UI must state plainly, before the user commits: losing the device *or* forgetting the master secret means **permanent, total data loss**; the vault cannot sync to another device; and the vault is lost on app uninstall or device wipe.
  2. **Remote backup** — an encrypted copy of the vault is stored server-side (still zero-knowledge; server holds ciphertext only). UI must state plainly: this protects against device loss *only if the master secret is remembered* — the server holds no plaintext and cannot recover a forgotten master secret either; a copy of the vault does leave the device (as ciphertext).
  - Both consequence statements should be shown side-by-side (or equivalent comparative UI) so the user is making an informed choice between them, not reading one disclaimer in isolation.

### 1.4 Device registration & encryption
- Devices register a public/private keypair for encryption purposes.
- Vault contents are encrypted **client-side** before leaving the device; server never sees plaintext passwords or the master secret.
- Master secret → key derivation via a slow KDF (Argon2id or PBKDF2 with high iteration count) — see 1.3 for the two-key split.
- Per-device asymmetric keypair enables new-device authorization by an already-trusted device, and revocation of a lost/stolen device.
- Local at-rest storage uses platform secure storage (Android Keystore-backed, e.g. `flutter_secure_storage`), never plain SharedPreferences/SQLite.

### 1.5 Network security
- All traffic over HTTPS/TLS, plus **application-layer encryption of the payload on top of transport encryption** (defense in depth).
- Certificate pinning to reduce MITM risk on compromised networks/CAs.
- Backend rate-limiting / lockout on repeated failed sign-in attempts (a backend requirement, noted here since it's a hard dependency of this client's security model).

### 1.6 Sharing
- **Decided**: no sharing feature in Phase 1. The product goal's mention of "shared passwords" is deferred to a later phase. This simplifies the encryption model considerably — no per-recipient key re-wrapping needed yet.

### 1.7 Account deletion
- Users can delete their own account; all associated stored data is **hard-deleted** from the backend.
- Require re-authentication immediately before this irreversible action.
- **Decided**: no data retention requirement — deletion is unconditional. In exchange:
  - Give **clear upfront communication** of what deletion means (irreversible, all devices, all backups) before the user can proceed.
  - Design the confirmation UI so accidental triggering is **near-impossible** (e.g., re-auth + explicit type-to-confirm + no single-tap path), given there is no recovery afterward.

### 1.8 Autofill / cross-app integration
- Implemented via the **Android Autofill Framework** (`AutofillService`), and for future iOS, the **Credential Provider Extension** — not a generic always-on background service.
- Autofill suggestions respect the same "own items only" access rule as 1.1.

---

## 2. Security Requirements

1. Vault data encrypted at rest on-device and in transit; server operates zero-knowledge.
2. Master secret never transmitted or stored, even hashed, in a reversible form on the backend (see 1.3's two-key derivation).
3. Auto-lock on inactivity/backgrounding.
4. Clipboard hygiene: auto-clear copied passwords after a short timeout (e.g., 30–60s).
5. Screenshot/screen-recording prevention on screens showing plaintext secrets (Android `FLAG_SECURE`).
6. **Decided**: root/jailbreak detection is required, gated by an **environment/build-variant attribute** (e.g. a compile-time flag tied to the DEBUG/RELEASE build type) — skipped on DEBUG builds so development/QA on rooted test devices and emulators isn't blocked, and enforced with no override on RELEASE builds. This must be a build-time attribute baked into the release artifact, not a runtime-toggleable flag, so it cannot be flipped off in a shipped build.
7. Session tokens short-lived with refresh; device de-authorization revokes tokens server-side immediately.
8. No secrets, logs, or crash reports ever contain plaintext credentials.

## 3. Non-Functional Requirements

### 3.1 Sync
- **Decided**: multi-device sync is deferred to a future phase, not Phase 1.
- Forward-compatibility requirement for Phase 1: **every vault item carries its own ETag** (or equivalent version token) from the start, so optimistic-concurrency sync can be added later without a data-model migration.
- Note per 1.3: this only benefits accounts in **remote backup** mode — local-only accounts have nothing to sync against.

### 3.2 Offline access
- Vault remains usable (read, and ideally write with later reconciliation) without network connectivity.

### 3.3 Backup / export / import
- **Decided**: no import in Phase 1.
- **Decided**: **CSV export is in scope**. This is a plaintext-secrets export by nature — require re-authentication immediately before export, and show an explicit warning about handling the resulting file (unencrypted on disk, should be deleted after use, etc.).

### 3.4 Accessibility & Localization
- Screen reader support, sufficient contrast/touch targets (per existing AGENTS.md convention).
- No hardcoded strings (existing convention). Target locale(s) for launch still to be confirmed — not blocking for Phase 1 requirements definition.

## 4. Explicitly Out of Scope for Phase 1

- iOS build/test.
- Browser extension / desktop clients.
- Sharing (individual or group).
- Multi-device sync.
- Import from other password managers.
- Team/enterprise admin console, SSO/SCIM provisioning.
- Breach-monitoring integrations (e.g., Have I Been Pwned checks).

---

## Decisions Log

| # | Question | Decision |
|---|---|---|
| 1 | Item types beyond credentials in Phase 1? | Credentials only |
| 2 | Sign-in method(s)? | Email + master secret; email confirmation required at signup; no OAuth/SSO |
| 3 | Account recovery approach? | User choice at signup: local-only (no recovery) or remote encrypted backup |
| 4 | Sharing in Phase 1? | No — deferred |
| 5 | Data retention after account deletion? | None — unconditional hard delete, offset by clear pre-deletion communication and accidental-trigger-proof UI |
| 6 | Root/jailbreak detection? | Required, gated by build-time DEBUG/RELEASE attribute; skipped on DEBUG, always blocks with no override on RELEASE |
| 7 | Multi-device sync strategy? | Deferred to future phase; per-item ETag added now for forward compatibility |
| 8 | Import/export in Phase 1? | No import; CSV export allowed (with re-auth + warning) |
