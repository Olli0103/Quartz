#if os(macOS)
import AppKit
import SwiftUI

/// Floating NSPanel für schnelle Notiz-Erfassung auf dem Mac.
///
/// Wird über einen globalen Hotkey (z.B. ⌥⌘N) aktiviert.
/// Das Panel schwebt über allen Fenstern und verschwindet
/// nach dem Speichern automatisch.
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

        // Zentriert auf dem Bildschirm
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

    /// Zeigt das Panel und bringt es in den Fokus.
    public func showPanel() {
        makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Manager für den globalen Hotkey und das Quick Note Panel.
@MainActor
public final class QuickNoteManager {
    private var panel: QuickNotePanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let vaultRoot: URL

    public init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
    }

    /// Registriert den globalen Hotkey (⌥⌘N).
    public func registerHotkey() {
        // Global Monitor: fängt Events auch wenn App nicht aktiv ist
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local Monitor: fängt Events wenn App aktiv ist
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Event konsumiert
            }
            return event
        }
    }

    /// Entfernt den globalen Hotkey.
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

    /// Zeigt das Quick Note Panel.
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
