import Foundation

/// Installs and removes Glance's Claude Code hooks in `~/.claude/settings.json`.
///
/// Safety rules (all enforced here and covered by tests):
/// - The existing settings file is backed up before any modification
///   (`settings.json.glance-backup-<timestamp>`).
/// - Only hook entries whose command references the Glance spool directory
///   are ever added or removed; every other byte of the user's settings is
///   preserved (the file is edited via JSONSerialization, not re-modeled).
/// - Uninstall removes exactly the entries install added.
/// - Prompt privacy: the UserPromptSubmit and PreToolUse hook commands
///   redirect stdin to /dev/null and create empty marker files — prompt and
///   tool contents never touch disk.
public struct ClaudeCodeHookInstaller: Sendable {
    public let claudeSettingsURL: URL
    public let spoolDirectoryURL: URL

    public static func defaultSpoolDirectory() -> URL {
        SettingsStore.defaultFileURL().deletingLastPathComponent()
            .appendingPathComponent("claude-code-events", isDirectory: true)
    }

    public init(
        claudeSettingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"),
        spoolDirectoryURL: URL = ClaudeCodeHookInstaller.defaultSpoolDirectory()
    ) {
        self.claudeSettingsURL = claudeSettingsURL
        self.spoolDirectoryURL = spoolDirectoryURL
    }

    public enum InstallError: Error, Equatable {
        case settingsNotJSON
        case writeFailed(String)
    }

    /// The hook definitions Glance installs. `mktemp` gives each event file
    /// a unique name; `|| true` guarantees hooks never block Claude Code.
    ///
    /// Returned as (hookEventName, command) pairs.
    public func hookDefinitions() -> [(event: String, command: String)] {
        let dir = spoolDirectoryURL.path
        func write(_ name: String) -> String {
            "mkdir -p '\(dir)' && cat > \"$(mktemp '\(dir)/\(name)-XXXXXX.json')\" || true"
        }
        func marker(_ name: String) -> String {
            "mkdir -p '\(dir)' && cat > /dev/null && mktemp '\(dir)/\(name)-XXXXXX.marker' > /dev/null || true"
        }
        return [
            ("SessionStart", write("sessionstart")),
            ("UserPromptSubmit", marker("prompt")),   // stdin (the prompt) is discarded
            ("PreToolUse", marker("tool")),           // stdin (tool input) is discarded
            ("Notification", write("notification")),
            ("Stop", write("stop")),
            ("SessionEnd", write("sessionend")),
        ]
    }

    public var isInstalled: Bool {
        guard let root = readSettings() else { return false }
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            guard let matchers = value as? [[String: Any]] else { return false }
            return matchers.contains { containsGlanceHook($0) }
        }
    }

    /// A human-readable preview of what install will change, shown in
    /// Settings before the user confirms.
    public func installPreview() -> String {
        let lines = hookDefinitions().map { "\($0.event): \($0.command)" }
        return """
        Glance will add the following hooks to \(claudeSettingsURL.path)
        (a backup is created first; existing hooks are preserved):

        \(lines.joined(separator: "\n"))
        """
    }

    @discardableResult
    public func install() throws -> URL? {
        try FileManager.default.createDirectory(at: spoolDirectoryURL, withIntermediateDirectories: true)

        var root: [String: Any]
        var backupURL: URL?
        if FileManager.default.fileExists(atPath: claudeSettingsURL.path) {
            guard let existing = readSettings() else { throw InstallError.settingsNotJSON }
            root = existing
            backupURL = try backup()
        } else {
            root = [:]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for definition in hookDefinitions() {
            var matchers = hooks[definition.event] as? [[String: Any]] ?? []
            // Idempotent: drop any previous Glance entry for this event first.
            matchers.removeAll { containsGlanceHook($0) }
            matchers.append([
                "hooks": [
                    ["type": "command", "command": definition.command]
                ]
            ])
            hooks[definition.event] = matchers
        }
        root["hooks"] = hooks
        try writeSettings(root)
        return backupURL
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path),
              var root = readSettings() else { return }
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        _ = try backup()
        for (event, value) in hooks {
            guard var matchers = value as? [[String: Any]] else { continue }
            matchers.removeAll { containsGlanceHook($0) }
            if matchers.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = matchers
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeSettings(root)
        // Leave the spool directory; it may hold undelivered events.
    }

    // MARK: Internals

    /// A matcher entry belongs to Glance iff one of its commands references
    /// our spool directory.
    private func containsGlanceHook(_ matcher: [String: Any]) -> Bool {
        guard let hookList = matcher["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { ($0["command"] as? String)?.contains(spoolDirectoryURL.path) == true }
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeSettingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeSettings(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: claudeSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: claudeSettingsURL, options: .atomic)
    }

    private func backup() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = claudeSettingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.glance-backup-\(stamp)")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: claudeSettingsURL, to: backupURL)
        return backupURL
    }
}
