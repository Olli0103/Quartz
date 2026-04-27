import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum RendererDiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct RendererDiagnosticRange: Codable, Sendable, Equatable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ range: NSRange) {
        self.location = range.location
        self.length = range.length
    }

    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

public struct RendererDiagnosticLineRange: Codable, Sendable, Equatable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct RendererDiagnosticEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: RendererDiagnosticLevel
    public let name: String
    public let noteBasename: String?
    public let affectedRange: RendererDiagnosticRange?
    public let lineRange: RendererDiagnosticLineRange?
    public let textRevision: UInt64?
    public let renderGeneration: UInt64?
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: RendererDiagnosticLevel = .info,
        name: String,
        noteBasename: String? = nil,
        affectedRange: RendererDiagnosticRange? = nil,
        lineRange: RendererDiagnosticLineRange? = nil,
        textRevision: UInt64? = nil,
        renderGeneration: UInt64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.name = name
        self.noteBasename = noteBasename
        self.affectedRange = affectedRange
        self.lineRange = lineRange
        self.textRevision = textRevision
        self.renderGeneration = renderGeneration
        self.metadata = Self.sanitizedMetadata(metadata)
    }

    private static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        let safeTextKeys: Set<String> = ["textLength", "oldTextLength", "newTextLength", "loadedTextLength", "textRevision", "textChecksum"]
        var result: [String: String] = [:]
        for (key, value) in metadata {
            if key.localizedCaseInsensitiveContains("text"), !safeTextKeys.contains(key) {
                result[key] = "<redacted>"
                continue
            }
            let normalized = value
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\\n")
            result[key] = String(normalized.prefix(160))
        }
        return result
    }
}

public struct RendererDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let enablementHint: String
    public let lastEvents: [RendererDiagnosticEvent]
    public let warningsAndErrors: [RendererDiagnosticEvent]
    public let lastRenderDurations: [String]
    public let lastSpanChecksums: [String]
    public let corruptionSignals: [RendererDiagnosticEvent]
}

public actor RendererDiagnosticsStore {
    public static let shared = RendererDiagnosticsStore()
    public static let defaultCapacity = 300

    private var capacity: Int
    private var events: [RendererDiagnosticEvent] = []
    private var lastSpanChecksumByTextChecksum: [String: String] = [:]

    public init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func record(_ event: RendererDiagnosticEvent) {
        append(event)
        observeSpanStability(from: event)
    }

    public func reset() {
        capacity = Self.defaultCapacity
        events.removeAll()
        lastSpanChecksumByTextChecksum.removeAll()
    }

    public func setCapacity(_ capacity: Int) {
        self.capacity = max(1, min(capacity, 5_000))
        if events.count > self.capacity {
            events.removeFirst(events.count - self.capacity)
        }
    }

    public func snapshot(enabled: Bool) -> RendererDiagnosticsSnapshot {
        let recentEvents = Array(events.suffix(120))
        let warnings = events.filter { $0.level == .warning || $0.level == .error }.suffix(40)
        let durations = events.compactMap { event -> String? in
            guard let duration = event.metadata["durationMs"] else { return nil }
            return "\(event.name): \(duration) ms"
        }.suffix(20)
        let checksums = events.compactMap { event -> String? in
            guard let checksum = event.metadata["spanChecksum"] else { return nil }
            let note = event.noteBasename ?? "unknown"
            return "\(event.name) \(note): \(checksum)"
        }.suffix(20)
        let signals = events.filter {
            $0.name.hasPrefix("corruption.") || $0.metadata["corruptionSignal"] == "true"
        }.suffix(40)

        return RendererDiagnosticsSnapshot(
            enabled: enabled,
            enablementHint: RendererDiagnostics.enablementHint,
            lastEvents: recentEvents,
            warningsAndErrors: Array(warnings),
            lastRenderDurations: Array(durations),
            lastSpanChecksums: Array(checksums),
            corruptionSignals: Array(signals)
        )
    }

    private func append(_ event: RendererDiagnosticEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    private func observeSpanStability(from event: RendererDiagnosticEvent) {
        guard let textChecksum = event.metadata["textChecksum"],
              let spanChecksum = event.metadata["spanChecksum"],
              !textChecksum.isEmpty,
              !spanChecksum.isEmpty else {
            return
        }

        if let previous = lastSpanChecksumByTextChecksum[textChecksum], previous != spanChecksum {
            append(RendererDiagnosticEvent(
                level: .warning,
                name: "corruption.loadReopenSpanChecksumMismatch",
                noteBasename: event.noteBasename,
                textRevision: event.textRevision,
                renderGeneration: event.renderGeneration,
                metadata: [
                    "textChecksum": textChecksum,
                    "previousSpanChecksum": previous,
                    "spanChecksum": spanChecksum,
                    "sourceEvent": event.name,
                    "corruptionSignal": "true"
                ]
            ))
        }
        lastSpanChecksumByTextChecksum[textChecksum] = spanChecksum
    }
}

public enum RendererDiagnostics {
    public static let userDefaultsKey = "quartz.editor.rendererDiagnosticsEnabled"
    public static let enablementHint = "Enable Settings > Editor > Advanced > Enable Renderer Diagnostics, launch with -QuartzRendererDiagnostics, or set QUARTZ_RENDERER_DIAGNOSTICS=1."

    public static var isEnabled: Bool {
        if UserDefaults.standard.bool(forKey: userDefaultsKey) {
            return true
        }
        if DeveloperDiagnostics.isRendererDiagnosticsEnabled {
            return true
        }
        if ProcessInfo.processInfo.arguments.contains("-QuartzRendererDiagnostics") {
            return true
        }
        return ProcessInfo.processInfo.environment["QUARTZ_RENDERER_DIAGNOSTICS"] == "1"
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }

    public static func record(_ event: RendererDiagnosticEvent) {
        guard isEnabled else { return }
        Task(priority: .utility) {
            await RendererDiagnosticsStore.shared.record(event)
        }
    }

    public static func snapshot() async -> RendererDiagnosticsSnapshot {
        await RendererDiagnosticsStore.shared.snapshot(enabled: isEnabled)
    }

    public static func resetForTesting() async {
        await RendererDiagnosticsStore.shared.reset()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    public static func spanChecksum(spans: [HighlightSpan], semanticDocument: EditorSemanticDocument) -> String {
        var hasher = FNV1a64()
        for span in spans.sorted(by: spanSort) {
            hasher.combine(spanType(span))
            hasher.combine(span.range.location)
            hasher.combine(span.range.length)
            if let role = span.semanticRole {
                hasher.combine(String(describing: role))
            }
        }
        for block in semanticDocument.blocks {
            hasher.combine(String(describing: block.kind))
            hasher.combine(block.range.location)
            hasher.combine(block.range.length)
            hasher.combine(block.contentRange.location)
            hasher.combine(block.contentRange.length)
        }
        return hasher.hexDigest
    }

    public static func textChecksum(_ text: String) -> String {
        var hasher = FNV1a64()
        hasher.combine((text as NSString).length)
        for scalar in text.unicodeScalars {
            hasher.combine(Int(scalar.value))
        }
        return hasher.hexDigest
    }

    public static func spanSummary(
        spans: [HighlightSpan],
        semanticDocument: EditorSemanticDocument,
        markdown: String,
        editedRange: NSRange?
    ) -> [String: String] {
        let textLength = (markdown as NSString).length
        var counts: [String: Int] = [:]
        var invalidCount = 0
        var outOfBoundsCount = 0
        var tableNearEdit = 0
        var headingNearEdit = 0

        for span in spans {
            let type = spanType(span)
            counts[type, default: 0] += 1
            if !isValid(span.range, textLength: textLength) {
                invalidCount += 1
                if span.range.location < 0 || span.range.length < 0 || span.range.location == NSNotFound || NSMaxRange(span.range) > textLength {
                    outOfBoundsCount += 1
                }
            }
            if let editedRange, near(span.range, editedRange) {
                if type == "table" { tableNearEdit += 1 }
                if type == "heading" { headingNearEdit += 1 }
            }
        }

        var metadata: [String: String] = [
            "spanCount": "\(spans.count)",
            "invalidSpanCount": "\(invalidCount)",
            "outOfBoundsSpanCount": "\(outOfBoundsCount)",
            "headingCount": "\(counts["heading", default: 0])",
            "tableCount": "\(counts["table", default: 0])",
            "listCount": "\(semanticDocument.blocks.filter { if case .listItem = $0.kind { return true }; return false }.count)",
            "codeCount": "\(counts["codeBlock", default: 0] + counts["inlineCode", default: 0])",
            "linkCount": "\(counts["link", default: 0])",
            "tableSpansNearEdit": "\(tableNearEdit)",
            "headingSpansNearEdit": "\(headingNearEdit)"
        ]
        for (key, count) in counts.sorted(by: { $0.key < $1.key }) {
            metadata["spanType.\(key)"] = "\(count)"
        }
        return metadata
    }

    public static func detectCorruptionSignals(
        spans: [HighlightSpan],
        semanticDocument: EditorSemanticDocument,
        markdown: String,
        noteBasename: String?,
        editedRange: NSRange?,
        textRevision: UInt64,
        renderGeneration: UInt64
    ) -> [RendererDiagnosticEvent] {
        let nsMarkdown = markdown as NSString
        let textLength = nsMarkdown.length
        var events: [RendererDiagnosticEvent] = []

        for span in spans where !isValid(span.range, textLength: textLength) {
            events.append(warning(
                name: span.range.location == NSNotFound || span.range.location < 0 || span.range.length < 0
                    ? "corruption.invalidSpanRange"
                    : "corruption.spanOutOfBounds",
                noteBasename: noteBasename,
                range: span.range,
                markdown: nsMarkdown,
                spanType: spanType(span),
                textRevision: textRevision,
                renderGeneration: renderGeneration
            ))
        }

        for block in semanticDocument.blocks {
            if !isValid(block.range, textLength: textLength) || !isValid(block.contentRange, textLength: textLength) {
                events.append(warning(
                    name: "corruption.semanticBlockOutOfBounds",
                    noteBasename: noteBasename,
                    range: block.range,
                    markdown: nsMarkdown,
                    spanType: String(describing: block.kind),
                    textRevision: textRevision,
                    renderGeneration: renderGeneration
                ))
            }
        }

        events.append(contentsOf: detectHeadingCoverageSignals(
            spans: spans,
            semanticDocument: semanticDocument,
            markdown: nsMarkdown,
            noteBasename: noteBasename,
            textRevision: textRevision,
            renderGeneration: renderGeneration
        ))
        events.append(contentsOf: detectTableBleedSignals(
            spans: spans,
            semanticDocument: semanticDocument,
            markdown: nsMarkdown,
            noteBasename: noteBasename,
            textRevision: textRevision,
            renderGeneration: renderGeneration
        ))
        events.append(contentsOf: detectImpossibleBlockOverlaps(
            semanticDocument: semanticDocument,
            markdown: nsMarkdown,
            noteBasename: noteBasename,
            textRevision: textRevision,
            renderGeneration: renderGeneration
        ))

        return events
    }

    public static func attributeKeys(_ attributes: [NSAttributedString.Key: Any]) -> [String] {
        attributes.keys.map(\.rawValue).sorted()
    }

    public static func unsafeTypingAttributeKeys(in attributes: [NSAttributedString.Key: Any]) -> [String] {
        let unsafe: Set<NSAttributedString.Key> = [
            .kern,
            .quartzTableRowStyle,
            .backgroundColor,
            .attachment,
            .quartzWikiLink,
            .underlineStyle,
            .strikethroughStyle,
            .link
        ]
        return attributes.keys.filter { unsafe.contains($0) }.map(\.rawValue).sorted()
    }

    private static func detectHeadingCoverageSignals(
        spans: [HighlightSpan],
        semanticDocument: EditorSemanticDocument,
        markdown: NSString,
        noteBasename: String?,
        textRevision: UInt64,
        renderGeneration: UInt64
    ) -> [RendererDiagnosticEvent] {
        let headingSpans = spans.filter {
            if case .heading = $0.semanticRole { return true }
            return false
        }
        return semanticDocument.blocks.compactMap { block in
            guard case .heading = block.kind else { return nil }
            let covered = headingSpans.contains {
                $0.range.location <= block.contentRange.location
                    && NSMaxRange($0.range) >= NSMaxRange(block.contentRange)
            }
            guard !covered else { return nil }
            return warning(
                name: "corruption.headingSpanIncomplete",
                noteBasename: noteBasename,
                range: block.contentRange,
                markdown: markdown,
                spanType: String(describing: block.kind),
                textRevision: textRevision,
                renderGeneration: renderGeneration
            )
        }
    }

    private static func detectTableBleedSignals(
        spans: [HighlightSpan],
        semanticDocument: EditorSemanticDocument,
        markdown: NSString,
        noteBasename: String?,
        textRevision: UInt64,
        renderGeneration: UInt64
    ) -> [RendererDiagnosticEvent] {
        let tableSpans = spans.filter { $0.tableRowStyle != nil }
        guard !tableSpans.isEmpty else { return [] }
        var events: [RendererDiagnosticEvent] = []

        for span in tableSpans {
            let intersectingBlocks = semanticDocument.blocks.filter {
                NSIntersectionRange($0.range, span.range).length > 0
            }
            for block in intersectingBlocks {
                guard case .tableRow = block.kind else {
                    events.append(warning(
                        name: "corruption.tableSpanBleedsIntoNonTableBlock",
                        noteBasename: noteBasename,
                        range: span.range,
                        markdown: markdown,
                        spanType: String(describing: block.kind),
                        textRevision: textRevision,
                        renderGeneration: renderGeneration
                    ))
                    continue
                }
                if span.range.location < block.range.location || NSMaxRange(span.range) > NSMaxRange(block.range) {
                    events.append(warning(
                        name: "corruption.tableSpanBleedsOutsideRow",
                        noteBasename: noteBasename,
                        range: span.range,
                        markdown: markdown,
                        spanType: "table",
                        textRevision: textRevision,
                        renderGeneration: renderGeneration
                    ))
                }
            }
        }

        return events
    }

    private static func detectImpossibleBlockOverlaps(
        semanticDocument: EditorSemanticDocument,
        markdown: NSString,
        noteBasename: String?,
        textRevision: UInt64,
        renderGeneration: UInt64
    ) -> [RendererDiagnosticEvent] {
        let blocks = semanticDocument.blocks.sorted { $0.range.location < $1.range.location }
        var events: [RendererDiagnosticEvent] = []
        for pair in zip(blocks, blocks.dropFirst()) {
            let lhs = pair.0
            let rhs = pair.1
            guard lhs.range.length > 0,
                  rhs.range.length > 0,
                  NSIntersectionRange(lhs.range, rhs.range).length > 0 else {
                continue
            }
            events.append(warning(
                name: "corruption.impossibleBlockOverlap",
                noteBasename: noteBasename,
                range: NSIntersectionRange(lhs.range, rhs.range),
                markdown: markdown,
                spanType: "\(lhs.kind)|\(rhs.kind)",
                textRevision: textRevision,
                renderGeneration: renderGeneration
            ))
        }
        return events
    }

    private static func warning(
        name: String,
        noteBasename: String?,
        range: NSRange,
        markdown: NSString,
        spanType: String,
        textRevision: UInt64,
        renderGeneration: UInt64
    ) -> RendererDiagnosticEvent {
        RendererDiagnosticEvent(
            level: .warning,
            name: name,
            noteBasename: noteBasename,
            affectedRange: RendererDiagnosticRange(range),
            lineRange: lineRange(for: range, in: markdown),
            textRevision: textRevision,
            renderGeneration: renderGeneration,
            metadata: [
                "spanType": spanType,
                "corruptionSignal": "true"
            ]
        )
    }

    private static func lineRange(for range: NSRange, in markdown: NSString) -> RendererDiagnosticLineRange? {
        guard markdown.length > 0,
              range.location != NSNotFound,
              range.location >= 0 else {
            return nil
        }
        let startLocation = min(range.location, max(markdown.length - 1, 0))
        let endLocation = min(max(NSMaxRange(range) - 1, startLocation), max(markdown.length - 1, 0))
        return RendererDiagnosticLineRange(
            start: lineNumber(containing: startLocation, in: markdown),
            end: lineNumber(containing: endLocation, in: markdown)
        )
    }

    private static func lineNumber(containing location: Int, in markdown: NSString) -> Int {
        var line = 1
        var cursor = 0
        while cursor < min(location, markdown.length) {
            let scalar = markdown.character(at: cursor)
            if scalar == 10 {
                line += 1
            }
            cursor += 1
        }
        return line
    }

    private static func near(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        let expanded = NSRange(location: max(0, rhs.location - 160), length: rhs.length + 320)
        return NSIntersectionRange(lhs, expanded).length > 0
    }

    private static func isValid(_ range: NSRange, textLength: Int) -> Bool {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0 else {
            return false
        }
        return NSMaxRange(range) <= textLength
    }

    private static func spanSort(_ lhs: HighlightSpan, _ rhs: HighlightSpan) -> Bool {
        if lhs.range.location == rhs.range.location {
            if lhs.range.length == rhs.range.length {
                return spanType(lhs) < spanType(rhs)
            }
            return lhs.range.length < rhs.range.length
        }
        return lhs.range.location < rhs.range.location
    }

    private static func spanType(_ span: HighlightSpan) -> String {
        if span.tableRowStyle != nil { return "table" }
        if span.wikiLinkTitle != nil { return "link" }
        if span.attachment != nil { return "attachment" }
        switch span.semanticRole {
        case .heading?: return "heading"
        case .bold?: return "bold"
        case .italic?: return "italic"
        case .inlineCode?: return "inlineCode"
        case .strikethrough?: return "strikethrough"
        case .blockquote?: return "blockquote"
        case .codeBlock?: return "codeBlock"
        case nil: break
        }
        if span.isOverlay { return "overlay" }
        return "primary"
    }
}

private struct FNV1a64 {
    private var value: UInt64 = 0xcbf29ce484222325

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
    }

    mutating func combine(_ integer: Int) {
        combine(String(integer))
        combine("|")
    }

    var hexDigest: String {
        String(format: "%016llx", value)
    }
}
