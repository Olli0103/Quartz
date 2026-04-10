import SwiftUI

/// A compact floating capsule showing recording status, live transcript preview,
/// and controls, designed to overlay the editor during active recording.
///
/// Shows: expand button | timer | live transcript (~50 chars) | pause | stop
///
/// Accessibility:
/// - Combined accessibility element with descriptive label
/// - Timer announces via `.accessibilityValue`
/// - Respects Reduce Motion (no pulse animation)
/// - Dynamic Type support
///
/// - Linear: OLL-39 (Live Capsule UI — floating recorder)
public struct LiveCapsuleOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public let formattedDuration: String
    public let isPaused: Bool
    public let isRecording: Bool
    public let liveTranscript: String

    public let onExpand: () -> Void
    public let onTogglePause: () -> Void
    public let onStop: () -> Void

    public init(
        formattedDuration: String,
        isPaused: Bool,
        isRecording: Bool,
        liveTranscript: String = "",
        onExpand: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.formattedDuration = formattedDuration
        self.isPaused = isPaused
        self.isRecording = isRecording
        self.liveTranscript = liveTranscript
        self.onExpand = onExpand
        self.onTogglePause = onTogglePause
        self.onStop = onStop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if !liveTranscript.isEmpty {
                transcriptPreview
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(formattedDuration)
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 14) {
            Button {
                onExpand()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Expand to full view", bundle: .module))

            Text(formattedDuration)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            if isPaused {
                Text(String(localized: "Paused", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                recordingIndicator
            }

            Spacer()

            Button {
                onTogglePause()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused
                ? String(localized: "Resume recording", bundle: .module)
                : String(localized: "Pause recording", bundle: .module))

            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.red.gradient))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stop recording", bundle: .module))
            .accessibilityHint(String(localized: "Stops recording and processes audio", bundle: .module))
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .modifier(PulseModifier(isActive: !reduceMotion && isRecording && !isPaused))
    }

    // MARK: - Live Transcript Preview

    private var transcriptPreview: some View {
        Text(String(liveTranscript.suffix(80)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.top, 8)
            .accessibilityLabel(String(localized: "Live transcript", bundle: .module))
            .accessibilityValue(liveTranscript)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        if isPaused {
            return String(localized: "Recording paused at \(formattedDuration)", bundle: .module)
        } else if isRecording {
            return String(localized: "Recording in progress, \(formattedDuration)", bundle: .module)
        } else {
            return String(localized: "Recording stopped", bundle: .module)
        }
    }
}

// MARK: - Pulse Modifier

private struct PulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.3 : 1.0)
            .animation(
                isActive
                    ? .spring(duration: 1.0, bounce: 0.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: isActive) { _, newValue in
                isPulsing = newValue
            }
            .onAppear {
                isPulsing = isActive
            }
    }
}
