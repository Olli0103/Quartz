import XCTest
import SwiftUI
@testable import QuartzKit

#if canImport(UIKit) && !os(macOS)
import UIKit

enum MobileEditorTargetDevice {
    case phone
    case pad

    var idiom: UIUserInterfaceIdiom {
        switch self {
        case .phone: .phone
        case .pad: .pad
        }
    }

    var platformSuffix: String {
        switch self {
        case .phone: "iOS"
        case .pad: "iPadOS"
        }
    }

    var snapshotSize: CGSize {
        switch self {
        case .phone: CGSize(width: 393, height: 852)
        case .pad: CGSize(width: 834, height: 1194)
        }
    }

    var liveCanvasSize: CGSize {
        switch self {
        case .phone: CGSize(width: 390, height: 360)
        case .pad: CGSize(width: 744, height: 420)
        }
    }

    var editorMaxWidth: CGFloat {
        switch self {
        case .phone: 358
        case .pad: 680
        }
    }
}

@MainActor
func requireMobileDevice(_ target: MobileEditorTargetDevice) throws {
    guard UIDevice.current.userInterfaceIdiom == target.idiom else {
        throw XCTSkip("Skipping \(target.platformSuffix) editor test on \(UIDevice.current.userInterfaceIdiom)")
    }
}

@MainActor
func makeLoadedMobileSession(fixture: EditorRealityFixture, target: MobileEditorTargetDevice) async throws -> EditorSession {
    let text = try fixture.load()
    let url = URL(fileURLWithPath: "/tmp/\(fixture.rawValue)-\(target.platformSuffix).md")
    let provider = MockVaultProvider()
    return try await makeLoadedMobileSession(
        text: text,
        title: fixture.rawValue,
        url: url,
        provider: provider
    )
}

@MainActor
func makeLoadedMobileSession(
    text: String,
    title: String,
    url: URL,
    provider: MockVaultProvider
) async throws -> EditorSession {
    let note = NoteDocument(
        fileURL: url,
        frontmatter: Frontmatter(title: title),
        body: text,
        isDirty: false
    )
    await provider.addNote(note)

    return await makeLoadedExistingMobileSession(at: url, provider: provider)
}

@MainActor
func makeLoadedExistingMobileSession(
    at url: URL,
    provider: MockVaultProvider
) async -> EditorSession {
    let session = EditorSession(
        vaultProvider: provider,
        frontmatterParser: FrontmatterParser(),
        inspectorStore: InspectorStore()
    )
    await session.loadNote(at: url)
    return session
}

@MainActor
func makeMobileSnapshotHarness(
    fixture: EditorRealityFixture,
    target: MobileEditorTargetDevice,
    syntaxVisibilityMode: SyntaxVisibilityMode,
    selection: NSRange? = nil,
    colorScheme: ColorScheme = .light
) async throws -> MobileEditorSnapshotHarness {
    let session = try await makeLoadedMobileSession(fixture: fixture, target: target)
    let rootView = AnyView(
        ZStack {
            Color(uiColor: .systemBackground)
            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: 1.0,
                editorFontFamily: EditorTypography.defaultFontFamily,
                editorLineSpacing: EditorTypography.defaultLineSpacingMultiplier,
                editorMaxWidth: target.editorMaxWidth,
                syntaxVisibilityMode: syntaxVisibilityMode
            )
        }
        .frame(width: target.snapshotSize.width, height: target.snapshotSize.height)
        .preferredColorScheme(colorScheme)
    )

    let controller = UIHostingController(rootView: rootView)
    controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    controller.view.frame = CGRect(origin: .zero, size: target.snapshotSize)

    let window = UIWindow(frame: controller.view.frame)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    window.layoutIfNeeded()

    try await waitForMobileEditorReady(session: session, hostView: controller.view)
    await settleMobileSnapshotSurface(controller: controller, window: window)

    if let textView = session.activeTextView as? MarkdownEditorUITextView {
        textView.hidesInsertionPointForSnapshots = true
    }

    if let selection {
        session.restoreCursor(location: selection.location, length: selection.length)
        session.selectionDidChange(selection)
        await settleMobileSnapshotSurface(controller: controller, window: window)
    }

    return MobileEditorSnapshotHarness(session: session, controller: controller, window: window)
}

@MainActor
func makeMountedMobileHarness(
    text: String,
    target: MobileEditorTargetDevice,
    syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret
) async throws -> MobileEditorHarness {
    let provider = MockVaultProvider()
    let url = URL(fileURLWithPath: "/tmp/editor-live-mutation-\(target.platformSuffix)-\(UUID().uuidString).md")
    let session = try await makeLoadedMobileSession(
        text: text,
        title: "Editor Regression",
        url: url,
        provider: provider
    )

    return try await mountMobileEditor(
        session: session,
        target: target,
        syntaxVisibilityMode: syntaxVisibilityMode
    )
}

@MainActor
func mountMobileEditor(
    session: EditorSession,
    target: MobileEditorTargetDevice,
    syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret
) async throws -> MobileEditorHarness {

    let rootView = AnyView(
        ZStack {
            Color(uiColor: .systemBackground)
            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: 1.0,
                editorFontFamily: EditorTypography.defaultFontFamily,
                editorLineSpacing: EditorTypography.defaultLineSpacingMultiplier,
                editorMaxWidth: target.editorMaxWidth,
                syntaxVisibilityMode: syntaxVisibilityMode
            )
        }
        .frame(width: target.liveCanvasSize.width, height: target.liveCanvasSize.height)
    )

    let controller = UIHostingController(rootView: rootView)
    controller.view.frame = CGRect(origin: .zero, size: target.liveCanvasSize)

    let window = UIWindow(frame: controller.view.frame)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    window.layoutIfNeeded()

    try await waitForMobileEditorReady(session: session, hostView: controller.view)

    guard let textView = session.activeTextView else {
        XCTFail("Mounted mobile editor did not expose an active text view")
        throw CancellationError()
    }

    textView.becomeFirstResponder()
    session.selectionDidChange(textView.selectedRange)

    return MobileEditorHarness(session: session, textView: textView, controller: controller, window: window)
}

@MainActor
func waitForMobileEditorReady(session: EditorSession, hostView: UIView) async throws {
    for _ in 0..<80 {
        hostView.layoutIfNeeded()

        if let textView = session.activeTextView,
           textView.alpha == 1,
           textView.text == session.currentText,
           textView.textStorage.length == (session.currentText as NSString).length {
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }

    XCTFail("Timed out waiting for UIKit editor harness to become ready")
    throw CancellationError()
}

@MainActor
func waitForMobileSessionText(_ session: EditorSession, expected: String) async throws {
    for _ in 0..<80 {
        if session.currentText == expected,
           session.activeTextView?.text == expected {
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }

    XCTFail("Timed out waiting for editor text to become \(expected.debugDescription)")
    throw CancellationError()
}

@MainActor
func pumpMobileHarness(_ harness: MobileEditorHarness, iterations: Int = 12) async {
    for _ in 0..<iterations {
        harness.controller.view.layoutIfNeeded()
        harness.window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func settleMobileSnapshotSurface(
    controller: UIHostingController<AnyView>,
    window: UIWindow,
    iterations: Int = 18
) async {
    for _ in 0..<iterations {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        CATransaction.flush()
        try? await Task.sleep(for: .milliseconds(16))
    }
}

func isBoldFont(_ font: UIFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.traitBold)
}

struct MobileEditorSnapshotHarness {
    let session: EditorSession
    let controller: UIHostingController<AnyView>
    let window: UIWindow
}

struct MobileEditorHarness {
    let session: EditorSession
    let textView: UITextView
    let controller: UIHostingController<AnyView>
    let window: UIWindow
}
#endif
