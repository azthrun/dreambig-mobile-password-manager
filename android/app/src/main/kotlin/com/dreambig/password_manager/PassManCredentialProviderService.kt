package com.dreambig.password_manager

import android.credentials.ClearCredentialStateException
import android.credentials.CreateCredentialException
import android.credentials.GetCredentialException
import android.os.Build
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import android.service.credentials.BeginCreateCredentialRequest
import android.service.credentials.BeginCreateCredentialResponse
import android.service.credentials.BeginGetCredentialRequest
import android.service.credentials.BeginGetCredentialResponse
import android.service.credentials.ClearCredentialStateRequest
import android.service.credentials.CredentialProviderService
import androidx.annotation.RequiresApi

/**
 * Minimal Credential Manager provider (API 34+).
 *
 * On Android 14+ the Settings surface for choosing a password service
 * ("Passwords, passkeys & autofill" / "Preferred service") is driven by
 * the Credential Manager framework, not the classic Autofill Framework —
 * an app that only declares an [android.service.autofill.AutofillService]
 * no longer shows up there on many devices. Declaring this service (with
 * `BIND_CREDENTIAL_PROVIDER_SERVICE` and the password-credential
 * capability, see `res/xml/credential_provider_configuration.xml`) is what
 * makes PassMan selectable as a password service on those devices.
 *
 * Actual credential fill still happens through
 * [PasswordManagerAutofillService]: once the user selects PassMan as their
 * service, the framework routes ordinary username/password form fills to
 * the autofill path. This provider therefore intentionally returns empty
 * responses — the same "no vault key available to a cold-started native
 * service" constraint documented on [PasswordManagerAutofillService]
 * applies here, and passkey support is out of scope for this phase.
 *
 * The OS only ever binds this service on API 34+, so the class (which
 * references API 34 types) is never loaded on older versions even though
 * it is unconditionally declared in the manifest.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class PassManCredentialProviderService : CredentialProviderService() {

    override fun onBeginGetCredential(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>,
    ) {
        // No passkeys/credentials surfaced via Credential Manager yet;
        // password fills are served by PasswordManagerAutofillService.
        callback.onResult(BeginGetCredentialResponse())
    }

    override fun onBeginCreateCredential(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>,
    ) {
        // Decline to offer save/create options (mirrors the stubbed
        // onSaveRequest on the autofill side).
        callback.onResult(BeginCreateCredentialResponse())
    }

    override fun onClearCredentialState(
        request: ClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void, ClearCredentialStateException>,
    ) {
        // Nothing is cached provider-side, so clearing is a no-op.
        callback.onResult(null)
    }
}
