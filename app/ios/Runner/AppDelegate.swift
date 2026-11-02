import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var documentController: UIDocumentInteractionController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WalletApsChannels")
    else { return }
    let messenger = registrar.messenger()

    // Subset of the Android `wallet_aps/spb_wallet` channel that the Dart side
    // calls on iOS; other methods report "not implemented".
    FlutterMethodChannel(name: "wallet_aps/spb_wallet", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "getLaunchWallet":
          result(nil)
        case "openExternalUri":
          guard let text = args?["uri"] as? String, let url = URL(string: text) else {
            result(false)
            return
          }
          UIApplication.shared.open(url) { opened in result(opened) }
        case "openFile":
          guard let path = args?["path"] as? String else {
            result(false)
            return
          }
          result(self?.previewFile(URL(fileURLWithPath: path)) ?? false)
        case "shareFile":
          guard let path = args?["path"] as? String else {
            result(false)
            return
          }
          result(self?.shareFile(URL(fileURLWithPath: path)) ?? false)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterMethodChannel(name: "wallet_aps/window", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "readClipboardImage":
          if let image = UIPasteboard.general.image, let png = image.pngData() {
            result(FlutterStandardTypedData(bytes: png))
          } else {
            result(nil)
          }
        case "writeClipboardImage":
          guard let data = call.arguments as? FlutterStandardTypedData,
            let image = UIImage(data: data.data)
          else {
            result(FlutterError(code: "bad_image", message: "Invalid image", details: nil))
            return
          }
          UIPasteboard.general.image = image
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var controller = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private func previewFile(_ url: URL) -> Bool {
    guard let controller = topViewController() else { return false }
    let interaction = UIDocumentInteractionController(url: url)
    documentController = interaction
    let anchor = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
    return interaction.presentOpenInMenu(from: anchor, in: controller.view, animated: true)
  }

  private func shareFile(_ url: URL) -> Bool {
    guard let controller = topViewController() else { return false }
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(
        x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    controller.present(activity, animated: true)
    return true
  }
}
