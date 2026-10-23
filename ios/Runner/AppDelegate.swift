import Photos
import Flutter
import UIKit
import Security
import CryptoKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  static var authReturn: [String: String]?
  private var fileResult: FlutterResult?

  static func receive(_ url: URL) {
    guard url.scheme == "magicai", url.host == "auth", url.path == "/complete",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
    var values: [String: String] = [:]
    for item in components.queryItems ?? [] { values[item.name] = item.value }
    authReturn = values
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    AppDelegate.receive(url)
    return url.scheme == "magicai" || super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "com.magicai.mobile/secure", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "unavailable", message: "Application unavailable", details: nil)); return }
      let args = call.arguments as? [String: Any] ?? [:]
      let key = args["key"] as? String ?? ""
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.magicai.mobile", kSecAttrAccount as String: key]
      switch call.method {
      case "read":
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil) }
        else if status == errSecSuccess, let data = item as? Data { result(String(data: data, encoding: .utf8)) }
        else { result(FlutterError(code: "keychain", message: "Unlock the device to continue.", details: nil)) }
      case "write":
        guard let value = args["value"] as? String else { result(FlutterError(code: "value", message: "Invalid secure value", details: nil)); return }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          status = SecItemAdd(add as CFDictionary, nil)
        }
        result(status == errSecSuccess ? nil : FlutterError(code: "keychain", message: "Unable to securely save your session.", details: nil))
      case "delete": SecItemDelete(query as CFDictionary); result(nil)
      case "openUrl":
        guard let value = args["url"] as? String, let url = URL(string: value), url.scheme == "https" else { result(FlutterError(code: "url", message: "Invalid address", details: nil)); return }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened ? nil : FlutterError(code: "browser", message: "Unable to open browser", details: nil)) }
      case "createLoginProof":
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { result(FlutterError(code: "random", message: "Secure login unavailable", details: nil)); return }
        func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let verifier = base64(Data(bytes)); let challenge = base64(Data(SHA256.hash(data: Data(verifier.utf8))))
        result(["verifier": verifier, "challenge": challenge])
      case "consumeAuthReturn": result(AppDelegate.authReturn); AppDelegate.authReturn = nil
      case "pickFile", "pickImage":
        guard self.fileResult == nil else { result(FlutterError(code: "busy", message: "A file picker is already open", details: nil)); return }
        self.fileResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: call.method == "pickImage" ? [.image] : [.pdf, .commaSeparatedText, .spreadsheet, .data], asCopy: true)
        picker.delegate = self
        let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        guard let root = root else { self.fileResult = nil; result(FlutterError(code: "picker", message: "Unable to open file picker", details: nil)); return }
        root.present(picker, animated: true)
      case "clearWebSession": result(nil)
      case "previewMedia":
        guard let value = args["url"] as? String, let url = URL(string: value), url.scheme == "https", url.host?.isEmpty == false, url.user == nil else { result(FlutterError(code: "url", message: "Invalid address", details: nil)); return }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened ? nil : FlutterError(code: "browser", message: "Unable to open media", details: nil)) }
      case "contactAction":
        let scheme = args["scheme"] as? String ?? ""
        let value = args["value"] as? String ?? ""
        guard ["tel", "mailto"].contains(scheme), value.count <= 255, !value.contains("\n"), !value.contains("\r"),
          let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "\(scheme):\(encoded)") else {
          result(FlutterError(code: "contact", message: "Invalid contact action", details: nil)); return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened ? nil : FlutterError(code: "contact", message: "No compatible app is available", details: nil)) }
      case "saveImageToGallery":
        guard let data = (args["bytes"] as? FlutterStandardTypedData)?.data, data.count <= 50 * 1024 * 1024, let image = UIImage(data: data) else {
          result(FlutterError(code: "image", message: "Unable to save this image", details: nil)); return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          guard status == .authorized || status == .limited else { DispatchQueue.main.async { result(FlutterError(code: "photos", message: "Allow photo access in Settings to save this image.", details: nil)) }; return }
          PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) }) { success, _ in
            DispatchQueue.main.async { result(success ? nil : FlutterError(code: "photos", message: "Unable to save this image.", details: nil)) }
          }
        }
      case "saveImage":
        guard let data = (args["bytes"] as? FlutterStandardTypedData)?.data, data.count <= 20 * 1024 * 1024, let image = UIImage(data: data) else {
          result(FlutterError(code: "image", message: "Unable to export this image", details: nil)); return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        result(nil)
      default: result(FlutterError(code: "unsupported", message: "This visual editor is not yet available on iOS.", details: nil))
      }
    }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { fileResult?(nil); fileResult = nil }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    defer { fileResult = nil }
    guard let url = urls.first else { fileResult?(nil); return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 50 * 1024 * 1024 else { fileResult?(FlutterError(code: "size", message: "Choose a file smaller than 50 MB", details: nil)); return }
      let bytes = try Data(contentsOf: url)
      fileResult?(["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: bytes)])
    } catch { fileResult?(FlutterError(code: "file", message: "Unable to read file", details: nil)) }
  }
}
