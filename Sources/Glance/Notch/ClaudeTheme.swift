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

/// Fills the complete notch shape, including its sensor row.
struct ClaudeBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [Color.claudeAccent.opacity(0.23), Color(red: 0.055, green: 0.035, blue: 0.055), Color(red: 0.18, green: 0.14, blue: 0.26).opacity(0.6)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .background(Color.black)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
