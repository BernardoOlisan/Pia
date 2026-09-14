import Foundation

public enum Secrets {
    public static let keychainService = "pia-voice"
    public static let keychainAccount = "openai"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// The OpenAI key: macOS Keychain first (`security add-generic-password -s pia-voice -a openai -w`),
    /// then the `OPENAI_API_KEY` environment variable.
    ///
    /// Read through `/usr/bin/security`, not the Security framework: the item was created by `security`, so it
    /// is already trusted. pia-voice itself is rebuilt on every change, and each build looks like a new app
    /// to the Keychain, which would ask for the login password again and again.
    public static func openAIKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        if let key = keychainKey() ?? environmentKey() {
            cached = key
            return key
        }
        return nil
    }

    private static func keychainKey() -> String? {
        let security = Process()
        security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        security.arguments = ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"]
        let output = Pipe()
        security.standardOutput = output
        security.standardError = FileHandle.nullDevice
        guard (try? security.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        security.waitUntilExit()
        guard security.terminationStatus == 0,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    private static func environmentKey() -> String? {
        guard let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty else { return nil }
        return env
    }
}
