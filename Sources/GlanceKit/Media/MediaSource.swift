import AppKit
import Foundation

/// One observable media application (Apple Music, Spotify, …).
///
/// Sources are event-driven: they listen to the player's distributed
/// notification and only use Scripting for the initial snapshot, position
/// correction while the Now Playing Screen is open, artwork, and commands.
@MainActor
public protocol MediaSource: AnyObject {
    var kind: MediaSourceKind { get }
    /// nil means "no current track / player quit".
    var onStateChange: (@MainActor (MediaState?) -> Void)? { get set }

    func start()
    func stop()
    func perform(_ command: MediaCommand)
    /// Sample the true playback position via scripting (nil if unavailable).
    func fetchPosition() async -> TimeInterval?
    /// Fetch raw artwork bytes for the given state (nil if unavailable).
    func fetchArtwork(for state: MediaState) async -> Data?
}

/// Shared helper: is the player application currently running? Used to avoid
/// firing Apple Events (and TCC prompts) at apps that aren't open.
@MainActor
func isApplicationRunning(bundleIdentifier: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
}
