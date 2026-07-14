package com.dreambig.password_manager

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by the
// local_auth plugin for biometric unlock (GOALS_v2 §1.3).
class MainActivity : FlutterFragmentActivity() {
    // Minimal platform channel backing `SecureScreenService`
    // (lib/data/security/secure_screen_service.dart) — toggles
    // `FLAG_SECURE` so screenshots/screen-recording are blocked while
    // secret-bearing screens are on screen (GOALS_v2 §2.5). Deliberately
    // just this one method rather than a third-party plugin; see that
    // file's doc comment for the dependency-vs-platform-channel rationale.
    private val secureScreenChannelName = "password_manager/secure_screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Caches this (the app's single, normal-lifecycle) FlutterEngine so
        // `PasswordManagerAutofillService` — which the OS can spin up in a
        // separate code path with no engine of its own — can look it up and
        // best-effort ask the already-running Dart side for autofill
        // matches (GOALS_v2 §1.8). See `AutofillBridge.kt` and
        // `lib/data/autofill/autofill_bridge_service.dart` for the full
        // "only works if this engine happens to already be alive" scope;
        // this cache entry is the native half of that story.
        FlutterEngineCache.getInstance().put(AutofillBridge.engineCacheId, flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            secureScreenChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE,
                        )
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
