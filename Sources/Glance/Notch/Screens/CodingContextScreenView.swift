import GlanceKit
import SwiftUI

/// The optional Coding Context Screen: current coding session plus a
/// lightweight daily summary. Not a dashboard.
struct CodingContextScreenView: View {
    @EnvironmentObject var codingContext: CodingContextProvider
    @EnvironmentObject var history: ContextHistoryStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 10) {
            Text("CODING")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(Color.cyan.opacity(0.9))

            if let session = codingContext.session {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    VStack(spacing: 5) {
                        Text(TimeFormatting.hoursMinutes(timeline.date.timeIntervalSince(session.startedAt)))
                            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        if settings.settings.codingContext.showCurrentApplication {
                            Text(session.appName)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Not coding right now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            if settings.settings.context.isEnabled {
                todaySummary
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var todaySummary: some View {
        let summary = history.todaySummary()
        let coding = summary.filter { $0.kind == .coding }.reduce(0.0) { $0 + $1.duration }
        let focus = summary.filter { $0.kind == .focus }.reduce(0.0) { $0 + $1.duration }
        if coding > 0 || focus > 0 {
            HStack(spacing: 18) {
                if coding > 0 {
                    summaryItem(label: "Today", value: TimeFormatting.hoursMinutes(coding))
                }
                if focus > 0 {
                    summaryItem(label: "Focus", value: TimeFormatting.hoursMinutes(focus))
                }
            }
            .padding(.top, 2)
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
