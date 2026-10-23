import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(name: "com.magicai.mobile/secure", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let key = args["key"] as? String ?? ""
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.magicai.mobile", kSecAttrAccount as String: key]
      switch call.method {
      case "read":
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil) }
        else if status == errSecSuccess, let bytes = item as? Data { result(String(data: bytes, encoding: .utf8)) }
        else { result(FlutterError(code: "keychain", message: "Unlock your Keychain to continue.", details: nil)) }
      case "write":
        guard let value = args["value"] as? String else { result(FlutterError(code: "value", message: "Invalid secure value", details: nil)); return }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var add = query
          add[kSecValueData as String] = data
          status = SecItemAdd(add as CFDictionary, nil)
        }
        result(status == errSecSuccess ? nil : FlutterError(code: "keychain", message: "Unable to save your secure session.", details: nil))
      case "delete":
        let status = SecItemDelete(query as CFDictionary)
        result(status == errSecSuccess || status == errSecItemNotFound ? nil : FlutterError(code: "keychain", message: "Unable to remove your secure session.", details: nil))
      default: result(FlutterMethodNotImplemented)
      }
    }


    super.awakeFromNib()
  }
}
