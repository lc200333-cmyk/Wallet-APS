import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWalletChannels(flutterViewController)

    super.awakeFromNib()
  }

  // Subset of the native channels that the Dart side calls on macOS; other
  // methods report "not implemented".
  private func registerWalletChannels(_ controller: FlutterViewController) {
    let messenger = controller.engine.binaryMessenger

    FlutterMethodChannel(name: "wallet_aps/spb_wallet", binaryMessenger: messenger)
      .setMethodCallHandler { [weak controller] call, result in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "getLaunchWallet":
          result(nil)
        case "openExternalUri":
          guard let text = args?["uri"] as? String, let url = URL(string: text) else {
            result(false)
            return
          }
          result(NSWorkspace.shared.open(url))
        case "openFile":
          guard let path = args?["path"] as? String else {
            result(false)
            return
          }
          result(NSWorkspace.shared.open(URL(fileURLWithPath: path)))
        case "shareFile":
          guard let path = args?["path"] as? String, let view = controller?.view else {
            result(false)
            return
          }
          let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
          let anchor = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
          picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterMethodChannel(name: "wallet_aps/window", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "readClipboardImage":
          let pasteboard = NSPasteboard.general
          if let png = pasteboard.data(forType: .png) {
            result(FlutterStandardTypedData(bytes: png))
          } else if let image = NSImage(pasteboard: pasteboard),
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
          {
            result(FlutterStandardTypedData(bytes: png))
          } else {
            result(nil)
          }
        case "writeClipboardImage":
          guard let data = call.arguments as? FlutterStandardTypedData else {
            result(FlutterError(code: "bad_image", message: "Invalid image", details: nil))
            return
          }
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.setData(data.data, forType: .png)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
