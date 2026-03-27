# Markdown Editor Architecture Research

**Date:** March 2026
**Purpose:** Evaluate approaches for building a premium native markdown editor on Apple platforms

---

## Executive Summary

Based on extensive research, **Quartz's current architecture is fundamentally sound** but requires enhancements for inline rendering. The combination of **swift-markdown + TextKit 2** is the correct choice for a premium Apple-native editor. The main gap is cursor-aware inline rendering (showing/hiding syntax characters based on cursor position).

### Key Recommendations

1. **Keep swift-markdown** - Apple's official parser with full AST access
2. **Keep TextKit 2** - The future-proof choice for Apple platforms
3. **Implement cursor-aware rendering** via NSTextLayoutFragment subclassing
4. **Add incremental parsing** for large document performance

---

## 1. Markdown Parsing Libraries Comparison

### swift-markdown (Apple) - **RECOMMENDED**

**Repository:** https://github.com/swiftlang/swift-markdown

| Criteria | Evaluation |
|----------|------------|
| **Parsing Speed** | Fast (based on cmark-gfm C implementation) |
| **GFM Support** | Full (tables, checkboxes, strikethrough) |
| **AST Access** | Excellent - full tree with SourceRange positions |
| **Maintenance** | Active (Apple official, v0.7.3 Oct 2025) |
| **Platform Support** | All Apple platforms |

**Strengths:**
- Official Apple library ensures long-term support
- Provides precise source ranges for every AST node (critical for highlighting)
- Immutable, thread-safe, copy-on-write value types (SwiftSyntax-style)
- Swift-native API with visitor pattern
- Used internally by Apple's documentation tools

**Weaknesses:**
- No incremental parsing (full re-parse on edit)
- Limited extension mechanism for custom syntax

**Verdict:** Best choice for Apple-native apps needing AST access.

---

### cmark-gfm (GitHub)

**Repository:** https://github.com/github/cmark-gfm

| Criteria | Evaluation |
|----------|------------|
| **Parsing Speed** | Excellent ("War and Peace in 127ms") |
| **GFM Support** | Full (the reference implementation) |
| **AST Access** | Via C API, requires bridging |
| **Maintenance** | Active (GitHub official) |
| **Platform Support** | Cross-platform C |

**Note:** swift-markdown is built ON TOP of cmark-gfm, so using swift-markdown gives you cmark-gfm's performance with Swift-native APIs.

---

### Down

**Repository:** https://github.com/johnxnguyen/Down

| Criteria | Evaluation |
|----------|------------|
| **Parsing Speed** | Excellent (cmark v0.29.0 based) |
| **GFM Support** | CommonMark only (no GFM extensions) |
| **AST Access** | Yes, via `toAST()` method |
| **Maintenance** | Moderate (last update 2023) |
| **Platform Support** | iOS 9+, macOS 10.11+, tvOS 9+ |

**Strengths:**
- Multiple output formats (HTML, XML, LaTeX, NSAttributedString)
- Built-in WebView rendering
- Mature, fuzz-tested

**Weaknesses:**
- No GFM table/checkbox support without extensions
- Less active than swift-markdown
- C-based AST access less ergonomic than swift-markdown

---

### Ink (John Sundell)

**Repository:** https://github.com/JohnSundell/Ink

| Criteria | Evaluation |
|----------|------------|
| **Parsing Speed** | Good (aims for O(N) via substring API) |
| **GFM Support** | Partial (tables yes, not full spec) |
| **AST Access** | **NO** - HTML output only |
| **Maintenance** | Low (described as "very young") |
| **Platform Support** | macOS 10.15+, Linux |

**Verdict:** Not suitable for live editing (no AST access).

---

### Markdownosaur

**Repository:** https://github.com/christianselig/Markdownosaur

| Criteria | Evaluation |
|----------|------------|
| **Nature** | Wrapper around swift-markdown |
| **Purpose** | Markdown to NSAttributedString conversion |
| **AST Access** | Uses swift-markdown's AST |
| **Maintenance** | Reference/demo code |

**Note:** Useful as a reference for visitor pattern implementation, but Quartz already has superior implementation in `MarkdownRenderer.swift`.

---

### Parser Recommendation

**Use swift-markdown.** It provides:
- Full GFM support via cmark-gfm underneath
- Swift-native AST with precise source ranges
- Official Apple support and maintenance
- Thread-safe value semantics

**Quartz's current choice is correct.**

---

## 2. Text Editing Frameworks Comparison

### TextKit 2 (Apple) - **RECOMMENDED**

**Documentation:** [WWDC 2021 - Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/)

| Criteria | Evaluation |
|----------|------------|
| **Inline Rendering** | Excellent (custom NSTextLayoutFragment) |
| **Large Documents** | Excellent (viewport-only layout) |
| **Syntax Highlighting** | Good (via text attributes) |
| **Cursor Preservation** | Built-in with proper transaction handling |
| **IME Compatibility** | Native |
| **Platform Support** | iOS 15+, macOS 12+ |

**Architecture (from WWDC):**

```
Storage Layer:
  NSTextElement (immutable building blocks)
  NSTextContentManager/NSTextContentStorage

Layout Layer:
  NSTextLayoutManager (replaces glyph-based NSLayoutManager)
  NSTextLayoutFragment (layout info per element)
  NSTextViewportLayoutController (visible area only)

Selection Layer:
  NSTextSelection (immutable selection state)
  NSTextSelectionNavigation (actions)
```

**Key Advantages:**
1. **Viewport-based layout** - Only layouts visible text, O(1) scroll performance
2. **Glyph abstraction** - Handles complex scripts (Arabic, CJK) correctly
3. **Value semantics** - Immutable objects prevent mutation bugs
4. **Custom layout fragments** - Can render markdown elements with custom drawing

**Customization Hooks for Inline Rendering:**

```swift
// 1. Custom text paragraph for display-only attributes
func textContentStorage(_ storage: NSTextContentStorage,
                       textParagraphWith range: NSRange) -> NSTextParagraph?

// 2. Hide elements without deleting
func textContentManager(_ manager: NSTextContentManager,
                       shouldEnumerate element: NSTextElement,
                       options: NSTextElementProviderEnumerationOptions) -> Bool

// 3. Custom layout fragments for rich rendering
func textLayoutManager(_ manager: NSTextLayoutManager,
                      textLayoutFragmentFor location: NSTextLocation,
                      in element: NSTextElement) -> NSTextLayoutFragment
```

---

### TextKit 1 (Legacy)

| Criteria | Evaluation |
|----------|------------|
| **Inline Rendering** | Possible but harder |
| **Large Documents** | Poor without noncontiguous layout |
| **Platform Support** | All iOS/macOS versions |

**Verdict:** Avoid for new projects. TextKit 2 is the future.

---

### Runestone (Simon Stoevring)

**Repository:** https://github.com/simonbs/Runestone

| Criteria | Evaluation |
|----------|------------|
| **Inline Rendering** | Limited (code editor focus) |
| **Large Documents** | Excellent (Tree-sitter incremental parsing) |
| **Syntax Highlighting** | Excellent (Tree-sitter based) |
| **Platform Support** | iOS, iPad, macOS Catalyst |

**Strengths:**
- Tree-sitter provides incremental parsing (only re-parse changed regions)
- Line-based architecture from AvalonEdit
- Production-quality (used in Scriptable, Jayson)

**Weaknesses:**
- Designed for code editing, not prose
- No native macOS support (Catalyst only)
- Not designed for inline markdown rendering
- GPL-compatible but complex licensing

**Verdict:** Great for code editors, but wrong paradigm for markdown notes.

---

### STTextView (Marcin Krzyzanowski)

**Repository:** https://github.com/krzyzanowskim/STTextView

| Criteria | Evaluation |
|----------|------------|
| **Nature** | Custom TextKit 2 implementation |
| **Purpose** | Address NSTextView TextKit 2 bugs |
| **Platform Support** | macOS 14+, iOS 16+ |

**Key Insight:** The author filed 20+ bugs against Apple's TextKit 2 implementation and created STTextView to work around them.

Custom components:
- `STTextLayoutManager`
- `STTextContentStorage`
- `STTextLayoutFragment`

**Strengths:**
- Fixes many TextKit 2 bugs
- Multi-cursor support
- Plugin architecture for syntax highlighting

**Weaknesses:**
- GPL v3 license (commercial license required)
- macOS-focused, iOS support newer
- Another abstraction layer

**Verdict:** Useful reference for TextKit 2 customization patterns, but the GPL license is problematic for commercial apps. Consider learning from it rather than adopting it.

---

### CodeEditTextView (CodeEdit)

**Repository:** https://github.com/CodeEditApp/CodeEditTextView

| Criteria | Evaluation |
|----------|------------|
| **Nature** | CoreText-based custom view |
| **Purpose** | High-performance code editing |
| **Platform Support** | macOS only |

**Note:** Uses CoreText directly, bypassing TextKit entirely. Designed specifically for code editing in the CodeEdit IDE.

**Verdict:** Not suitable for markdown notes (code-focused, macOS-only).

---

### Framework Recommendation

**Use TextKit 2.** It provides:
- Native platform integration
- Viewport-based layout for performance
- Custom layout fragments for inline rendering
- Future-proof architecture
- Built-in accessibility

**Quartz's current choice is correct.**

---

## 3. Competitor Analysis

### Bear App

**Approach:** Native TextKit-based editor (TextKit 1, likely migrating to 2)

**Editor Characteristics:**
- Inline markdown rendering with cursor-aware syntax hiding
- Custom font handling for headings
- Nested tag system
- Native iOS/macOS with shared core

**Likely Implementation:**
- Custom `NSLayoutManager` subclass for TextKit 1
- Attribute-based styling with `.foregroundColor` manipulation
- Real-time AST diffing for efficient updates

**What Quartz Can Learn:**
- Smooth cursor-position-dependent syntax visibility
- Consistent behavior across platforms
- Premium animation and transitions

---

### iA Writer

**Approach:** Custom markup-based editor

**Editor Characteristics:**
- Focus mode (sentence/paragraph dimming)
- Syntax highlighting for parts of speech
- Style check (grammar analysis)
- Cross-platform (iOS, macOS, Windows)

**Technical Philosophy:**
- Plain text foundation with Markdown
- On-device processing for privacy
- Platform-specific optimization

**What Quartz Can Learn:**
- Focus mode implementation (cursor-aware paragraph styling)
- Writing analysis features
- Premium monospace typography

---

### Obsidian

**Approach:** CodeMirror 6 (web-based)

**Note:** Obsidian uses Electron + CodeMirror, making it non-native. While feature-rich, it lacks:
- Native performance
- Platform-specific behaviors
- System integration

**Verdict:** Not a relevant reference for native implementation.

---

### Ulysses

**Approach:** Markup-based native editor

**Editor Characteristics:**
- Custom markup syntax (Markdown-extended)
- Live preview built-in
- Style switching on-the-fly

**What Quartz Can Learn:**
- Clean separation of markup and preview
- Export format flexibility
- Writing-focused UX

---

### Craft

**Approach:** Block-based editor (non-TextKit)

**Note:** Craft uses a completely different paradigm - block-based editing where each paragraph/element is a separate interactive block. This is fundamentally different from continuous text editing.

**Verdict:** Different paradigm, not directly applicable.

---

## 4. Inline Rendering Implementation Approaches

### The Goal: Cursor-Aware Syntax Hiding

When the cursor is NOT on a line:
```
# Heading      →  [Large Bold] Heading
**bold text** →  [Bold] bold text
```

When the cursor IS on the line:
```
# Heading      →  # Heading
**bold text** →  **bold text**
```

---

### Approach 1: Attribute-Based Hiding (Simplest)

**Mechanism:** Set `.foregroundColor = .clear` for syntax characters when cursor is elsewhere.

```swift
// When cursor moves away from a styled range:
storage.addAttribute(.foregroundColor, value: UIColor.clear, range: syntaxRange)

// When cursor enters the range:
storage.addAttribute(.foregroundColor, value: UIColor.label, range: syntaxRange)
```

**Pros:**
- Simple to implement
- Works with existing TextKit stack
- No custom layout fragments needed

**Cons:**
- Syntax characters still take up space (layout doesn't collapse)
- Can feel "glitchy" if not carefully debounced
- Selection can expose hidden text

**Verdict:** Good starting point, but not Bear-quality.

---

### Approach 2: Custom NSTextLayoutFragment (Recommended)

**Mechanism:** Create custom layout fragments that render markdown elements differently based on cursor position.

```swift
class MarkdownLayoutFragment: NSTextLayoutFragment {
    var isCursorInFragment: Bool = false

    override func draw(at point: CGPoint, in context: CGContext) {
        if isCursorInFragment {
            // Draw raw markdown with syntax characters
            super.draw(at: point, in: context)
        } else {
            // Draw rendered view (hide syntax, apply styling)
            drawRenderedMarkdown(at: point, in: context)
        }
    }
}
```

Hook via delegate:
```swift
func textLayoutManager(_ manager: NSTextLayoutManager,
                      textLayoutFragmentFor location: NSTextLocation,
                      in element: NSTextElement) -> NSTextLayoutFragment {
    // Return custom fragment based on markdown element type
    return MarkdownLayoutFragment(textElement: element, range: element.elementRange)
}
```

**Pros:**
- Full control over rendering
- Can collapse syntax character space
- Native TextKit 2 pattern
- Smooth cursor transitions

**Cons:**
- More complex implementation
- Need to handle cursor tracking
- Platform-specific drawing code

**Verdict:** The correct approach for premium quality.

---

### Approach 3: Real-Time AST Diffing

**Mechanism:** Maintain persistent AST and diff on edits to minimize re-styling.

```swift
actor IncrementalMarkdownParser {
    private var currentAST: Document?
    private var currentText: String = ""

    func updateForEdit(range: NSRange, replacement: String) -> [ASTDiff] {
        // 1. Apply edit to text
        // 2. Re-parse affected paragraphs only
        // 3. Diff old AST vs new AST
        // 4. Return only changed nodes
    }
}
```

**Implementation Details:**
1. Track paragraph boundaries
2. Only re-parse paragraphs that changed
3. Diff AST nodes to find changed styles
4. Apply only changed attributes

**Pros:**
- Minimal attribute updates
- Better performance on large documents
- Enables efficient cursor tracking

**Cons:**
- Complex to implement correctly
- swift-markdown doesn't support incremental parsing natively

**Verdict:** Optimization for later, after basic inline rendering works.

---

### Approach 4: Hybrid (Recommended Path)

**Phase 1:** Attribute-based hiding with debouncing
- Quick win, visible improvement
- Foundation for cursor tracking

**Phase 2:** Custom layout fragments for headings
- Headings are the most visible elements
- Test the custom fragment approach

**Phase 3:** Extend to all inline elements
- Bold, italic, code, links
- Consistent cursor-aware behavior

**Phase 4:** Incremental parsing optimization
- Only for documents > 10,000 characters
- Paragraph-level invalidation

---

## 5. Current Quartz Implementation Review

### Strengths

**MarkdownASTHighlighter.swift:**
- Correct use of swift-markdown AST
- Background parsing with debouncing (80ms)
- Adaptive debounce for large documents
- Clean span-based architecture
- Relative font scales (Dynamic Type ready)

**MarkdownTextView.swift:**
- Proper TextKit 2 stack setup
- Version tracking to reject stale highlights
- IME composition detection (`hasMarkedText()`)
- Selection and typing attribute preservation
- Writing Tools integration (iOS 18.1+)

**MarkdownTextContentManager.swift:**
- Correct `performEditingTransaction` wrapper
- Paragraph-level invalidation helpers
- Clean extension point for AST integration

**MarkdownListContinuation.swift:**
- Comprehensive list marker parsing
- Proper checkbox, numbered, bullet, blockquote support
- Surgical text replacement (not full-document)

### Gaps and Recommendations

**Gap 1: No Cursor-Aware Inline Rendering**

Current state: Syntax highlighting applies fonts/colors, but syntax characters (`#`, `**`, etc.) are always visible.

**Recommendation:** Implement cursor-aware hiding (Approach 2 or hybrid).

---

**Gap 2: Full-Document Re-Highlighting**

Current state: `MarkdownASTHighlighter.parse()` parses the entire document on every edit.

**Recommendation:** Add incremental parsing:
```swift
public func parseIncremental(
    _ markdown: String,
    editedRange: NSRange,
    previousSpans: [HighlightSpan]
) async -> [HighlightSpan] {
    // 1. Find affected paragraphs
    // 2. Re-parse only those paragraphs
    // 3. Merge with unchanged spans
}
```

---

**Gap 3: Missing Markdown Elements**

Current highlighting covers: Heading, Strong, Emphasis, InlineCode, CodeBlock

Missing:
- Links (color only, no underline)
- Blockquotes (indent + left border)
- Strikethrough
- Tables
- Horizontal rules

**Recommendation:** Extend `collectSpans()` for full GFM coverage.

---

**Gap 4: No Custom Layout Fragments**

The `MarkdownTextContentManager` has hooks documented but not implemented.

**Recommendation:** Implement `textLayoutManager(_:textLayoutFragmentFor:in:)` delegate for custom heading rendering.

---

## 6. Final Recommendations

### Should Quartz keep swift-markdown?

**YES.** It's the correct choice because:
- Official Apple library
- Full AST access with source ranges
- GFM support via cmark-gfm
- Swift-native API
- Active maintenance

### Should Quartz keep TextKit 2?

**YES.** It's the correct choice because:
- Future-proof (Apple's direction)
- Viewport-based layout for performance
- Custom layout fragment API for inline rendering
- Native accessibility support
- Platform integration

### Best architecture for inline rendering?

**Hybrid approach:**

1. **Short-term:** Attribute-based syntax hiding with debounced cursor tracking
2. **Medium-term:** Custom NSTextLayoutFragment for headings and code blocks
3. **Long-term:** Full cursor-aware rendering for all inline elements

### Path to Bear-quality editing?

1. **Phase 1 (Weeks 1-2):** Cursor tracking infrastructure
   - Track cursor position changes
   - Detect when cursor enters/exits styled ranges
   - Debounce to avoid excessive updates

2. **Phase 2 (Weeks 3-4):** Attribute-based hiding
   - Hide syntax characters via `.foregroundColor = .clear`
   - Show when cursor is on line
   - Smooth transitions with animation

3. **Phase 3 (Weeks 5-8):** Custom layout fragments
   - Implement `MarkdownLayoutFragment` subclass
   - Start with headings (most visible)
   - Extend to code blocks, then inline elements

4. **Phase 4 (Ongoing):** Polish and optimization
   - Incremental parsing for large documents
   - Animation refinement
   - Edge case handling (IME, dictation, selection)

---

## References

1. [WWDC 2021 - Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/)
2. [swift-markdown Repository](https://github.com/swiftlang/swift-markdown)
3. [TextKit Documentation](https://developer.apple.com/documentation/appkit/textkit)
4. [STTextView (TextKit 2 reference)](https://github.com/krzyzanowskim/STTextView)
5. [Runestone (Tree-sitter approach)](https://github.com/simonbs/Runestone)
6. [Down (cmark wrapper)](https://github.com/johnxnguyen/Down)
7. [cmark-gfm](https://github.com/github/cmark-gfm)

---

## Appendix: Code Samples

### Cursor Position Tracking

```swift
// Add to MarkdownTextView Coordinator
private func handleCursorChange(to newPosition: NSRange) {
    let affectedRanges = findStyledRangesAffectedBy(newPosition)
    let previouslyAffectedRanges = currentlyVisibleSyntaxRanges

    // Hide syntax for ranges cursor left
    for range in previouslyAffectedRanges.subtracting(affectedRanges) {
        hideSyntaxCharacters(in: range)
    }

    // Show syntax for ranges cursor entered
    for range in affectedRanges.subtracting(previouslyAffectedRanges) {
        showSyntaxCharacters(in: range)
    }

    currentlyVisibleSyntaxRanges = affectedRanges
}
```

### Custom Layout Fragment Skeleton

```swift
class MarkdownHeadingLayoutFragment: NSTextLayoutFragment {
    let headingLevel: Int
    var showsSyntax: Bool = false

    override func draw(at point: CGPoint, in context: CGContext) {
        if showsSyntax {
            super.draw(at: point, in: context)
        } else {
            // Skip the "# " prefix in drawing
            let textToRender = attributedString.attributedSubstring(
                from: NSRange(location: headingLevel + 1, length: attributedString.length - headingLevel - 1)
            )
            // Draw with heading styling
            drawHeading(textToRender, level: headingLevel, at: point, in: context)
        }
    }

    override var layoutFragmentFrame: CGRect {
        // Return frame based on whether syntax is shown
        var frame = super.layoutFragmentFrame
        if !showsSyntax {
            // Adjust frame to not include hidden syntax characters
            frame.origin.x -= syntaxCharacterWidth
        }
        return frame
    }
}
```

---

*Document generated for Quartz markdown editor architecture planning.*
