import SwiftUI

/// All Pomodoro appearances share a full-notch, phase-colored atmosphere.
struct PomodoroArtworkBackgroundView: View {
    let tint: Color
    var reduceMotion: Bool = false

    var body: some View {
        LinearGradient(
            colors: [tint.opacity(0.36), Color(red: 0.045, green: 0.07, blue: 0.065), Color(red: 0.18, green: 0.14, blue: 0.26).opacity(0.65)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .background(Color.black)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: tint)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
