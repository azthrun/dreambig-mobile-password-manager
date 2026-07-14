# Goals & Requirements — Password Manager (Flutter)

This refines [SPECS.md](SPECS.md). Original requirements are kept (renumbered) with clarifications; new items fill gaps that are essential for a password manager specifically. Items marked **[OPEN]** need a decision from you before implementation.

## Scope

Build a Flutter mobile app for managing personal and shared passwords.

**Phase 1**: Android only (build/test target). iOS should not be architecturally precluded, but is not tested yet.

---

## 1. Functional Requirements

### 1.1 Vault items
- Users can save credentials: identifier (username/email), secret (password), and — refined — also **site/app name, URL, notes, and tags/folder** for organization. A password manager without a name/URL field is unusable at scale.
- **[OPEN]** Should Phase 1 support additional item types (secure notes, payment cards, identity/passport info), or credentials only? Recommend: credentials-only for Phase 1, model the data schema so other types can be added later without migration pain.
  - **[ANSWER]** Phase 1 should support credentials only.
- Users can edit and delete stored items.
  - **Refined**: deletes should be **soft delete with a recovery window** (e.g., 30-day trash) at the UI/sync layer, distinct from the permanent hard-delete required in 1.9 for full account deletion. Losing a password to a fat-fingered delete is a common, painful failure mode.
  - **New**: maintain **revision history** per item (old password values) so users can recover after an overwrite — a top-priority feature in every mainstream password manager.
- Users can only view/edit items belonging to their own signed-in account, **except** items explicitly shared with them (see 1.6).

### 1.2 Password generator
- Generate passwords with configurable: length, character sets (upper/lower/digits/symbols), and an option to exclude ambiguous characters (`0/O`, `1/l/I`).
- **New**: support a **passphrase mode** (e.g., word-based, Diceware-style) — increasingly required by sites and easier for users to type manually.
- **New**: show a **strength estimate** (e.g., zxcvbn-style scoring) at generation and entry time.

### 1.3 Authentication & session
- Sign-in required before use.
- **[OPEN]** What's the sign-in method — email/password only, or also OAuth/SSO (Google/Apple)? Note OAuth complicates the "zero-knowledge" model in 1.5 since the master secret can't be derived from an OAuth token alone.
  - **[ANSWER]** Phase 1 should not use OAuth/SSO. Sign in with email + master secret only. Users should receive confirmation email to confirm the email address.
- Biometric unlock (fingerprint/Face ID) is an *additional, local* convenience layer — **it must unlock the local vault/session only, not replace the master password as the root of encryption key derivation**. If the phone's biometric store is compromised, vault data must not be recoverable without the master password.
- **New**: **auto-lock** after a configurable inactivity timeout or on app backgrounding, requiring re-authentication (biometric or master password) to resume.
- **New**: **account recovery** flow when a user forgets their master password. This is a genuine hard problem in zero-knowledge systems (see 1.5) — **[OPEN]**: decide between (a) no recovery possible, full data loss, prompting mandatory user-generated recovery kit/emergency codes at signup, or (b) a recovery mechanism that necessarily weakens zero-knowledge guarantees. Needs explicit tradeoff sign-off since it's a security-vs-usability decision, not an engineering detail.
  - **[ANSWER]** Allow users to pick between: 1. no recovery, everything stores locally - make sure users understand that master secret will only be stored locally, and the risk of full data loss; 2. remote backups - a copy of encrypted data will be stored remotely.

### 1.4 Device registration & encryption
- Devices register a public/private keypair for encryption purposes (from original spec).
- **Refined/expanded** — this needs to be a concrete architecture, not just "keys exist":
  - Vault contents are encrypted **client-side** before leaving the device (zero-knowledge: server never sees plaintext passwords or the master password).
  - Master password → key derivation via a slow KDF (Argon2id or PBKDF2 with high iteration count), never sent to the server.
  - Per-device asymmetric keypair enables secure multi-device sync (e.g., vault key wrapped per device) and new-device authorization by an already-trusted device.
  - **New**: define the **new device onboarding / de-authorization flow** — how does a second phone get access, and how does the user revoke a lost/stolen device's access?
- Local at-rest storage must use platform secure storage (Android Keystore-backed encrypted storage, e.g. `flutter_secure_storage`), not plain SharedPreferences/SQLite.

### 1.5 Network security
- All traffic over HTTPS/TLS with **application-layer encryption of the payload on top of transport encryption** (defense in depth — "encrypted information via HTTP requests" in the original spec was slightly ambiguous; corrected to HTTPS + payload encryption).
- **New**: certificate pinning to reduce MITM risk on compromised networks/CAs.
- **New**: backend rate-limiting / lockout on repeated failed sign-in attempts (brute-force protection) — a client-only requirement can't enforce this; call out as a backend requirement even though this repo is the Flutter client.

### 1.6 Sharing (referenced in the project goal, absent from original requirements)
- **[OPEN]** The stated goal says "personal or shared passwords," but no requirement covers sharing. Needs explicit scope for Phase 1:
  - Is sharing in scope at all for Phase 1, or deferred?
  - If in scope: share with individual users vs. groups/"vaults"? Read-only vs. edit access? Revocable?
  - Sharing complicates the encryption model in 1.4 (shared item keys must be re-encrypted per recipient's public key).
  - **[ANSWER]** No sharing feature for Phase 1.

### 1.7 Account deletion
- Users can delete their own account; all associated stored data is **hard-deleted** from the backend (original spec, kept as-is — reasonable for a security product).
- **New**: require re-authentication immediately before this irreversible action, and a confirmation step (type-to-confirm or similar) given the blast radius.
- **[OPEN]** Any legal/compliance retention requirement (e.g., audit logs) that must survive account deletion, or is deletion unconditional?
  - **[ANSWER]** Clear communication with users before deletion occurs. Also design the UI in a way that deletion can almost impossible happen "accidentally".

### 1.8 Autofill / cross-app integration
- **Refined**: "background service to fetch/store account info for other apps" is more precisely the **Android Autofill Framework** (`AutofillService`) and, for future iOS, the **Credential Provider Extension** / iOS Autofill. Recommend rewording the requirement this way — a generic always-on background service is both a battery-drain and Play Store policy risk; the platform autofill APIs are the sanctioned, expected mechanism.
- Autofill suggestions must respect the same "only the signed-in user's own + shared-with items" access rule as 1.1.

---

## 2. Security Requirements (elevated to first-class, not buried in functional list)

1. Vault data encrypted at rest on-device and in transit; server operates zero-knowledge (cannot read plaintext credentials or master password).
2. Master password never transmitted or stored, even hashed, in a reversible form on the backend.
3. Auto-lock on inactivity/backgrounding.
4. Clipboard hygiene: auto-clear copied passwords after a short timeout (e.g., 30–60s); mark password fields to avoid inclusion in clipboard managers where possible.
5. Screenshot/screen-recording prevention on screens showing plaintext secrets (Android `FLAG_SECURE`).
6. **[OPEN]** Root/jailbreak detection — block or warn on compromised devices? Common in this product category but adds complexity and false-positive risk.
  - **[ANSWER]** Add root/jailbreak detection. Never allow jailbroken devices. Exclude DEBUG builds.
7. Session tokens short-lived with refresh; device de-authorization revokes tokens server-side immediately.
8. No secrets, logs, or crash reports ever contain plaintext credentials (verify crash reporting/analytics tooling scrubs vault data).

## 3. Non-Functional Requirements (new section)

- **Sync**: multi-device sync behavior and conflict resolution (e.g., last-write-wins vs. per-item revision) — **[OPEN]**, needs a decision since it affects the data model.
  - **[ANSWER]** Expect sync feature in future phase. Each vault item should have its own Etag.
- **Offline access**: vault should remain usable (read, and ideally write with later sync) without network connectivity.
- **Backup/export**: users can export their vault (encrypted, or plaintext with explicit warning) for migration/backup purposes; import from common formats (CSV) for onboarding from other password managers. **[OPEN]** — in scope for Phase 1?
  - **[ANSWER]** No imports in Phase 1. But users can export to CSV.
- **Accessibility**: screen reader support, sufficient contrast/touch targets, since AGENTS.md already calls this out as a project convention.
- **Localization**: no hardcoded strings (already an AGENTS.md convention) — confirm which locales matter for launch.

## 4. Explicitly Out of Scope for Phase 1 (recommend stating this to avoid scope creep)

- iOS build/test (architecture should not block it, but no testing effort).
- Browser extension / desktop clients.
- Team/enterprise admin console, SSO/SCIM provisioning.
- Breach-monitoring integrations (e.g., Have I Been Pwned checks) — good Phase 2 candidate.

---

## Summary of decisions needed from you

| # | Question | Why it matters |
|---|---|---|
| 1 | Item types beyond credentials in Phase 1? | Affects data model |
| 2 | Sign-in method(s) — password only or OAuth/SSO too? | Affects encryption key derivation model |
| 3 | Account recovery approach when master password is forgotten? | Fundamental security/usability tradeoff |
| 4 | Is sharing in scope for Phase 1? What access model? | Goal statement mentions "shared passwords" but no requirement covers it |
| 5 | Any data retention requirement surviving account deletion? | Compliance |
| 6 | Root/jailbreak detection required? | Security vs. complexity tradeoff |
| 7 | Multi-device sync conflict resolution strategy? | Data model design |
| 8 | Import/export in Phase 1? | Scope |
