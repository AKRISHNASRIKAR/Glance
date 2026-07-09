import Foundation

/// Executes small AppleScript snippets on a dedicated serial queue.
///
/// Why AppleScript: macOS has no public API for reading another app's
/// playback state or controlling it. The private MediaRemote framework is
/// deliberately NOT used (see docs/NOW_PLAYING.md). Apple Music and Spotify
/// both ship stable, documented scripting interfaces; scripting requires the
/// user-granted Automation permission (NSAppleEventsUsageDescription), which
/// macOS prompts for on first use.
///
/// NSAppleScript is not thread-safe; every instance here is confined to one
/// serial queue for its whole life, which is the supported usage pattern.
public final class ScriptRunner: @unchecked Sendable {
    public static let shared = ScriptRunner()

    private let queue = DispatchQueue(label: "app.glance.scripting", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    public init() {}

    public struct ScriptError: Error, Sendable {
        public let code: Int
        public let message: String
        /// -1743 is errAEEventNotPermitted: the user declined Automation access.
        public var isPermissionDenied: Bool { code == -1743 }
    }

    /// Run a script, returning its result descriptor. Compiled scripts are
    /// cached by source text.
    public func run(_ source: String) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                let script: NSAppleScript
                if let cached = compiled[source] {
                    script = cached
                } else if let fresh = NSAppleScript(source: source) {
                    compiled[source] = fresh
                    script = fresh
                } else {
                    continuation.resume(throwing: ScriptError(code: -1, message: "Script failed to compile"))
                    return
                }
                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                    continuation.resume(throwing: ScriptError(code: code, message: message))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Convenience: run and ignore failures (for fire-and-forget commands).
    @discardableResult
    public func runIgnoringResult(_ source: String) async -> Bool {
        do {
            _ = try await run(source)
            return true
        } catch {
            GlanceLog.nowPlaying.debug("Script command failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
