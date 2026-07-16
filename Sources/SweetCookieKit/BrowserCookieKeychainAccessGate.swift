import Foundation

#if os(macOS)
/// Opt-in switch for disabling Keychain access in host apps.
public enum BrowserCookieKeychainAccessGate {
    public nonisolated(unsafe) static var isDisabled: Bool = false

    /// Controls whether Chromium cookie decryption may promote a no-UI Keychain read to an interactive one.
    ///
    /// Interactive recovery remains the compatibility default. Hosts performing background work can suppress
    /// it for the duration of a specific import with ``withUserInteractionDisallowed(_:)``.
    @TaskLocal public static var isUserInteractionDisallowed = false

    /// Runs an operation that must not request user interaction from macOS Keychain.
    public static func withUserInteractionDisallowed<T>(_ operation: () throws -> T) rethrows -> T {
        try self.$isUserInteractionDisallowed.withValue(true) {
            try operation()
        }
    }
}
#endif
