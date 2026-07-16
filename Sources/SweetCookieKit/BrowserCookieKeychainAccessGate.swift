import Foundation

#if os(macOS)
/// Opt-in switch for disabling Keychain access in host apps.
public enum BrowserCookieKeychainAccessGate {
    public nonisolated(unsafe) static var isDisabled: Bool = false

    /// Controls whether Chromium cookie decryption may promote a no-UI Keychain read to an interactive one.
    ///
    /// The secure default keeps background imports non-interactive. Hosts that have obtained user intent can
    /// opt in for the duration of a specific import with ``withUserInteractionAllowed(_:)``.
    @TaskLocal public static var isUserInteractionAllowed = false

    /// Runs an operation that may request user interaction from macOS Keychain.
    public static func withUserInteractionAllowed<T>(_ operation: () throws -> T) rethrows -> T {
        try self.$isUserInteractionAllowed.withValue(true) {
            try operation()
        }
    }
}
#endif
