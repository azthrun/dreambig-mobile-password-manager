import 'package:flutter/material.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';

/// Shown instead of the real app when [DeviceIntegrityGate] blocks launch
/// (GOALS_v2 §2.6, release builds only). Deliberately has **no** button,
/// link, or gesture that continues into the app — "enforced with no
/// override on RELEASE builds" means exactly that.
class CompromisedDeviceApp extends StatelessWidget {
  const CompromisedDeviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  // liveRegion so a screen reader announces this blocking
                  // message immediately on launch, without requiring the
                  // user to manually explore the screen first — this is a
                  // security-critical dead end with no other affordance.
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.gpp_bad_outlined,
                          color: Colors.redAccent,
                          size: 64,
                          semanticLabel: '',
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.securityBlockedTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.securityBlockedMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
