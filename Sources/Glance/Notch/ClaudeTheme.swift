import SwiftUI

/// Shared visual identity for "a Claude Code session is active" states,
/// kept in one place so the notch, the peek indicator, and the Claude
/// Screen never drift out of sync with each other.
extension Color {
    /// Anthropic's Claude brand accent (a warm clay/terracotta), used
    /// instead of a generic system tint whenever the notch is reflecting
    /// live Claude Code activity.
    static let claudeAccent = Color(red: 0.851, green: 0.467, blue: 0.341)
}
