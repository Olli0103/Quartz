import SwiftUI

/// Compact status indicator for the Intelligence Engine.
///
/// Displays the current engine state with a subtle, non-intrusive design:
/// - Idle: Hidden or minimal indicator
/// - Active: Animated progress with description
/// - Complete: Brief success state, then fades
///
/// Respects `@Environment(\.accessibilityReduceMotion)` for animations.
public struct IntelligenceStatusView: View {
    let status: IntelligenceEngineStatus
    let style: DisplayStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public enum DisplayStyle {
        /// Compact pill for sidebar (minimal footprint)
        case compact
        /// Expanded view for inspector panel (more detail)
        case expanded
    }

    public init(status: IntelligenceEngineStatus, style: DisplayStyle = .compact) {
        self.status = status
        self.style = style
    }

    public var body: some View {
        switch style {
        case .compact:
            compactView
        case .expanded:
            expandedView
        }
    }

    // MARK: - Compact View (Sidebar)

    @ViewBuilder
    private var compactView: some View {
        if status.isActive {
            HStack(spacing: 6) {
                statusIcon
                    .font(.caption2)

                if let fraction = status.progressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 40)
                        .tint(statusColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.1))
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    // MARK: - Expanded View (Inspector)

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusIcon
                    .font(.subheadline)

                Text(status.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if let fraction = status.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(statusColor.opacity(0.06))
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status)
    }

    // MARK: - Components

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.secondary)

        case .indexing:
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(QuartzColors.accent)
                .symbolEffect(.pulse.byLayer, options: .repeating)

        case .analyzing:
            Image(systemName: "sparkles")
                .foregroundStyle(QuartzColors.canvasPurple)
                .symbolEffect(.pulse.byLayer, options: .repeating)

        case .extracting:
            Image(systemName: "brain.head.profile")
                .foregroundStyle(QuartzColors.folderYellow)
                .symbolEffect(.pulse.byLayer, options: .repeating)

        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle, .complete:
            return .secondary
        case .indexing:
            return QuartzColors.accent
        case .analyzing:
            return QuartzColors.canvasPurple
        case .extracting:
            return QuartzColors.folderYellow
        case .error:
            return .red
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Intelligence Status - States") {
    VStack(spacing: 20) {
        IntelligenceStatusView(status: .idle, style: .expanded)
        IntelligenceStatusView(status: .indexing(progress: 45, total: 100), style: .expanded)
        IntelligenceStatusView(status: .analyzing, style: .expanded)
        IntelligenceStatusView(status: .extracting(progress: 12, total: 50, currentNote: "Meeting Notes"), style: .expanded)
        IntelligenceStatusView(status: .complete, style: .expanded)
        IntelligenceStatusView(status: .error(message: "Network unavailable"), style: .expanded)

        Divider()

        HStack(spacing: 16) {
            IntelligenceStatusView(status: .indexing(progress: 45, total: 100), style: .compact)
            IntelligenceStatusView(status: .analyzing, style: .compact)
        }
    }
    .padding()
}
#endif
