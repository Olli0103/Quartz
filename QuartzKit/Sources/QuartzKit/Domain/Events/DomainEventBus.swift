import Foundation

// MARK: - Domain Events (Per CODEX.md F4)

/// Typed domain events to replace NotificationCenter for core flows.
///
/// **Per CODEX.md F4:** NotificationCenter was overloaded for core data flow,
/// causing ordering races, hidden coupling, and hard reproducibility.
///
/// This typed event system provides:
/// - Compile-time type safety
/// - Guaranteed ordering (FIFO within a subscriber)
/// - Explicit coupling via subscription
/// - Testable event sequences
public enum DomainEvent: Sendable {
    // MARK: - Note Lifecycle

    /// A note was saved to disk.
    case noteSaved(url: URL, timestamp: Date)

    /// A note was created.
    case noteCreated(url: URL)

    /// A note was deleted.
    case noteDeleted(url: URL)

    /// A note was relocated (moved or renamed).
    case noteRelocated(from: URL, to: URL)

    // MARK: - Index & Graph

    /// A full reindex was requested.
    case reindexRequested

    /// Spotlight index entries were removed.
    case spotlightEntriesRemoved(urls: [URL])

    /// Graph connections were updated for a note.
    case graphUpdated(url: URL)

    // MARK: - Sync & Conflict

    /// A sync conflict was detected.
    case conflictDetected(url: URL)

    /// A sync conflict was resolved.
    case conflictResolved(url: URL, resolution: ConflictResolutionType)

    /// Sync status changed for a file.
    case syncStatusChanged(url: URL, status: SyncStatus)

    // MARK: - AI & Intelligence

    /// AI analysis completed for a note.
    case aiAnalysisCompleted(url: URL, concepts: [String])

    /// Semantic links were discovered.
    case semanticLinksDiscovered(url: URL, relatedURLs: [URL])

    /// AI provider health changed.
    case aiProviderHealthChanged(health: ProviderHealth)

    // MARK: - Nested Types for Self-Containment

    /// Sync status (mirrors CloudSyncStatus for self-containment).
    public enum SyncStatus: String, Sendable {
        case current, uploading, downloading, notDownloaded, conflict, error
    }

    /// Provider health (mirrors AIProviderHealthState for self-containment).
    public enum ProviderHealth: String, Sendable {
        case healthy, degraded, unavailable, circuitOpen
    }
}

/// Resolution type for conflict events.
public enum ConflictResolutionType: Sendable {
    case keptLocal
    case keptCloud
    case keptBoth
    case merged
}

// MARK: - Event Bus

/// Typed event bus with async stream delivery.
///
/// Thread-safe via actor isolation. Events are delivered in FIFO order
/// to each subscriber.
///
/// Usage:
/// ```swift
/// // Subscribe
/// let bus = DomainEventBus.shared
/// for await event in bus.subscribe() {
///     switch event {
///     case .noteSaved(let url, _):
///         // handle
///     default:
///         break
///     }
/// }
///
/// // Publish
/// await bus.publish(.noteSaved(url: noteURL, timestamp: Date()))
/// ```
public actor DomainEventBus {

    // MARK: - Singleton

    /// Shared event bus for app-wide domain events.
    public static let shared = DomainEventBus()

    // MARK: - State

    private var continuations: [UUID: AsyncStream<DomainEvent>.Continuation] = [:]
    private var eventHistory: [DomainEvent] = []
    private let historyLimit = 100

    public init() {}

    // MARK: - Subscribe

    /// Subscribes to domain events.
    ///
    /// Returns an async stream of events. Events are delivered in order.
    /// The stream terminates when the subscriber cancels or the bus is reset.
    public func subscribe() -> AsyncStream<DomainEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            self.continuations[id] = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { [weak self] in
                    await self?.unsubscribe(id: id)
                }
            }
        }
    }

    private func unsubscribe(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    // MARK: - Publish

    /// Publishes an event to all subscribers.
    ///
    /// Events are delivered synchronously to all active continuations.
    public func publish(_ event: DomainEvent) {
        // Record in history
        eventHistory.append(event)
        if eventHistory.count > historyLimit {
            eventHistory.removeFirst()
        }

        // Deliver to all subscribers
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    // MARK: - Testing Support

    /// Returns recent event history for testing.
    public func recentEvents(limit: Int = 10) -> [DomainEvent] {
        Array(eventHistory.suffix(limit))
    }

    /// Clears all state. For testing only.
    public func reset() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        eventHistory.removeAll()
    }

    /// Returns the number of active subscribers.
    public var subscriberCount: Int {
        continuations.count
    }
}
