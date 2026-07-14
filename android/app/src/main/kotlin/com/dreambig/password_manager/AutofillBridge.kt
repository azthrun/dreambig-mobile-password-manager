package com.dreambig.password_manager

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** A single suggestion handed back from the Dart-side vault, already
 * decrypted (only ever produced while the Dart isolate holds an unlocked
 * session's vault key in memory — see `AutofillBridgeService`'s doc
 * comment on the Dart side). [label] is what's shown in the autofill
 * picker UI; [identifier] is filled into username/email fields and
 * [secret] into password fields (see
 * `PasswordManagerAutofillService.buildDataset`) — never the same value
 * for both.
 */
data class AutofillSuggestion(
    val id: String,
    val identifier: String,
    val secret: String,
    val label: String,
)

/**
 * Best-effort bridge from [PasswordManagerAutofillService] into the
 * Dart-side `AutofillBridgeService`
 * (`lib/data/autofill/autofill_bridge_service.dart`), over the
 * `password_manager/autofill` method channel.
 *
 * This only ever succeeds if [FlutterEngineCache] holds the app's
 * already-running engine (put there once by `MainActivity`, see
 * [engineCacheId]) *and* the Dart side has registered a handler for the
 * channel, which it only does while there is a signed-in-unlocked session
 * (see `AutoLockWrapper` on the Dart side). Any other case — no cached
 * engine, an engine but no registered handler, or simply no response
 * inside [timeoutMillis] — reports `null` to [onResult] rather than
 * throwing, so the caller can fall back to the unlock suggestion instead
 * of failing the fill request outright.
 *
 * **Untested against the real Autofill Framework**: there is no
 * Android emulator/device available in this build sandbox (see
 * `PasswordManagerAutofillService`'s doc comment for the full caveat).
 * This is written and reasoned through against the public
 * `io.flutter.plugin.common.MethodChannel` / `FlutterEngineCache` APIs,
 * mirroring the one existing platform-channel precedent in this codebase
 * (`MainActivity`'s `secure_screen` channel), but has not been exercised
 * end-to-end.
 */
object AutofillBridge {
    /** Must match the key `MainActivity` caches its engine under. */
    const val engineCacheId = "password_manager_main_engine"

    /** Must match `AutofillBridgeService.channelName` on the Dart side. */
    private const val channelName = "password_manager/autofill"

    /**
     * Kept short relative to the Autofill Framework's own fill-request
     * budget: a fill request that never resolves blocks the OS's autofill
     * UI from appearing at all, so failing over quickly to the unlock
     * suggestion is strictly better than waiting out a long timeout on a
     * channel call that was never going to be answered (no engine/no
     * registered handler).
     */
    private const val timeoutMillis = 1500L

    fun fetchSuggestions(
        packageName: String,
        webDomain: String?,
        onResult: (List<AutofillSuggestion>?) -> Unit,
    ) {
        val engine = FlutterEngineCache.getInstance().get(engineCacheId)
        if (engine == null) {
            onResult(null)
            return
        }

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        val handler = Handler(Looper.getMainLooper())
        var responded = false

        fun respondOnce(value: List<AutofillSuggestion>?) {
            if (responded) return
            responded = true
            onResult(value)
        }

        handler.postDelayed({ respondOnce(null) }, timeoutMillis)

        channel.invokeMethod(
            "getSuggestions",
            mapOf("packageName" to packageName, "webDomain" to webDomain),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    @Suppress("UNCHECKED_CAST")
                    val raw = result as? List<Map<String, Any?>>
                    respondOnce(raw?.map { it.toSuggestion() })
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    respondOnce(null)
                }

                override fun notImplemented() {
                    respondOnce(null)
                }
            },
        )
    }

    private fun Map<String, Any?>.toSuggestion(): AutofillSuggestion {
        val identifier = this["identifier"] as? String ?: ""
        val secret = this["secret"] as? String ?: ""
        val siteName = (this["siteName"] as? String)?.takeIf { it.isNotBlank() }
        return AutofillSuggestion(
            id = this["id"] as? String ?: "",
            identifier = identifier,
            secret = secret,
            label = siteName ?: identifier,
        )
    }
}
