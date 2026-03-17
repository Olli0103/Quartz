#if os(macOS)
import AppKit
import SwiftUI

/// Floating NSPanel for quick note capture on Mac.
///
/// Activated via a global hotkey (e.g. ⌥⌘N).
/// The panel floats above all windows and disappears
/// automatically after saving.
public final class QuickNotePanel: NSPanel {
    private var hostingView: NSHostingView<QuickNoteView>?

    public init(vaultRoot: URL) {
        let contentRect = NSRect(x: 0, y: 0, width: 400, height: 300)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        title = String(localized: "Quick Note", bundle: .module)
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        // Centered on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - contentRect.width / 2
            let y = screenFrame.midY - contentRect.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let quickNoteView = QuickNoteView(vaultRoot: vaultRoot) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingView(rootView: quickNoteView)
        contentView = hosting
        hostingView = hosting
    }

    /// Shows the panel and brings it into focus.
    public func showPanel() {
        makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Manager for the global hotkey and the Quick Note panel.
@MainActor
public final class QuickNoteManager {
    private var panel: QuickNotePanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let vaultRoot: URL

    public init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
    }

    /// Registers the global hotkey (⌥⌘N).
    public func registerHotkey() {
        // Global monitor: catches events even when app is not active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: catches events when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Event consumed
            }
            return event
        }
    }

    /// Removes the global hotkey.
    public func unregisterHotkey() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Shows the Quick Note panel.
    public func showQuickNote() {
        if panel == nil {
            panel = QuickNotePanel(vaultRoot: vaultRoot)
        }
        panel?.showPanel()
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // ⌥⌘N = Option + Command + N
        let modifiers: NSEvent.ModifierFlags = [.option, .command]
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers,
              event.charactersIgnoringModifiers == "n" else {
            return false
        }

        Task { @MainActor in
            showQuickNote()
        }
        return true
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
#endif
