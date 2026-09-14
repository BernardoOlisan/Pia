import Foundation
import Security

public enum Secrets {
    public static let keychainService = "pia-voice"
    public static let keychainAccount = "openai"

    /// The OpenAI key: macOS Keychain first (`security add-generic-password -s pia-voice -a openai -w`),
    /// then the `OPENAI_API_KEY` environment variable.
    public static func openAIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty { return env }
        return nil
    }
}
