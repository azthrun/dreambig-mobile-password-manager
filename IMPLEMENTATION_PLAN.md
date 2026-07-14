# Implementation Plan — Password Manager (Flutter)

Source of truth for requirements: [GOALS_v2.md](GOALS_v2.md). This plan breaks Phase 1 (Android-only) delivery into dev phases, each executed by a worker subagent, reviewed by a reviewer subagent (iterate until clean), then gated by a phase reviewer before the next phase starts.

Backend note: no backend project/infra has been specified. Each phase builds against an abstracted `ApiClient`/repository interface with a local fake/mock implementation, so the app is runnable and testable end-to-end without a real backend. Swapping in a real backend later is an interface implementation, not an architecture change.

## Process per phase
1. Worker subagent implements the phase's scope against this plan + GOALS_v2.md.
2. Reviewer subagent reviews the worker's diff (correctness, security, adherence to AGENTS.md conventions, GOALS_v2 requirements coverage). Worker fixes findings; repeat until reviewer approves.
3. Phase reviewer subagent reviews the *whole phase* (build/analyze/test green, requirements traceability, no regressions to prior phases). Only on approval do we advance.
4. Status table below updated after each gate.

## Dev phases

- **Phase 0 — Project scaffolding**: `flutter create`, layered architecture (data/domain/presentation), routing, theming, DI, lint rules, base widget/unit test setup, localization (`intl`) scaffolding, empty `ApiClient` interface + fake impl.
- **Phase 1 — Auth & session foundation**: sign-up/sign-in UI, email+master secret, email confirmation flow (fake), two-key derivation (HKDF domain-separated auth key vs vault key, Argon2id/PBKDF2 stretch), recovery-mode choice screen (local-only vs remote backup, comparative UI), secure storage (`flutter_secure_storage`) wiring, auto-lock/inactivity timeout, biometric unlock as local convenience layer.
- **Phase 2 — Vault core**: credential item model (identifier, secret, site/app, URL, notes, tags/folder, ETag, schema future-proofed for item types), local encrypted persistence, CRUD screens, soft-delete + 30-day trash, revision history, own-account-only scoping.
- **Phase 3 — Password generator**: length/charset/exclude-ambiguous options, passphrase (Diceware) mode, zxcvbn-style strength estimate, wired into item create/edit.
- **Phase 4 — Device registration & encryption**: per-device asymmetric keypair generation/storage, new-device authorization & revocation flows (against fake `ApiClient`), client-side encryption of vault payloads before any network call.
- **Phase 5 — Network & security hardening**: HTTPS client with app-layer payload encryption on top of TLS, certificate pinning config, session token issue/refresh + server-side revocation semantics (against fake backend), root/jailbreak detection gated by DEBUG/RELEASE build-time flag.
- **Phase 6 — Security UX**: clipboard auto-clear timer, `FLAG_SECURE` on secret-bearing screens, auto-lock enforcement across app lifecycle, log/crash-report scrubbing of secrets.
- **Phase 7 — Account deletion & CSV export**: re-auth-gated hard account deletion with type-to-confirm + no single-tap path, CSV export with re-auth + on-disk warning.
- **Phase 8 — Autofill integration**: Android `AutofillService` implementation scoped to own items only.
- **Phase 9 — Accessibility, localization, final QA**: screen reader labels, contrast/touch targets, string externalization audit, full regression pass across all phases.

## Status

| Phase | Worker | Reviewer | Phase Reviewer | Status |
|---|---|---|---|---|
| 0 | done | done | done | Approved — Phase 1 unlocked |
| 1 | done | done | done | Approved — Phase 2 unlocked |
| 2 | done | done | done | Approved — Phase 3 unlocked |
| 3 | done | done | done | Approved — Phase 4 unlocked |
| 4 | done | done | done | Approved — Phase 5 unlocked |
| 5 | done | done | done | Approved — Phase 6 unlocked |
| 6 | done | done | done | Approved — Phase 7 unlocked |
| 7 | done | done | done | Approved — Phase 8 unlocked |
| 8 | done | done | done | Approved — Phase 9 unlocked (not started, work paused here per user request) |
| 9 | done | done | done | Approved — all 10 phases (0-9) complete, GOALS_v2.md Phase 1 scope fully covered |
