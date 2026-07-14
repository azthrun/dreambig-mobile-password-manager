package com.dreambig.password_manager

import android.app.PendingIntent
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews

/**
 * Android Autofill Framework entry point (GOALS_v2 §1.8). Registered in
 * `AndroidManifest.xml` with the standard `BIND_AUTOFILL_SERVICE`
 * `<service>` shape so the OS can offer this app as the device's autofill
 * provider.
 *
 * ## Critical constraint this class is built around
 * The OS can instantiate this service in a fresh process at any time —
 * e.g. while the user is filling a form in some *other* app, with this
 * app never launched this boot. There is no vault key and therefore no
 * decrypted vault data available to native code in that case: per
 * GOALS_v2 §2 and `AuthState.vaultKey`'s doc comment, the vault key only
 * ever exists in the main Dart isolate's memory while there's a
 * signed-in-unlocked session, and it is deliberately never persisted
 * anywhere a keyless native service could read it independently.
 * Weakening that just to make this service self-sufficient would undercut
 * the exact model Phases 1–2 built, so this class never attempts to read
 * or decrypt vault storage itself.
 *
 * ## What this Phase 1 implementation actually does
 * On every fill request, it best-effort asks the already-running Flutter
 * engine (if any) for matches via [AutofillBridge]. If that returns real
 * suggestions, each is offered as a fillable [Dataset]. If it returns
 * nothing (most commonly: no engine running, or one running but with no
 * unlocked session's handler registered — see `AutofillBridgeService` on
 * the Dart side), this falls back to a single generic "Unlock to
 * autofill" dataset whose [Dataset.Builder.setAuthentication] points at a
 * [PendingIntent] into [MainActivity] — the same mechanism the framework
 * itself uses for biometric-gated datasets. Tapping it opens the app for
 * the user to unlock and copy/fill the credential manually; it does not
 * attempt to auto-complete the fill after unlock (carrying the
 * [AutofillId]s across that activity round-trip is a reasonable follow-up,
 * not attempted in this phase).
 *
 * [onSaveRequest] is intentionally stubbed (always declines): offering to
 * *save* a newly-typed credential back into the vault needs the same
 * "only while unlocked, with the real vault key" constraint as fill does,
 * plus UI to confirm which item/site the save belongs to and to actually
 * write through `VaultRepository.createCredential`/`updateCredential` —
 * a materially bigger feature than "read-only suggestions," and out of
 * scope for this Phase 8 pass per the worker brief. The Autofill
 * Framework treats [SaveCallback.onFailure] as "this service declined to
 * offer a save," which is a safe, well-defined no-op rather than a crash.
 *
 * ## What's honestly untested here
 * There is no Android emulator/device in this build sandbox, so none of
 * `onFillRequest`, `onSaveRequest`, the manifest's `<service>`
 * registration, or the `AutofillBridge` channel round-trip have been
 * exercised against the real Android Autofill Framework. This is written
 * and reasoned through against the public `android.service.autofill` API
 * shape (mirroring `MainActivity`'s existing `secure_screen` platform
 * channel as the one precedent in this codebase for native/Dart
 * integration style), but should get a real-device smoke test — including
 * enabling this app as the system autofill service in Settings and
 * exercising fill/unlock — before shipping.
 */
class PasswordManagerAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val target = AutofillStructureParser.parse(structure)
        if (target.fields.isEmpty()) {
            // Nothing on screen looks like a credential field — offer
            // nothing rather than guessing.
            callback.onSuccess(null)
            return
        }

        AutofillBridge.fetchSuggestions(
            packageName = target.packageName,
            webDomain = target.webDomain,
        ) { suggestions ->
            if (cancellationSignal.isCanceled) return@fetchSuggestions

            val responseBuilder = FillResponse.Builder()
            if (suggestions.isNullOrEmpty()) {
                responseBuilder.addDataset(buildUnlockDataset(target))
            } else {
                suggestions.forEach { suggestion ->
                    responseBuilder.addDataset(buildDataset(target, suggestion))
                }
            }
            callback.onSuccess(responseBuilder.build())
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // See class doc comment: saving is out of scope for this phase.
        callback.onFailure(null)
    }

    /**
     * Fills [AutofillTarget.identifierFields] (username/email) with
     * [AutofillSuggestion.identifier] and [AutofillTarget.passwordFields]
     * with [AutofillSuggestion.secret] — deliberately two different values,
     * not the same value stuffed into every field, so a password field
     * actually receives the password rather than the username.
     */
    private fun buildDataset(target: AutofillTarget, suggestion: AutofillSuggestion): Dataset {
        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(android.R.id.text1, suggestion.label)
        }
        val builder = Dataset.Builder(presentation)
        val identifierValue = AutofillValue.forText(suggestion.identifier)
        val secretValue = AutofillValue.forText(suggestion.secret)
        target.identifierFields.forEach { field -> builder.setValue(field, identifierValue) }
        target.passwordFields.forEach { field -> builder.setValue(field, secretValue) }
        return builder.build()
    }

    private fun buildUnlockDataset(target: AutofillTarget): Dataset {
        // Externalized via res/values/strings.xml rather than hardcoded here
        // — Flutter's l10n mechanism doesn't reach native Kotlin code, so
        // Android's own string-resource mechanism is the idiomatic
        // equivalent (see strings.xml's doc comment).
        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(
                android.R.id.text1,
                applicationContext.getString(R.string.autofill_unlock_prompt),
            )
        }
        val unlockIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            unlockIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Dataset.Builder(presentation)
        builder.setAuthentication(pendingIntent.intentSender)
        // A dataset built with `setAuthentication` still needs a value
        // entry per field for the framework to treat it as fillable; the
        // real value is intentionally left null since control hands off to
        // `unlockIntent` before any value would ever be applied (per the
        // Autofill Framework's documented auth-dataset pattern).
        target.fields.forEach { field -> builder.setValue(field, null) }
        return builder.build()
    }
}
