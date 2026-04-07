import SwiftUI
import AVFoundation

// MARK: - View Model

@Observable
@MainActor
public final class AudioRecordingViewModel {
    public enum Mode: String, CaseIterable {
        case transcription = "Transcription"
        case meetingMinutes = "Meeting Minutes"
    }

    var mode: Mode = .transcription
    var transcriptionEnabled = true
    var minutesTemplate: MeetingMinutesTemplate = .standard
    var customMinutesPrompt: String = ""
    var isTranscribing = false
    var transcriptionProgress: String = ""
    var errorMessage: String?
    var didFinish = false

    let recordingService = AudioRecordingService()

    private let transcriptionService = TranscriptionService()

    var vaultURL: URL?

    func startRecording() async {
        guard let vaultURL else {
            errorMessage = String(localized: "No vault selected.", bundle: .module)
            return
        }

        errorMessage = nil
        didFinish = false

        let granted = await recordingService.requestPermission()
        guard granted else {
            errorMessage = String(localized: "Microphone access denied. Please enable in Settings.", bundle: .module)
            return
        }

        do {
            try recordingService.startRecording(vaultURL: vaultURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async -> String? {
        do {
            let audioURL = try recordingService.stopRecording()

            guard transcriptionEnabled else {
                didFinish = true
                return nil
            }

            isTranscribing = true
            transcriptionProgress = String(localized: "Transcribing audio…", bundle: .module)

            if mode == .meetingMinutes {
                return try await generateMeetingMinutes(audioURL: audioURL)
            } else {
                return try await transcribeAudio(audioURL: audioURL)
            }
        } catch {
            errorMessage = error.localizedDescription
            isTranscribing = false
            return nil
        }
    }

    func togglePause() {
        if recordingService.isPaused {
            recordingService.resume()
        } else {
            recordingService.pause()
        }
    }

    func discardRecording() {
        recordingService.discardRecording()
        errorMessage = nil
        isTranscribing = false
        transcriptionProgress = ""
    }

    // MARK: - Private

    private func transcribeAudio(audioURL: URL) async throws -> String {
        let granted = await transcriptionService.requestPermission()
        guard granted else {
            isTranscribing = false
            throw TranscriptionService.TranscriptionError.permissionDenied
        }

        transcriptionProgress = String(localized: "Processing speech…", bundle: .module)
        let result = try await transcriptionService.transcribe(audioURL: audioURL)
        isTranscribing = false
        didFinish = true
        return result.text
    }

    private func generateMeetingMinutes(audioURL: URL) async throws -> String {
        transcriptionProgress = String(localized: "Transcribing audio…", bundle: .module)

        let minutesService = MeetingMinutesService(
            transcriptionService: transcriptionService,
            providerRegistry: AIProviderRegistry.shared
        )

        transcriptionProgress = String(localized: "Generating meeting minutes…", bundle: .module)
        let template = minutesTemplate
        let customPrompt = customMinutesPrompt
        let minutes = try await minutesService.generateMinutes(
            from: audioURL,
            template: template,
            customPrompt: template == .custom && !customPrompt.isEmpty ? customPrompt : nil
        )

        if let vaultURL {
            _ = try await minutesService.saveAsNote(minutes, vaultURL: vaultURL)
        }

        isTranscribing = false
        didFinish = true
        return minutes.toMarkdown()
    }
}

// MARK: - Audio Recording View

public struct AudioRecordingView: View {
    @State private var viewModel = AudioRecordingViewModel()
    @State private var showCompactPill = false
    @Environment(\.dismiss) private var dismiss

    private let vaultURL: URL?
    private let onInsertText: (String) -> Void
    private let compactMode: Bool
    private let initialMode: AudioRecordingViewModel.Mode?

    public init(
        vaultURL: URL?,
        onInsertText: @escaping (String) -> Void,
        compactMode: Bool = false,
        initialMode: AudioRecordingViewModel.Mode? = nil
    ) {
        self.vaultURL = vaultURL
        self.onInsertText = onInsertText
        self.compactMode = compactMode
        self.initialMode = initialMode
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.recordingService.isRecording && showCompactPill {
                    compactPillOverlay
                } else {
                    fullRecordingView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .quartzMaterialBackground(cornerRadius: 0)
            .navigationTitle(String(localized: "Record Audio", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        viewModel.discardRecording()
                        dismiss()
                    }
                }
                if viewModel.recordingService.isRecording && !showCompactPill {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(QuartzAnimation.standard) { showCompactPill = true }
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel(String(localized: "Minimize to compact mode", bundle: .module))
                    }
                }
                if viewModel.didFinish {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done", bundle: .module)) {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                viewModel.vaultURL = vaultURL
                if let mode = initialMode {
                    viewModel.mode = mode
                }
            }
        }
        .frame(minWidth: compactMode ? 280 : 380, minHeight: compactMode ? 260 : 440)
    }

    // MARK: - Granola-Style Compact Pill (Floating During Recording)

    private var compactPillOverlay: some View {
        VStack {
            Spacer()
            compactPillView
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    private var compactPillView: some View {
        HStack(spacing: 16) {
            Button {
                QuartzFeedback.selection()
                withAnimation(QuartzAnimation.standard) { showCompactPill = false }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Expand to full view", bundle: .module))

            Text(viewModel.recordingService.formattedDuration)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundStyle(QuartzColors.accent)
                .contentTransition(.numericText())

            if viewModel.recordingService.isPaused {
                Text(String(localized: "Paused", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .pulse()
            }

            Spacer()

            Button {
                QuartzFeedback.toggle()
                viewModel.togglePause()
            } label: {
                Image(systemName: viewModel.recordingService.isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button {
                QuartzFeedback.primaryAction()
                Task {
                    if let text = await viewModel.stopRecording() {
                        showCompactPill = false
                        onInsertText(text)
                    }
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(QuartzColors.accent.gradient))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stop recording", bundle: .module))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    // MARK: - Full Recording View

    private var fullRecordingView: some View {
        VStack(spacing: 0) {
            Spacer()

            if !compactMode {
                waveformDisplay
                    .padding(.bottom, 24)
            }

            timerDisplay
                .padding(.bottom, compactMode ? 16 : 32)

            recordingControls
                .padding(.bottom, compactMode ? 12 : 28)

            if !compactMode {
                modeSelector
                    .padding(.bottom, 16)
            }

            if viewModel.isTranscribing {
                transcriptionStatus
                    .padding(.bottom, 16)
            }

            if let error = viewModel.errorMessage {
                errorBanner(error)
                    .padding(.bottom, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Waveform

    private var waveformDisplay: some View {
        HStack(alignment: .center, spacing: 2) {
            let history = viewModel.recordingService.levelHistory
            let bars = recentBars(from: history, count: 40)
            ForEach(Array(bars.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(QuartzColors.accent.opacity(barOpacity(for: index, total: bars.count)))
                    .frame(width: 4, height: barHeight(for: level))
                    .animation(
                        .spring(response: 0.15, dampingFraction: 0.7),
                        value: level
                    )
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassBackground(cornerRadius: 16, opacity: 0.8, shadowRadius: 8)
    }

    private func recentBars(from history: [Float], count: Int) -> [Float] {
        if history.isEmpty {
            return Array(repeating: Float(0.02), count: count)
        }
        if history.count >= count {
            return Array(history.suffix(count))
        }
        let padding = Array(repeating: Float(0.02), count: count - history.count)
        return padding + history
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 72
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }

    private func barOpacity(for index: Int, total: Int) -> Double {
        guard total > 1 else { return 1 }
        let progress = Double(index) / Double(total - 1)
        return 0.3 + 0.7 * progress
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        VStack(spacing: 6) {
            Text(viewModel.recordingService.formattedDuration)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(viewModel.recordingService.isRecording ? QuartzColors.accent : .primary)
                .contentTransition(.numericText())
                .animation(QuartzAnimation.standard, value: viewModel.recordingService.duration)

            if viewModel.recordingService.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .pulse()
                    Text(viewModel.recordingService.isPaused
                         ? String(localized: "Paused", bundle: .module)
                         : String(localized: "Recording", bundle: .module))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        HStack(spacing: 32) {
            if viewModel.recordingService.isRecording {
                Button {
                QuartzFeedback.toggle()
                viewModel.togglePause()
            } label: {
                    Image(systemName: viewModel.recordingService.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .quartzMaterialCircle()
                }
                .buttonStyle(QuartzBounceButtonStyle())
                .accessibilityLabel(viewModel.recordingService.isPaused
                    ? String(localized: "Resume", bundle: .module)
                    : String(localized: "Pause", bundle: .module))

                Button {
                    QuartzFeedback.primaryAction()
                    Task {
                        if let text = await viewModel.stopRecording() {
                            onInsertText(text)
                        }
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(
                            Circle()
                                .fill(QuartzColors.accent.gradient)
                                .shadow(color: QuartzColors.accent.opacity(0.4), radius: 12, y: 6)
                        )
                }
                .buttonStyle(QuartzBounceButtonStyle())
                .accessibilityLabel(String(localized: "Stop recording", bundle: .module))

                Button {
                    QuartzFeedback.destructive()
                    viewModel.discardRecording()
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 52, height: 52)
                        .quartzMaterialCircle()
                }
                .buttonStyle(QuartzBounceButtonStyle())
                .accessibilityLabel(String(localized: "Discard recording", bundle: .module))
            } else if viewModel.isTranscribing {
                ProgressView()
                    .controlSize(.large)
                    .tint(QuartzColors.accent)
            } else {
                Button {
                    QuartzFeedback.primaryAction()
                    Task { await viewModel.startRecording() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(
                            Circle()
                                .fill(QuartzColors.accent.gradient)
                                .shadow(color: QuartzColors.accent.opacity(0.4), radius: 12, y: 6)
                        )
                }
                .buttonStyle(QuartzBounceButtonStyle())
                .disabled(viewModel.didFinish)
                .accessibilityLabel(String(localized: "Start recording", bundle: .module))
            }
        }
        .animation(QuartzAnimation.standard, value: viewModel.recordingService.isRecording)
        .animation(QuartzAnimation.standard, value: viewModel.isTranscribing)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $viewModel.transcriptionEnabled) {
                Label(
                    String(localized: "Transcribe after recording", bundle: .module),
                    systemImage: "text.bubble"
                )
                .font(.subheadline)
            }
            .tint(QuartzColors.accent)
            .disabled(viewModel.recordingService.isRecording || viewModel.isTranscribing)

            if viewModel.transcriptionEnabled {
                Picker(String(localized: "Mode", bundle: .module), selection: $viewModel.mode) {
                    ForEach(AudioRecordingViewModel.Mode.allCases, id: \.self) { mode in
                        Text(modeLabel(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.recordingService.isRecording || viewModel.isTranscribing)
                .transition(.move(edge: .top).combined(with: .opacity))

                if viewModel.mode == .meetingMinutes {
                    Picker(String(localized: "Template", bundle: .module), selection: $viewModel.minutesTemplate) {
                        ForEach(MeetingMinutesTemplate.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.recordingService.isRecording || viewModel.isTranscribing)

                    if viewModel.minutesTemplate == .custom {
                        TextField(String(localized: "Custom system instruction…", bundle: .module), text: $viewModel.customMinutesPrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .disabled(viewModel.recordingService.isRecording || viewModel.isTranscribing)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassBackground(cornerRadius: 14, opacity: 0.6, shadowRadius: 6)
        .animation(QuartzAnimation.content, value: viewModel.transcriptionEnabled)
    }

    private func modeLabel(_ mode: AudioRecordingViewModel.Mode) -> String {
        switch mode {
        case .transcription:
            String(localized: "Transcription", bundle: .module)
        case .meetingMinutes:
            String(localized: "Meeting Minutes", bundle: .module)
        }
    }

    // MARK: - Transcription Status

    private var transcriptionStatus: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(QuartzColors.accent)
            Text(viewModel.transcriptionProgress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackground(cornerRadius: 10, opacity: 0.6, shadowRadius: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(QuartzAnimation.content, value: viewModel.transcriptionProgress)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.red.opacity(0.1))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(QuartzAnimation.status, value: viewModel.errorMessage)
    }
}
