import Foundation

/// The four visual states of the notch surface.
///
/// State precedence (highest wins):
/// `expanded` (user intent) > interruption-driven `peek` > `live` > `idle`.
public enum NotchVisualState: String, Sendable, Equatable {
    /// Nothing important is happening. The surface visually disappears into
    /// the physical notch.
    case idle

    /// A short-lived interruption briefly expands the notch.
    case peek

    /// A persistent activity (Pomodoro, Now Playing, Claude working) shows a
    /// compact live indicator beside the notch.
    case live

    /// The user intentionally opened the notch into the Screen pager.
    case expanded
}
