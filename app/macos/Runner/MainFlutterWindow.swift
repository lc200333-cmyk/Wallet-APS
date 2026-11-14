import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private let vaultDocuments = MacVaultDocuments()

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
      .setMethodCallHandler { [weak self, weak controller] call, result in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "getLaunchWallet":
          result(nil)
        case "pickSpbWallet":
          guard let window = self else {
            result(FlutterError(code: "no_ui", message: "No application window", details: nil))
            return
          }
          self?.vaultDocuments.pick(from: window, result: result)
        case "copySpbWallet":
          guard let uri = args?["uri"] as? String else {
            result(FlutterError(code: "bad_args", message: "Missing uri", details: nil))
            return
          }
          self?.vaultDocuments.copy(
            uri: uri, displayName: args?["displayName"] as? String, result: result)
        case "writeSpbWallet":
          guard let uri = args?["uri"] as? String,
            let localPath = args?["localPath"] as? String
          else {
            result(FlutterError(
              code: "bad_args", message: "Missing uri or localPath", details: nil))
            return
          }
          self?.vaultDocuments.write(uri: uri, localPath: localPath, result: result)
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

/// Keeps access to a sandboxed, user-selected vault across app restarts.
/// SQLite works on an app-owned copy; saves are coordinated back to the file
/// represented by the security-scoped bookmark.
final class MacVaultDocuments {
  private static let uriPrefix = "macos-bookmark:"
  private static let sqliteHeader = Data("SQLite format 3\u{0}".utf8)
  private let ioQueue = DispatchQueue(label: "wallet_aps.macos_vault_io")

  func pick(from window: NSWindow, result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = Self.walletContentTypes
    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      self.ioQueue.async {
        do {
          let uri = try Self.bookmark(for: url)
          let map = try Self.workingCopy(of: url, uri: uri, displayName: nil)
          DispatchQueue.main.async { result(map) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "pick_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  func copy(uri: String, displayName: String?, result: @escaping FlutterResult) {
    ioQueue.async {
      do {
        let url = try Self.resolve(uri)
        let map = try Self.workingCopy(of: url, uri: uri, displayName: displayName)
        DispatchQueue.main.async { result(map) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "copy_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func write(uri: String, localPath: String, result: @escaping FlutterResult) {
    ioQueue.async {
      do {
        try Self.writeBack(uri: uri, localPath: localPath)
        DispatchQueue.main.async { result(true) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "write_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static var walletContentTypes: [UTType] {
    var types = [UTType(filenameExtension: "swl") ?? .data]
    for ext in ["db", "sqlite"] {
      if let type = UTType(filenameExtension: ext) { types.append(type) }
    }
    return types
  }

  private static func withAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
    guard url.startAccessingSecurityScopedResource() else {
      throw VaultAccessError("The saved file permission is no longer available")
    }
    defer { url.stopAccessingSecurityScopedResource() }
    return try body()
  }

  private static func bookmark(for url: URL) throws -> String {
    let data = try withAccess(to: url) {
      try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
    }
    return uriPrefix + data.base64EncodedString()
  }

  private static func resolve(_ uri: String) throws -> URL {
    guard uri.hasPrefix(uriPrefix),
      let data = Data(base64Encoded: String(uri.dropFirst(uriPrefix.count)))
    else { throw VaultAccessError("Unknown file reference") }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &stale)
    if stale {
      throw VaultAccessError("The saved file permission is stale; select the file again")
    }
    return url
  }

  private static func coordinate(
    _ url: URL, writing: Bool, _ body: (URL) throws -> Void
  ) throws {
    var coordinatorError: NSError?
    var bodyError: Error?
    let coordinator = NSFileCoordinator()
    if writing {
      coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) {
        do { try body($0) } catch { bodyError = error }
      }
    } else {
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) {
        do { try body($0) } catch { bodyError = error }
      }
    }
    if let error = coordinatorError ?? bodyError { throw error }
  }

  private static func workingCopy(
    of url: URL, uri: String, displayName: String?
  ) throws -> [String: Any] {
    try withAccess(to: url) {
      let name = displayName?.isEmpty == false ? displayName! : url.lastPathComponent
      let caches = try FileManager.default.url(
        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let local = caches.appendingPathComponent(
        "spbwallet_\(Int(Date().timeIntervalSince1970 * 1000))_\(safeName(name))")
      try coordinate(url, writing: false) { readURL in
        try Data(contentsOf: readURL).write(to: local, options: .atomic)
      }
      guard isValidWallet(try Data(contentsOf: local)) else {
        try? FileManager.default.removeItem(at: local)
        throw VaultAccessError("The selected file is empty or is not a wallet database")
      }
      return [
        "uri": uri,
        "localPath": local.path,
        "displayName": name,
        "displayPath": url.path,
        "writable": FileManager.default.isWritableFile(atPath: url.path),
        "persisted": true,
        "recovered": false,
      ]
    }
  }

  private static func writeBack(uri: String, localPath: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
    guard isValidWallet(data) else {
      throw VaultAccessError("The wallet working copy is empty or damaged")
    }
    let url = try resolve(uri)
    try withAccess(to: url) {
      try coordinate(url, writing: true) { target in
        do {
          try data.write(to: target, options: .atomic)
        } catch {
          try data.write(to: target)
        }
        guard try Data(contentsOf: target) == data else {
          throw VaultAccessError("The wallet file was not written completely")
        }
      }
    }
  }

  private static func isValidWallet(_ data: Data) -> Bool {
    data.count >= sqliteHeader.count && data.prefix(sqliteHeader.count) == sqliteHeader
  }

  private static func safeName(_ value: String) -> String {
    let sanitized = value.replacingOccurrences(
      of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
    return sanitized.isEmpty ? "wallet.swl" : sanitized
  }
}

private struct VaultAccessError: LocalizedError {
  init(_ message: String) { self.message = message }
  let message: String
  var errorDescription: String? { message }
}
