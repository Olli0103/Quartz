import SwiftUI
import os

// MARK: - File Removed Fallback View

/// Displays when a note is deleted while the editor is open.
///
/// **Hostile OS Threat:**
/// - **iPadOS Stage Manager**: Two windows open same note, Window A deletes it
/// - **macOS Multi-Window**: Secondary window open while main window deletes file
/// - **iCloud Sync**: Remote device deletes file during local editing
///
/// **Behavior:**
/// - Immediately disables editing to prevent crash
/// - Shows clear "File Removed" message with options
/// - No fatal writes attempted to missing file
///
/// **Liquid Glass Design:**
/// - Frosted glass card with SF Symbol
/// - Calm, non-alarming visual language
/// - Clear actions: Close window or Create new note
public struct FileRemovedFallbackView: View {
    let fileName: String
    let onClose: () -> Void
    let onCreateNew: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAppearing = false

    public init(
        fileName: String,
        onClose: @escaping () -> Void,
        onCreateNew: (() -> Void)? = nil
    ) {
        self.fileName = fileName
        self.onClose = onClose
        self.onCreateNew = onCreateNew
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)

            // Title
            Text("File No Longer Available")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            // Subtitle
            Text("\"\(fileName)\" was moved or deleted.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Actions
            VStack(spacing: 12) {
                Button(action: onClose) {
                    Label("Close Window", systemImage: "xmark.circle")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let onCreateNew {
                    Button(action: onCreateNew) {
                        Label("Create New Note", systemImage: "doc.badge.plus")
                            .frame(maxWidth: 200)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        }
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File no longer available: \(fileName)")
        .accessibilityHint("Double tap to close window")
    }
}

// MARK: - Multi-Window File Coordinator

/// Coordinates file state across multiple windows in Stage Manager.
///
/// **Hostile OS Threat:**
/// - **iPadOS Stage Manager**: Same document open in 2+ windows
/// - **macOS**: Secondary windows via WindowGroup
/// - **Race Conditions**: Window A saves while Window B reads
///
/// **Telemetry:**
/// - Logs all window registrations/unregistrations
/// - Tracks file deletion notifications per-window
/// - Posts `.quartzFileRemovedFromWindow` for UI handling
@MainActor
public final class MultiWindowFileCoordinator: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = MultiWindowFileCoordinator()

    // MARK: - State

    /// Active windows mapped by their scene session ID.
    private var activeWindows: [String: WindowFileState] = [:]

    /// Files currently being edited, mapped to their window IDs.
    private var fileToWindows: [URL: Set<String>] = [:]

    /// nonisolated(unsafe) for deinit access — Swift 6 deinit is nonisolated.
    /// Safe: by deinit, no other code holds a reference to self.
    nonisolated(unsafe) private var observerTokens: [Any] = []

    private let logger = Logger(subsystem: "com.quartz", category: "MultiWindowCoordinator")

    // MARK: - Init

    private init() {
        startObserving()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Window Registration

    /// Registers a window as editing a specific file.
    public func registerWindow(id: String, editing fileURL: URL) {
        // Update window state
        activeWindows[id] = WindowFileState(windowID: id, fileURL: fileURL)

        // Track file-to-window mapping
        var windows = fileToWindows[fileURL] ?? []
        windows.insert(id)
        fileToWindows[fileURL] = windows

        logger.info("Window \(id, privacy: .public) registered for \(fileURL.lastPathComponent, privacy: .public)")

        // Warn if multiple windows are editing same file
        if windows.count > 1 {
            logger.warning("Multiple windows (\(windows.count)) editing same file: \(fileURL.lastPathComponent, privacy: .public)")
        }
    }

    /// Unregisters a window.
    public func unregisterWindow(id: String) {
        guard let state = activeWindows.removeValue(forKey: id) else { return }

        // Remove from file-to-window mapping
        if var windows = fileToWindows[state.fileURL] {
            windows.remove(id)
            if windows.isEmpty {
                fileToWindows.removeValue(forKey: state.fileURL)
            } else {
                fileToWindows[state.fileURL] = windows
            }
        }

        logger.info("Window \(id, privacy: .public) unregistered")
    }

    /// Checks if a file is being edited by multiple windows.
    public func isFileEditedByMultipleWindows(_ fileURL: URL) -> Bool {
        (fileToWindows[fileURL]?.count ?? 0) > 1
    }

    /// Returns the number of windows editing a file.
    public func windowCount(for fileURL: URL) -> Int {
        fileToWindows[fileURL]?.count ?? 0
    }

    // MARK: - File Deletion Handling

    private func startObserving() {
        // Listen for NSFilePresenter deletion notifications
        let deleteToken = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterWillDelete,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in
                self?.handleFileDeletion(at: url)
            }
        }
        observerTokens.append(deleteToken)

        // Listen for move notifications (could be rename or actual move)
        let moveToken = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterDidMove,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let oldURL = userInfo["oldURL"] as? URL,
                  let newURL = userInfo["newURL"] as? URL else { return }
            Task { @MainActor in
                self?.handleFileMove(from: oldURL, to: newURL)
            }
        }
        observerTokens.append(moveToken)
    }

    private func handleFileDeletion(at url: URL) {
        guard let windowIDs = fileToWindows[url], !windowIDs.isEmpty else { return }

        logger.warning("File deleted while open in \(windowIDs.count) window(s): \(url.lastPathComponent, privacy: .public)")

        // Notify each window
        for windowID in windowIDs {
            NotificationCenter.default.post(
                name: .quartzFileRemovedFromWindow,
                object: nil,
                userInfo: [
                    "windowID": windowID,
                    "fileURL": url,
                    "fileName": url.deletingPathExtension().lastPathComponent
                ]
            )
        }

        // Clear the mapping
        fileToWindows.removeValue(forKey: url)
        for windowID in windowIDs {
            activeWindows.removeValue(forKey: windowID)
        }
    }

    private func handleFileMove(from oldURL: URL, to newURL: URL) {
        guard let windowIDs = fileToWindows[oldURL], !windowIDs.isEmpty else { return }

        logger.info("File moved while open: \(oldURL.lastPathComponent, privacy: .public) → \(newURL.lastPathComponent, privacy: .public)")

        // Update mappings
        fileToWindows.removeValue(forKey: oldURL)
        fileToWindows[newURL] = windowIDs

        for windowID in windowIDs {
            if var state = activeWindows[windowID] {
                state.fileURL = newURL
                activeWindows[windowID] = state
            }

            // Notify the window of the URL change
            NotificationCenter.default.post(
                name: .quartzFileMovedInWindow,
                object: nil,
                userInfo: [
                    "windowID": windowID,
                    "oldURL": oldURL,
                    "newURL": newURL
                ]
            )
        }
    }

    // MARK: - Supporting Types

    public struct WindowFileState: Sendable {
        public let windowID: String
        public var fileURL: URL
    }
}

// MARK: - SwiftUI Environment Integration

/// View modifier that handles file removal gracefully.
public struct FileRemovalHandler: ViewModifier {
    let fileURL: URL
    let windowID: String
    @Binding var isFileRemoved: Bool
    @State private var removedFileName: String = ""

    public func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isFileRemoved ? 0.3 : 1)
                .allowsHitTesting(!isFileRemoved)

            if isFileRemoved {
                FileRemovedFallbackView(
                    fileName: removedFileName,
                    onClose: {
                        dismissWindow()
                    },
                    onCreateNew: nil
                )
            }
        }
        .onAppear {
            MultiWindowFileCoordinator.shared.registerWindow(id: windowID, editing: fileURL)
        }
        .onDisappear {
            MultiWindowFileCoordinator.shared.unregisterWindow(id: windowID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzFileRemovedFromWindow)) { notification in
            guard let userInfo = notification.userInfo,
                  let notificationWindowID = userInfo["windowID"] as? String,
                  notificationWindowID == windowID else { return }

            removedFileName = (userInfo["fileName"] as? String) ?? "Unknown"
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isFileRemoved = true
            }
        }
    }

    private func dismissWindow() {
        #if os(macOS)
        NSApplication.shared.keyWindow?.close()
        #else
        // On iOS, windows are managed by UIKit scene lifecycle
        // The view will be dismissed when the scene is destroyed
        #endif
    }
}

public extension View {
    /// Handles file removal gracefully in multi-window scenarios.
    func handleFileRemoval(fileURL: URL, windowID: String, isRemoved: Binding<Bool>) -> some View {
        modifier(FileRemovalHandler(fileURL: fileURL, windowID: windowID, isFileRemoved: isRemoved))
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when a file is deleted while open in a window.
    /// `userInfo` contains: windowID, fileURL, fileName
    static let quartzFileRemovedFromWindow = Notification.Name("quartzFileRemovedFromWindow")

    /// Posted when a file is moved/renamed while open in a window.
    /// `userInfo` contains: windowID, oldURL, newURL
    static let quartzFileMovedInWindow = Notification.Name("quartzFileMovedInWindow")
}

// MARK: - Preview

#if DEBUG
#Preview("File Removed Fallback") {
    FileRemovedFallbackView(
        fileName: "Important Notes",
        onClose: { print("Close tapped") },
        onCreateNew: { print("Create new tapped") }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.2))
}
#endif
