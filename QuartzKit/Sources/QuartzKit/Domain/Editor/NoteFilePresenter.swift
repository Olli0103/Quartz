import Foundation

/// NSFilePresenter implementation for a single open note.
///
/// Registers with `NSFileCoordinator` to receive notifications when the file is
/// modified, moved, or deleted by other processes (Finder, iCloud sync, other apps).
///
/// This is critical for iCloud Drive reliability — without NSFilePresenter, the app
/// is blind to coordinated writes from the `bird` daemon and other processes.
///
/// ## Thread Safety
///
/// All presenter callbacks run on `presentedItemOperationQueue` (a serial queue).
/// UI updates are dispatched to MainActor via `Task { @MainActor in ... }`.
///
/// ## Lifecycle
///
/// 1. Create with `NoteFilePresenter(url:delegate:)`
/// 2. Presenter auto-registers with `NSFileCoordinator.addFilePresenter`
/// 3. Call `invalidate()` or let deinit run to unregister
///
/// ## Important
///
/// The presenter holds a weak reference to its delegate to avoid retain cycles.
/// Ensure the delegate (typically EditorSession) outlives the presenter.
public final class NoteFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {

    // MARK: - NSFilePresenter Protocol

    /// The URL of the file being presented. May be updated if the file moves.
    public private(set) var presentedItemURL: URL?

    /// Serial queue for presenter callbacks. Required by NSFilePresenter protocol.
    public let presentedItemOperationQueue: OperationQueue

    // MARK: - Delegate

    /// Delegate to notify of file events. Weak to avoid retain cycles.
    public weak var delegate: NoteFilePresenterDelegate?

    // MARK: - State

    /// Whether the presenter is currently registered with NSFileCoordinator.
    private var isRegistered = false

    /// Lock for thread-safe state mutations.
    private let stateLock = NSLock()

    // MARK: - Initialization

    /// Creates a new file presenter for the given URL.
    ///
    /// - Parameters:
    ///   - url: The file URL to present.
    ///   - delegate: The delegate to notify of file events.
    ///
    /// The presenter automatically registers with `NSFileCoordinator` on creation.
    public init(url: URL, delegate: NoteFilePresenterDelegate? = nil) {
        self.presentedItemURL = url
        self.delegate = delegate

        // Create a serial operation queue for presenter callbacks
        let queue = OperationQueue()
        queue.name = "com.quartz.NoteFilePresenter.\(url.lastPathComponent)"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        self.presentedItemOperationQueue = queue

        super.init()

        // Register with the file coordinator system
        register()
    }

    deinit {
        // Unregister on deallocation
        unregister()
    }

    // MARK: - Registration

    /// Registers this presenter with NSFileCoordinator.
    /// Called automatically on init.
    private func register() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRegistered else { return }
        NSFileCoordinator.addFilePresenter(self)
        isRegistered = true
    }

    /// Unregisters this presenter from NSFileCoordinator.
    /// Called automatically on deinit, or call manually to stop receiving events.
    public func invalidate() {
        unregister()
    }

    private func unregister() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRegistered else { return }
        NSFileCoordinator.removeFilePresenter(self)
        isRegistered = false
    }

    // MARK: - NSFilePresenter Callbacks

    /// Called when the file's contents have changed.
    ///
    /// This is triggered by:
    /// - iCloud syncing a new version from another device
    /// - Another app editing the file via NSFileCoordinator
    /// - Finder modifying the file
    public func presentedItemDidChange() {
        guard let delegate = delegate else { return }

        Task { @MainActor in
            delegate.filePresenterDidDetectChange(self)
        }
    }

    /// Called when the file has been moved or renamed.
    ///
    /// - Parameter newURL: The new location of the file.
    ///
    /// This is triggered by:
    /// - iCloud renaming/moving the file during sync
    /// - Finder rename/move
    /// - Another app moving the file via NSFileCoordinator
    public func presentedItemDidMove(to newURL: URL) {
        let oldURL = presentedItemURL

        // Update our tracked URL
        stateLock.lock()
        presentedItemURL = newURL
        stateLock.unlock()

        guard let delegate = delegate else { return }

        Task { @MainActor in
            delegate.filePresenter(self, didMoveFrom: oldURL, to: newURL)
        }
    }

    /// Called before the file is deleted.
    ///
    /// - Parameter completionHandler: Must be called when we're done handling the deletion.
    ///
    /// This gives us a chance to:
    /// 1. Save any unsaved changes to a recovery location
    /// 2. Update the UI to show the file was deleted
    ///
    /// **Important**: We MUST call the completionHandler or the deleting process will hang.
    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        guard let delegate = delegate else {
            completionHandler(nil)
            return
        }

        // Wrap completion handler to make it Sendable-safe
        let wrappedCompletion = UncheckedSendableWrapper(completionHandler)
        let queue = presentedItemOperationQueue

        Task { @MainActor in
            do {
                try await delegate.filePresenterWillDelete(self)
                queue.addOperation { wrappedCompletion.value(nil) }
            } catch {
                queue.addOperation { wrappedCompletion.value(error) }
            }
        }
    }

    /// Called when we should save our changes before another process writes.
    ///
    /// - Parameter completionHandler: Must be called when save is complete.
    ///
    /// This is called when another process wants to write to the file via
    /// NSFileCoordinator. We should save any pending changes first.
    public func savePresentedItemChanges(completionHandler: @escaping (Error?) -> Void) {
        guard let delegate = delegate else {
            completionHandler(nil)
            return
        }

        // Wrap completion handler to make it Sendable-safe
        let wrappedCompletion = UncheckedSendableWrapper(completionHandler)
        let queue = presentedItemOperationQueue

        Task { @MainActor in
            do {
                try await delegate.filePresenterShouldSave(self)
                queue.addOperation { wrappedCompletion.value(nil) }
            } catch {
                queue.addOperation { wrappedCompletion.value(error) }
            }
        }
    }
}

/// Wrapper to make non-Sendable values usable across isolation boundaries.
/// Use with caution — only for values that are known to be safe (e.g., completion handlers
/// that will only be called once).
private struct UncheckedSendableWrapper<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Delegate Protocol

/// Delegate protocol for NoteFilePresenter events.
///
/// All delegate methods are called on the MainActor.
@MainActor
public protocol NoteFilePresenterDelegate: AnyObject {
    /// Called when the file's contents have changed externally.
    ///
    /// The delegate should:
    /// - If no unsaved changes: reload from disk
    /// - If unsaved changes: show "modified externally" banner
    func filePresenterDidDetectChange(_ presenter: NoteFilePresenter)

    /// Called when the file has been moved or renamed.
    ///
    /// The delegate should update its internal URL reference.
    func filePresenter(_ presenter: NoteFilePresenter, didMoveFrom oldURL: URL?, to newURL: URL)

    /// Called before the file is deleted.
    ///
    /// The delegate should:
    /// - Save any unsaved changes to a recovery location
    /// - Update UI to show file was deleted
    ///
    /// Throw an error to prevent the deletion (rarely appropriate).
    func filePresenterWillDelete(_ presenter: NoteFilePresenter) async throws

    /// Called when we should save pending changes.
    ///
    /// This is called when another process wants to write to the file.
    /// Save any pending changes immediately.
    func filePresenterShouldSave(_ presenter: NoteFilePresenter) async throws
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when a file presenter detects an external modification.
    /// `object` is the file URL.
    static let quartzFilePresenterDidChange = Notification.Name("quartzFilePresenterDidChange")

    /// Posted when a file presenter detects the file was moved.
    /// `userInfo` contains `"oldURL": URL?` and `"newURL": URL`.
    static let quartzFilePresenterDidMove = Notification.Name("quartzFilePresenterDidMove")

    /// Posted when a file presenter detects the file was deleted.
    /// `object` is the file URL.
    static let quartzFilePresenterWillDelete = Notification.Name("quartzFilePresenterWillDelete")
}
