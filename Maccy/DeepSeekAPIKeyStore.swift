import Foundation
import Security

enum DeepSeekAPIKeyStore {
  private static let service = Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy"
  private static let account = "DeepSeekAPIKey"

  static var apiKey: String {
    get { read() ?? "" }
    set { save(newValue) }
  }

  private static func read() -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  private static func save(_ apiKey: String) {
    let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedAPIKey.isEmpty else {
      SecItemDelete(baseQuery() as CFDictionary)
      return
    }

    let data = Data(trimmedAPIKey.utf8)
    let attributes = [kSecValueData as String: data]
    let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)

    guard status == errSecItemNotFound else {
      return
    }

    var query = baseQuery()
    query[kSecValueData as String] = data
    SecItemAdd(query as CFDictionary, nil)
  }

  private static func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}
