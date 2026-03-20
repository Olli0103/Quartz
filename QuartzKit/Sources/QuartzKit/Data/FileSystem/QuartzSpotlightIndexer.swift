import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Submits vault notes to Core Spotlight for system-wide search (complements in-app ``VaultSearchIndex``).
public actor QuartzSpotlightIndexer {
    private let vaultProvider: any VaultProviding
    private let searchableIndex: CSSearchableIndex

    /// Groups all Quartz note items so they can be cleared when switching vaults or reindexing.
    private static let domainIdentifier = "com.quartz.spotlight.notes"

    public init(vaultProvider: any VaultProviding, searchableIndex: CSSearchableIndex = .default()) {
        self.vaultProvider = vaultProvider
        self.searchableIndex = searchableIndex
    }

    // MARK: - Public

    /// Removes every indexed note in this app’s Spotlight domain (e.g. before indexing another vault).
    public func removeAllInDomain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            searchableIndex.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { _ in
                continuation.resume()
            }
        }
    }

    /// Removes a single file path from Spotlight (note trashed or deleted).
    public func removeNote(fileURL: URL) async {
        let id = Self.uniqueIdentifier(for: fileURL)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            searchableIndex.deleteSearchableItems(withIdentifiers: [id]) { _ in
                continuation.resume()
            }
        }
    }

    /// After rename or move on disk: drop the old id, index the new location.
    public func relocate(from oldURL: URL, to newURL: URL, vaultRoot: URL) async {
        await removeNote(fileURL: oldURL)
        await indexNote(at: newURL, vaultRoot: vaultRoot)
    }

    /// Indexes or updates one note (e.g. after save).
    public func indexNote(at url: URL, vaultRoot: URL) async {
        guard url.standardizedFileURL.path().hasPrefix(vaultRoot.standardizedFileURL.path()) else { return }
        guard let note = try? await vaultProvider.readNote(at: url) else {
            await removeNote(fileURL: url)
            return
        }
        let item = Self.makeSearchableItem(note: note, fileURL: url)
        await indexItems([item])
    }

    /// Full reindex for the current vault tree (used after load and manual reindex).
    public func indexAllNotes(urls: [URL], vaultRoot: URL) async {
        guard !urls.isEmpty else { return }
        let batchSize = 40
        var start = urls.startIndex
        while start < urls.endIndex {
            let end = urls.index(start, offsetBy: batchSize, limitedBy: urls.endIndex) ?? urls.endIndex
            let batch = urls[start..<end]
            var items: [CSSearchableItem] = []
            for url in batch {
                guard url.standardizedFileURL.path().hasPrefix(vaultRoot.standardizedFileURL.path()),
                      let note = try? await vaultProvider.readNote(at: url) else { continue }
                items.append(Self.makeSearchableItem(note: note, fileURL: url))
            }
            if !items.isEmpty {
                await indexItems(items)
            }
            start = end
        }
    }

    // MARK: - Private

    private func indexItems(_ items: [CSSearchableItem]) async {
        guard !items.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            searchableIndex.indexSearchableItems(items) { _ in
                continuation.resume()
            }
        }
    }

    /// Stable per-file key: standardized path string (matches on-disk identity; updates when the file moves).
    private static func uniqueIdentifier(for url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private static func makeSearchableItem(note: NoteDocument, fileURL: URL) -> CSSearchableItem {
        let id = uniqueIdentifier(for: fileURL)
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.plainText)
        attributes.title = note.displayName
        attributes.contentDescription = excerpt(from: note.body)
        attributes.keywords = note.frontmatter.tags
        attributes.contentModificationDate = note.frontmatter.modifiedAt
        attributes.contentURL = fileURL
        attributes.textContent = note.body
        return CSSearchableItem(
            uniqueIdentifier: id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }

    private static func excerpt(from body: String, maxLen: Int = 240) -> String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxLen else { return t }
        return String(t.prefix(maxLen)) + "…"
    }
}
