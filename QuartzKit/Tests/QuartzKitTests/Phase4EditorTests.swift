import Testing
import Foundation
@testable import QuartzKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Phase 4: Production Editor Integration Tests
// Behavioral tests exercising MarkdownASTHighlighter.parseIncremental(),
// ASTDirtyRegionTracker, and MutationTransaction undo policies
// through actual production APIs — not hand-constructed constants.

// MARK: - Suite 1: AST Incremental Parse Integration

@Suite("Phase4ASTIncrementalParseIntegration")
struct Phase4ASTIncrementalParseIntegrationTests {

    private func makeHighlighter() -> MarkdownASTHighlighter {
        MarkdownASTHighlighter(baseFontSize: 14)
    }

    @Test("Full parse of bold markdown produces bold trait in spans")
    func fullParseBoldProducesBoldTrait() async {
        let h = makeHighlighter()
        let md = "Hello **bold** world"
        let spans = await h.parse(md)
        let boldSpans = spans.filter { $0.traits.bold }
        #expect(!boldSpans.isEmpty, "Should produce at least one bold span for **bold**")
    }

    @Test("Full parse of italic markdown produces italic trait in spans")
    func fullParseItalicProducesItalicTrait() async {
        let h = makeHighlighter()
        let md = "Hello *italic* world"
        let spans = await h.parse(md)
        let italicSpans = spans.filter { $0.traits.italic }
        #expect(!italicSpans.isEmpty, "Should produce at least one italic span for *italic*")
    }

    @Test("Incremental parse after insertion preserves unchanged spans before edit")
    func incrementalPreservesSpansBeforeEdit() async {
        let h = makeHighlighter()
        // Initial parse: "**bold** and plain"
        let original = "**bold** and plain"
        let fullSpans = await h.parse(original)

        // Append " text" at end → "**bold** and plain text"
        let modified = "**bold** and plain text"
        let editRange = NSRange(location: 18, length: 5) // " text" inserted at position 18
        let incrementalSpans = await h.parseIncremental(modified, editRange: editRange, preEditLength: 0)

        // Bold span at start should still exist
        let boldSpans = incrementalSpans.filter { $0.traits.bold }
        #expect(!boldSpans.isEmpty, "Bold span should be preserved after appending text at end")

        // Verify at least some spans from before the edit survived
        let spansBeforeEdit = incrementalSpans.filter { $0.range.location + $0.range.length <= 8 }
        let originalBeforeEdit = fullSpans.filter { $0.range.location + $0.range.length <= 8 }
        #expect(spansBeforeEdit.count >= originalBeforeEdit.count,
                "Spans before edit region should be preserved")
    }

    @Test("Incremental parse: adding bold markers produces bold spans")
    func incrementalAddBoldMarkers() async {
        let h = makeHighlighter()
        let original = "Hello world"
        _ = await h.parse(original)

        // Change "Hello world" → "Hello **world**"
        // In pre-edit: replaced "world" (location:6, length:5) with "**world**" (length:9)
        let modified = "Hello **world**"
        let editRange = NSRange(location: 6, length: 9)
        let spans = await h.parseIncremental(modified, editRange: editRange, preEditLength: 5)

        let boldSpans = spans.filter { $0.traits.bold }
        #expect(!boldSpans.isEmpty, "Adding ** markers should produce bold spans")
    }

    @Test("Incremental parse: code fence triggers full reparse")
    func codeFenceTriggersFullReparse() async {
        let h = makeHighlighter()
        let original = "Hello world\n\nSome text"
        _ = await h.parse(original)

        // Insert code fence: "Hello world\n\n```swift\ncode\n```\n\nSome text"
        let modified = "Hello world\n\n```swift\ncode\n```\n\nSome text"
        let insertedText = "```swift\ncode\n```\n\n"
        let editRange = NSRange(location: 13, length: insertedText.count)
        let spans = await h.parseIncremental(modified, editRange: editRange, preEditLength: 0)

        // Code fence boundary detected → falls back to full parse, still returns valid spans
        #expect(!spans.isEmpty, "Code fence edit should still return valid spans (via full reparse)")
    }

    @Test("Incremental parse: delete heading prefix removes heading span")
    func deleteHeadingPrefixRemovesHeadingSpan() async {
        let h = makeHighlighter()
        let original = "# Heading\n\nBody text"
        _ = await h.parse(original)

        // Delete "# " → "Heading\n\nBody text"
        let modified = "Heading\n\nBody text"
        let editRange = NSRange(location: 0, length: 0) // After deletion, nothing at location 0
        let spans = await h.parseIncremental(modified, editRange: editRange, preEditLength: 2)

        // The heading should no longer produce a bold heading span at position 0
        let firstLineHasBoldHeading = spans.contains { span in
            span.range.location == 0 && span.traits.bold
        }
        // After removing "# " prefix, the text "Heading" is plain — no bold
        #expect(!firstLineHasBoldHeading, "Removing heading prefix should remove heading bold style")
    }

    @Test("Incremental parse: insert at document start shifts all subsequent spans")
    func insertAtDocStartShiftsSpans() async {
        let h = makeHighlighter()
        let original = "**bold** text"
        let fullSpans = await h.parse(original)
        let originalBoldLoc = fullSpans.first { $0.traits.bold }?.range.location ?? -1

        // Insert "Prefix " at start → "Prefix **bold** text"
        let modified = "Prefix **bold** text"
        let editRange = NSRange(location: 0, length: 7) // "Prefix " inserted
        let spans = await h.parseIncremental(modified, editRange: editRange, preEditLength: 0)

        let newBoldSpan = spans.first(where: { $0.traits.bold })
        #expect(newBoldSpan != nil, "Bold span should still exist after prefix insertion")
        if let newBold = newBoldSpan, originalBoldLoc >= 0 {
            #expect(newBold.range.location > originalBoldLoc,
                    "Bold span should be shifted right after prefix insertion")
        }
    }

    @Test("Empty document incremental parse does not crash")
    func emptyDocIncrementalParse() async {
        let h = makeHighlighter()
        _ = await h.parse("x") // seed cache with non-empty
        let spans = await h.parseIncremental("", editRange: NSRange(location: 0, length: 0), preEditLength: 1)
        // Falls back to full parse on empty doc — should return empty spans, not crash
        #expect(spans.isEmpty, "Empty document should produce no spans")
    }

    @Test("Multi-paragraph edit triggers dirty region expansion")
    func multiParagraphEditExpandsDirtyRegion() async {
        let h = makeHighlighter()
        let original = "# Heading\n\nParagraph one.\n\nParagraph two."
        _ = await h.parse(original)

        // Replace "Paragraph one.\n\nParagraph two." with "New content."
        let modified = "# Heading\n\nNew content."
        let editRange = NSRange(location: 12, length: 12) // "New content."
        let preEditLen = "Paragraph one.\n\nParagraph two.".count
        let spans = await h.parseIncremental(modified, editRange: editRange, preEditLength: preEditLen)

        // Should return valid spans — heading should still be present
        let headingSpans = spans.filter { $0.traits.bold }
        #expect(!headingSpans.isEmpty, "Heading span should survive multi-paragraph edit below it")
    }
}

// MARK: - Suite 2: ASTDirtyRegionTracker Behavioral

@Suite("Phase4ASTDirtyRegionTrackerBehavioral")
struct Phase4ASTDirtyRegionTrackerBehavioralTests {

    @Test("Edit mid-paragraph: dirty range covers full paragraph")
    func editMidParagraphCoversFullParagraph() {
        let text = "First paragraph.\n\nSecond paragraph here.\n\nThird paragraph."
        // Edit in "Second" — location ~19, length 1
        let editRange = NSRange(location: 22, length: 1)
        let dirty = ASTDirtyRegionTracker.dirtyRange(in: text, editRange: editRange)

        #expect(dirty != nil)
        if let dirty {
            // Should cover at least the full "Second paragraph here.\n" line
            let secondParagraphStart = 18 // after "First paragraph.\n\n"
            let secondParagraphEnd = 40   // "Second paragraph here.\n"
            #expect(dirty.location <= secondParagraphStart, "Dirty range should start at or before second paragraph")
            #expect(dirty.location + dirty.length >= secondParagraphEnd, "Dirty range should extend to end of second paragraph")
        }
    }

    @Test("Edit at paragraph boundary: expanded range covers ±1 paragraph")
    func editAtParagraphBoundaryExpandsContext() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        // Edit at the newline between first and second paragraphs
        let editRange = NSRange(location: 17, length: 0)
        let expanded = ASTDirtyRegionTracker.expandedDirtyRange(in: text, editRange: editRange)

        #expect(expanded != nil)
        if let expanded {
            // Expanded should include first paragraph and second paragraph
            #expect(expanded.location == 0, "Expanded range should reach back to document start")
            #expect(expanded.location + expanded.length > 18, "Expanded range should extend into second paragraph")
        }
    }

    @Test("Code fence in dirty region detected correctly")
    func codeFenceInDirtyRegionDetected() {
        let text = "Some text\n\n```swift\nlet x = 1\n```\n\nMore text"
        // Dirty range covering the code fence
        let codeFenceRange = NSRange(location: 11, length: 22) // "```swift\nlet x = 1\n```"
        let hasFence = ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: codeFenceRange)
        #expect(hasFence, "Should detect ``` as code fence boundary")
    }

    @Test("Code fence with tildes detected")
    func tildeFenceDetected() {
        let text = "Before\n\n~~~python\nprint('hi')\n~~~\n\nAfter"
        let range = NSRange(location: 8, length: 25)
        let hasFence = ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range)
        #expect(hasFence, "Should detect ~~~ as code fence boundary")
    }

    @Test("Edit in list item: dirty range covers list item paragraph")
    func editInListItemCoversListParagraph() {
        let text = "# Heading\n\n- Item one\n- Item two\n- Item three\n\nFooter"
        // Edit inside "Item two" at approximate location 24
        let editRange = NSRange(location: 24, length: 1)
        let dirty = ASTDirtyRegionTracker.dirtyRange(in: text, editRange: editRange)

        #expect(dirty != nil)
        if let dirty {
            // Should cover at least the "- Item two\n" line
            let nsText = text as NSString
            let dirtySubstring = nsText.substring(with: dirty)
            #expect(dirtySubstring.contains("Item two"), "Dirty range should cover the edited list item")
        }
    }

    @Test("Edit spanning multiple paragraphs: merged dirty range")
    func editSpanningMultipleParagraphs() {
        let text = "Para one.\n\nPara two.\n\nPara three."
        // Edit spanning from para one into para two
        let editRange = NSRange(location: 5, length: 20)
        let dirty = ASTDirtyRegionTracker.dirtyRange(in: text, editRange: editRange)

        #expect(dirty != nil)
        if let dirty {
            #expect(dirty.location == 0, "Should start at beginning of first paragraph")
            #expect(dirty.length > 20, "Should cover both affected paragraphs")
        }
    }

    @Test("Pre-edit coordinates convert correctly to post-edit dirty range")
    func preEditCoordinatesConvertCorrectly() {
        // "Hello world" → "Hello beautiful world" (insert "beautiful " at position 6)
        let postEditText = "Hello beautiful world"
        let preEditRange = NSRange(location: 6, length: 0) // insertion point
        let replacementLength = 10 // "beautiful "

        let dirty = ASTDirtyRegionTracker.dirtyRange(
            in: postEditText,
            preEditRange: preEditRange,
            replacementLength: replacementLength
        )

        #expect(dirty != nil)
        if let dirty {
            // Should cover the region where "beautiful " was inserted
            #expect(dirty.location <= 6, "Dirty range should include insertion point")
            #expect(dirty.location + dirty.length >= 16, "Dirty range should cover inserted text")
        }
    }
}

// MARK: - Suite 3: MutationTransaction Undo Policy Behavioral

@Suite("Phase4MutationTransactionUndoPolicy")
struct Phase4MutationTransactionUndoPolicyTests {

    @Test("userTyping groups with previous for native coalescing")
    func userTypingGroupsWithPrevious() {
        let tx = MutationTransaction(
            origin: .userTyping,
            editedRange: NSRange(location: 0, length: 1),
            replacementLength: 1
        )
        #expect(tx.registersUndo, "userTyping should register undo")
        #expect(tx.groupsWithPrevious, "userTyping should group with previous for character coalescing")
        #expect(!tx.needsExplicitUndoGroup, "userTyping uses native grouping, not explicit")
        #expect(!tx.clearsUndoStack, "userTyping should not clear undo stack")
    }

    @Test("formatting creates explicit undo group")
    func formattingCreatesExplicitGroup() {
        let tx = MutationTransaction(
            origin: .formatting,
            editedRange: NSRange(location: 5, length: 4),
            replacementLength: 8
        )
        #expect(tx.registersUndo, "formatting should register undo")
        #expect(tx.needsExplicitUndoGroup, "formatting should use explicit undo group")
        #expect(!tx.groupsWithPrevious, "formatting should not group with previous")
    }

    @Test("syncMerge clears undo stack and does not register")
    func syncMergeClearsStack() {
        let tx = MutationTransaction(
            origin: .syncMerge,
            editedRange: NSRange(location: 0, length: 100),
            replacementLength: 120
        )
        #expect(!tx.registersUndo, "syncMerge should NOT register undo")
        #expect(tx.clearsUndoStack, "syncMerge should clear undo stack")
        #expect(!tx.needsExplicitUndoGroup, "syncMerge should not need explicit group")
    }

    @Test("writingTools does not register undo")
    func writingToolsNoUndo() {
        let tx = MutationTransaction(
            origin: .writingTools,
            editedRange: NSRange(location: 0, length: 10),
            replacementLength: 15
        )
        #expect(!tx.registersUndo, "writingTools should NOT register undo (system-managed)")
        #expect(!tx.clearsUndoStack, "writingTools should not clear stack")
        #expect(!tx.needsExplicitUndoGroup, "writingTools should not use explicit group")
    }

    @Test("listContinuation creates explicit group, does not coalesce")
    func listContinuationExplicitGroupNoCoalesce() {
        let tx = MutationTransaction(
            origin: .listContinuation,
            editedRange: NSRange(location: 20, length: 0),
            replacementLength: 5
        )
        #expect(tx.registersUndo, "listContinuation should register undo")
        #expect(tx.needsExplicitUndoGroup, "listContinuation should use explicit undo group")
        #expect(!tx.groupsWithPrevious, "listContinuation should NOT group with previous")
    }

    @Test("All 9 MutationOrigin cases have correct undo policy tuple")
    func allOriginsHaveCorrectPolicyTuple() {
        // Expected policy matrix: (registersUndo, clearsUndoStack, groupsWithPrevious, needsExplicitUndoGroup)
        let expectations: [(MutationOrigin, Bool, Bool, Bool, Bool)] = [
            (.userTyping,       true,  false, true,  false),
            (.listContinuation, true,  false, false, true),
            (.formatting,       true,  false, false, true),
            (.aiInsert,         true,  false, false, true),
            (.syncMerge,        false, true,  false, false),
            (.pasteOrDrop,      true,  false, false, true),
            (.writingTools,     false, false, false, false),
            (.taskToggle,       true,  false, false, true),
            (.tableNavigation,  true,  false, false, true),
        ]

        for (origin, regUndo, clearsStack, groupsPrev, needsExplicit) in expectations {
            let tx = MutationTransaction(
                origin: origin,
                editedRange: NSRange(location: 0, length: 1),
                replacementLength: 1
            )
            #expect(tx.registersUndo == regUndo,
                    "\(origin.rawValue): registersUndo should be \(regUndo)")
            #expect(tx.clearsUndoStack == clearsStack,
                    "\(origin.rawValue): clearsUndoStack should be \(clearsStack)")
            #expect(tx.groupsWithPrevious == groupsPrev,
                    "\(origin.rawValue): groupsWithPrevious should be \(groupsPrev)")
            #expect(tx.needsExplicitUndoGroup == needsExplicit,
                    "\(origin.rawValue): needsExplicitUndoGroup should be \(needsExplicit)")
        }
    }

    @Test("Highlight policy: userTyping prefers incremental, formatting prefers full")
    func highlightPolicyCorrect() {
        let typing = MutationTransaction(origin: .userTyping, editedRange: NSRange(location: 0, length: 1), replacementLength: 1)
        let formatting = MutationTransaction(origin: .formatting, editedRange: NSRange(location: 0, length: 1), replacementLength: 1)
        let sync = MutationTransaction(origin: .syncMerge, editedRange: NSRange(location: 0, length: 1), replacementLength: 1)

        #expect(typing.prefersIncrementalHighlight, "userTyping should prefer incremental highlight")
        #expect(!formatting.prefersIncrementalHighlight, "formatting should NOT prefer incremental highlight")
        #expect(!sync.prefersIncrementalHighlight, "syncMerge should NOT prefer incremental highlight")
    }

    @Test("All CaseIterable origins are covered")
    func allOriginsAreCaseIterable() {
        let allOrigins = MutationOrigin.allCases
        #expect(allOrigins.count == 9, "Should have exactly 9 MutationOrigin cases")

        // Verify each case can create a valid transaction
        for origin in allOrigins {
            let tx = MutationTransaction(origin: origin, editedRange: NSRange(location: 0, length: 0), replacementLength: 0)
            #expect(tx.origin == origin)
        }
    }
}

// MARK: - Suite 4: Editor Cursor & Selection Stability

@Suite("Phase4EditorCursorSelectionStability")
struct Phase4EditorCursorSelectionStabilityTests {

    @Test("Highlighter does not lose cached spans after repeated parses")
    func highlighterCacheStability() async {
        let h = MarkdownASTHighlighter(baseFontSize: 14)
        let md = "# Title\n\n**Bold** and *italic*"

        let spans1 = await h.parse(md)
        let spans2 = await h.parse(md)

        // Same input should produce same span count
        #expect(spans1.count == spans2.count,
                "Repeated parses of identical content should produce same span count")
    }

    @Test("Incremental parse with zero-length edit range does not crash")
    func incrementalZeroLengthEdit() async {
        let h = MarkdownASTHighlighter(baseFontSize: 14)
        let md = "Hello **bold** world"
        _ = await h.parse(md)

        // Zero-length edit (cursor position, no actual change)
        let spans = await h.parseIncremental(md, editRange: NSRange(location: 5, length: 0), preEditLength: 0)
        #expect(spans.count > 0, "Zero-length edit should still return valid spans")
    }

    @Test("Large document (1000 lines) full parse completes")
    func largeDocFullParseCompletes() async {
        let h = MarkdownASTHighlighter(baseFontSize: 14)
        var lines: [String] = []
        for i in 0..<1000 {
            if i % 10 == 0 {
                lines.append("## Section \(i)")
            } else if i % 5 == 0 {
                lines.append("- List item **bold** and *italic*")
            } else {
                lines.append("Regular paragraph text with some content line \(i).")
            }
            lines.append("")
        }
        let md = lines.joined(separator: "\n")

        let spans = await h.parse(md)
        #expect(!spans.isEmpty, "Large document should produce spans")

        // Should have bold and italic spans from the list items
        let boldSpans = spans.filter { $0.traits.bold }
        let italicSpans = spans.filter { $0.traits.italic }
        #expect(!boldSpans.isEmpty, "Should detect bold in large document")
        #expect(!italicSpans.isEmpty, "Should detect italic in large document")
    }
}

// MARK: - Suite 5: TextKit 2 Integration Paths

@Suite("Phase4TextKit2IntegrationPaths")
struct Phase4TextKit2IntegrationPathsTests {

    @Test("TextKit2 stack wires content manager to NSTextLayoutManager")
    @MainActor
    func textKit2StackWiresLayoutManager() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (layoutManager, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        #expect(contentManager.textLayoutManagers.contains { $0 === layoutManager })
        #expect(layoutManager.textContainer === container)
    }

    @Test("MarkdownTextContentManager mutates backing storage through TextKit2 transactions")
    @MainActor
    func contentManagerEditingTransactionMutatesBackingStore() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        _ = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        contentManager.performEditingTransaction {
            contentManager.textStorage?.setAttributedString(
                NSMutableAttributedString(
                    string: "Hello\nWorld",
                    attributes: [.font: PlatformFont.systemFont(ofSize: 14)]
                )
            )
        }

        contentManager.performMarkdownEdit {
            contentManager.textStorage?.mutableString.append("\nTextKit 2")
        }

        let paragraphRange = contentManager.boundingRangeForParagraph(containing: 7)
        #expect(contentManager.attributedString?.string == "Hello\nWorld\nTextKit 2")
        #expect(paragraphRange == NSRange(location: 6, length: 6))
    }

    @Test("Paragraph union tracks multi-paragraph edits for incremental invalidation")
    @MainActor
    func paragraphUnionTracksMultiParagraphEdits() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        contentManager.attributedString = NSAttributedString(string: "One\nTwo\nThree\nFour")

        let affectedRange = contentManager.boundingRangeForParagraphs(intersecting: NSRange(location: 2, length: 8))
        #expect(affectedRange == NSRange(location: 0, length: 14))
    }

    @Test("Representable source wires MarkdownTextKit2Stack on both platforms")
    func representableSourceUsesTextKit2Factory() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift")
        let content = try String(contentsOf: sourceURL, encoding: .utf8)

        let makeCount = content.components(separatedBy: "MarkdownTextKit2Stack.makeContentManager()").count - 1
        let wireCount = content.components(separatedBy: "MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)").count - 1

        #expect(makeCount == 2, "Both the iOS and macOS representables must construct the shared TextKit2 stack")
        #expect(wireCount == 2, "Both the iOS and macOS representables must wire the shared TextKit2 stack")
    }
}

#if canImport(AppKit)
private typealias PlatformFont = NSFont
#elseif canImport(UIKit)
private typealias PlatformFont = UIFont
#endif
