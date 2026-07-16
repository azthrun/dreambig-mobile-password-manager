import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Must match `SecureScreenService.channelName`
  // (lib/data/security/secure_screen_service.dart) and the Android
  // counterpart in MainActivity.kt.
  private let secureScreenChannelName = "password_manager/secure_screen"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // iOS half of the `SecureScreenService` platform channel (GOALS_v2
    // §2.5). Android toggles `FLAG_SECURE`; iOS has no direct equivalent,
    // so `SecureScreenController` combines the secure-text-field capture
    // shield (blanks screenshots/recordings) with a privacy cover in the
    // app switcher. Kept inline here, mirroring how the Android handler
    // lives directly in MainActivity.kt.
    guard
      let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecureScreenChannel")
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: secureScreenChannelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSecure":
        let arguments = call.arguments as? [String: Any]
        let enabled = arguments?["enabled"] as? Bool ?? false
        DispatchQueue.main.async {
          SecureScreenController.shared.setSecure(enabled)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// iOS analogue of Android's `FLAG_SECURE` (GOALS_v2 §2.5), best-effort:
///
///  * **Screenshots / screen recording**: iOS offers no supported API to
///    block capture of arbitrary views, but content hosted inside a secure
///    text field's layer is excluded from screenshots, recordings, and
///    mirroring by the OS. Re-parenting the window's layer under a hidden
///    `UITextField` with `isSecureTextEntry = true` (the widely used
///    technique behind packages like ScreenProtectorKit / screen_protector)
///    therefore blanks the app's content in any capture while leaving it
///    visible on the device itself.
///  * **App-switcher snapshot**: the capture shield does not reliably cover
///    the snapshot iOS takes when the app resigns active, so this
///    controller additionally overlays an opaque cover while secure mode is
///    on, driven by the will-resign-active / did-become-active
///    notifications (observed here rather than in `SceneDelegate`:
///    `FlutterSceneDelegate` implements the scene lifecycle callbacks
///    without declaring them in its public header, so a Swift subclass
///    cannot `override` them and call `super` — shadowing them would
///    silently break plugin lifecycle forwarding).
///
/// Like the Dart side (`FlutterSecureScreenChannel`), every path here is
/// best-effort hardening: failures degrade to "no protection", never to a
/// crash or a blocked app.
final class SecureScreenController: NSObject {
  static let shared = SecureScreenController()

  private override init() {
    super.init()
    // `UIApplication` activity notifications still fire in scene-based
    // apps, and observing them here keeps the whole feature in one place
    // (see the doc comment above for why SceneDelegate overrides are not
    // an option).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  @objc private func applicationWillResignActive() {
    guard isSecureEnabled, let window = keyWindow else { return }
    showPrivacyCover(on: window)
  }

  @objc private func applicationDidBecomeActive() {
    hidePrivacyCover()
  }

  private var captureShieldField: UITextField?
  private weak var protectedWindow: UIWindow?
  private var privacyCover: UIView?
  private(set) var isSecureEnabled = false

  private var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  func setSecure(_ enabled: Bool) {
    isSecureEnabled = enabled
    guard let window = keyWindow else { return }
    installCaptureShieldIfNeeded(on: window)
    // Toggling `isSecureTextEntry` is what actually turns the capture
    // shield on/off; the layer re-parenting stays in place either way.
    captureShieldField?.isSecureTextEntry = enabled
    if !enabled {
      hidePrivacyCover()
    }
  }

  private func installCaptureShieldIfNeeded(on window: UIWindow) {
    if captureShieldField != nil, protectedWindow === window { return }

    let field = UITextField()
    field.isUserInteractionEnabled = false
    field.backgroundColor = .clear
    // The field must exactly cover the window: after the re-parenting
    // below, the window's layer is positioned in the field's coordinate
    // space, so any offset/size mismatch shifts the entire app's rendering
    // (seen as the app drawing in one quarter of the screen when the field
    // was centered with its tiny intrinsic size).
    field.frame = window.bounds
    field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(field)
    window.layer.superlayer?.addSublayer(field.layer)
    // The window's layer must become a child of the text field's internal
    // canvas layer for the OS capture exclusion to apply; which sublayer
    // hosts the canvas moved in iOS 17.
    if #available(iOS 17.0, *) {
      field.layer.sublayers?.last?.addSublayer(window.layer)
    } else {
      field.layer.sublayers?.first?.addSublayer(window.layer)
    }

    captureShieldField = field
    protectedWindow = window
  }

  /// Covers the given window with an opaque view so the app-switcher
  /// snapshot shows no vault content while secure mode is on.
  private func showPrivacyCover(on window: UIWindow) {
    guard isSecureEnabled, privacyCover == nil else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .systemBackground
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  private func hidePrivacyCover() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
