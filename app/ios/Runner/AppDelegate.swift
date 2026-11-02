import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var documentController: UIDocumentInteractionController?
  private let vaultDocuments = VaultDocuments()

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
        case "pickSpbWallet":
          guard let controller = self?.topViewController() else {
            result(FlutterError(code: "no_ui", message: "No view controller", details: nil))
            return
          }
          self?.vaultDocuments.pick(from: controller, result: result)
        case "createSpbWalletDocument":
          guard let controller = self?.topViewController() else {
            result(FlutterError(code: "no_ui", message: "No view controller", details: nil))
            return
          }
          let name = args?["displayName"] as? String ?? "wallet.swl"
          self?.vaultDocuments.create(displayName: name, from: controller, result: result)
        case "copySpbWallet":
          guard let uri = args?["uri"] as? String else {
            result(FlutterError(code: "bad_args", message: "Missing uri", details: nil))
            return
          }
          self?.vaultDocuments.copy(uri: uri, displayName: args?["displayName"] as? String, result: result)
        case "writeSpbWallet":
          guard let uri = args?["uri"] as? String, let localPath = args?["localPath"] as? String
          else {
            result(FlutterError(code: "bad_args", message: "Missing uri or localPath", details: nil))
            return
          }
          self?.vaultDocuments.write(uri: uri, localPath: localPath, result: result)
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

/// iOS counterpart of the Android document-provider vault flow: the user picks
/// a file once, a security-scoped bookmark keeps access to it, the app edits a
/// local working copy and every save writes that copy back to the original.
final class VaultDocuments: NSObject, UIDocumentPickerDelegate {
  private static let uriPrefix = "ios-bookmark:"
  private static let sqliteHeader = Data("SQLite format 3\u{0}".utf8)

  private var pendingResult: FlutterResult?
  private var pendingIsCreate = false
  private let ioQueue = DispatchQueue(label: "wallet_aps.vault_io")

  func pick(from controller: UIViewController, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "File picker is already open", details: nil))
      return
    }
    var types: [UTType] = [UTType("com.lc200333cmyk.walletaps.swl") ?? .data]
    for ext in ["db", "sqlite"] {
      if let type = UTType(filenameExtension: ext) { types.append(type) }
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    present(picker, from: controller, isCreate: false, result: result)
  }

  func create(displayName: String, from controller: UIViewController, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "File picker is already open", details: nil))
      return
    }
    do {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("new_vault_\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let placeholder = directory.appendingPathComponent(Self.safeName(displayName))
      try Data().write(to: placeholder)
      let picker = UIDocumentPickerViewController(forExporting: [placeholder], asCopy: false)
      present(picker, from: controller, isCreate: true, result: result)
    } catch {
      result(FlutterError(code: "create_failed", message: error.localizedDescription, details: nil))
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
          result(FlutterError(code: "copy_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func write(uri: String, localPath: String, result: @escaping FlutterResult) {
    // Saves also run when the app goes to the background; ask iOS for time to
    // finish so the original file is not left half-written.
    var task = UIBackgroundTaskIdentifier.invalid
    task = UIApplication.shared.beginBackgroundTask(withName: "WalletApsVaultWrite") {
      UIApplication.shared.endBackgroundTask(task)
      task = .invalid
    }
    ioQueue.async {
      var outcome: Any = true
      do {
        try Self.writeBack(uri: uri, localPath: localPath)
      } catch {
        outcome = FlutterError(code: "write_failed", message: error.localizedDescription, details: nil)
      }
      DispatchQueue.main.async {
        result(outcome)
        if task != .invalid {
          UIApplication.shared.endBackgroundTask(task)
          task = .invalid
        }
      }
    }
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingResult else { return }
    let isCreate = pendingIsCreate
    pendingResult = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    ioQueue.async {
      do {
        let uri = try Self.bookmark(for: url)
        let map: [String: Any?]
        if isCreate {
          map = try Self.withAccess(to: url) {
            [
              "uri": uri,
              "displayName": url.lastPathComponent,
              "displayPath": Self.displayPath(of: url),
              "writable": true,
              "persisted": true,
            ]
          }
        } else {
          map = try Self.workingCopy(of: url, uri: uri, displayName: nil)
        }
        DispatchQueue.main.async { result(map) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  // MARK: - Helpers

  private func present(
    _ picker: UIDocumentPickerViewController, from controller: UIViewController,
    isCreate: Bool, result: @escaping FlutterResult
  ) {
    pendingResult = result
    pendingIsCreate = isCreate
    picker.delegate = self
    picker.allowsMultipleSelection = false
    controller.present(picker, animated: true)
  }

  private static func withAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    return try body()
  }

  private static func bookmark(for url: URL) throws -> String {
    let data = try withAccess(to: url) {
      try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    return uriPrefix + data.base64EncodedString()
  }

  private static func resolve(_ uri: String) throws -> URL {
    guard uri.hasPrefix(uriPrefix),
      let data = Data(base64Encoded: String(uri.dropFirst(uriPrefix.count)))
    else { throw VaultError("Unknown file reference") }
    var stale = false
    return try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
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

  private static func workingCopy(of url: URL, uri: String, displayName: String?) throws -> [String: Any?] {
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
        throw VaultError("Выбранный файл пуст или не является базой")
      }
      return [
        "uri": uri,
        "localPath": local.path,
        "displayName": name,
        "displayPath": displayPath(of: url),
        "writable": FileManager.default.isWritableFile(atPath: url.path),
        "persisted": true,
        "recovered": false,
      ]
    }
  }

  private static func writeBack(uri: String, localPath: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
    guard isValidWallet(data) else {
      throw VaultError("Рабочая копия базы пуста или повреждена")
    }
    let url = try resolve(uri)
    try withAccess(to: url) {
      try coordinate(url, writing: true) { target in
        // Keep the previous contents so a failed write can be recovered.
        if let previous = try? Data(contentsOf: target), isValidWallet(previous) {
          try? saveRecoveryCopy(previous, name: target.lastPathComponent)
        }
        do {
          try data.write(to: target, options: .atomic)
        } catch {
          // Some file providers only grant access to the file itself, not to
          // its folder, so an atomic temp-file replacement is not possible.
          try data.write(to: target)
        }
        guard try Data(contentsOf: target) == data else {
          throw VaultError("Файл базы записан не полностью")
        }
      }
    }
  }

  private static func saveRecoveryCopy(_ data: Data, name: String) throws {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = support.appendingPathComponent("ios-vault-recovery", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: directory.appendingPathComponent(safeName(name)), options: .atomic)
  }

  private static func isValidWallet(_ data: Data) -> Bool {
    data.count >= sqliteHeader.count && data.prefix(sqliteHeader.count) == sqliteHeader
  }

  private static func displayPath(of url: URL) -> String {
    let folder = url.deletingLastPathComponent().lastPathComponent
    return folder.isEmpty ? url.lastPathComponent : "\(folder)/\(url.lastPathComponent)"
  }

  private static func safeName(_ name: String) -> String {
    let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
    return cleaned.isEmpty ? "wallet.swl" : cleaned
  }
}

private struct VaultError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}
