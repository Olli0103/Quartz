# TextKit 2 Editor Diagnosis Report

**Date:** 2026-03-24
**Analyzed Files:**
- `/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextView.swift`
- `/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextContentManager.swift`
- `/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift`
- `/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownListContinuation.swift`

---

## Executive Summary

The editor has a fundamentally correct TextKit 2 architecture but contains several implementation issues that can cause:
1. Cursor jumping and selection instability
2. Visible flicker during syntax highlighting
3. Typing attributes being overwritten
4. IME/composition mode interference
5. Performance issues with large documents
6. SwiftUI binding feedback loops

---

## Issue 1: CRITICAL - Full Text Replacement on Programmatic Updates

**Location:** `MarkdownTextView.swift` lines 191-198 (iOS), 481-490 (macOS)

**Problem:**
```swift
if textChanged {
    let savedSelection = uiView.selectedRange
    uiView.text = text  // <-- FULL REPLACEMENT
    // ...
}
```

When the SwiftUI binding changes, the entire text is replaced via `textView.text = text` (iOS) or `textView.string = text` (macOS). This destroys:
- Active IME composition sessions
- Undo/redo history
- Marked text ranges
- Text input context state

**Apple Documentation Reference:**
Per Apple's TextKit 2 documentation, text modifications should be performed through the text storage using `replaceCharacters(in:with:)` for the minimal affected range, not wholesale assignment.

**WWDC References:**
- WWDC 2021 "Meet TextKit 2" (10061): "TextKit 2 is designed around surgical updates"
- WWDC 2022 "What's new in TextKit and text views" (10090): Emphasizes incremental layout invalidation

**Recommended Fix:**
Implement text diffing before updating the text view. Only apply changes via `textStorage.replaceCharacters(in:with:)` for the actual changed ranges.

---

## Issue 2: HIGH - List Continuation Replaces Entire Document

**Location:** `MarkdownTextView.swift` lines 374-402 (iOS), 629-660 (macOS)

**Problem:**
```swift
let changeRange = NSRange(location: changeStart, length: nsCurrentText.length)  // changeStart = 0
storage.beginEditing()
storage.replaceCharacters(in: changeRange, with: result.newText)  // FULL DOC REPLACEMENT
```

When handling newlines for list continuation, the code replaces the **entire document** rather than just inserting the continuation text at the cursor position.

**Impact:**
- Destroys undo coalescing
- Forces complete layout recalculation
- Causes visible flicker
- Resets text input state

**Recommended Fix:**
Calculate the minimal change (just the newline + list marker insertion) and apply only that delta:
```swift
// Instead of replacing the whole document:
let insertRange = NSRange(location: cursorPos, length: 0)
let insertText = "\n" + continuationMarker
storage.replaceCharacters(in: insertRange, with: insertText)
```

---

## Issue 3: HIGH - Syntax Highlighting Resets All Attributes

**Location:** `MarkdownTextView.swift` lines 319-343 (iOS), 578-602 (macOS)

**Problem:**
```swift
contentManager.performMarkdownEdit {
    // First pass: reset font to default across entire document
    storage.addAttribute(.font, value: defaultFont, range: fullRange)
    storage.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
    storage.removeAttribute(.backgroundColor, range: fullRange)
    storage.removeAttribute(.strikethroughStyle, range: fullRange)

    // Second pass: apply span-specific attributes
    for span in spans { ... }
}
```

Every highlight pass resets attributes across the **entire document** before applying new spans. This causes:
- Visible flicker as fonts change twice (reset, then apply)
- Layout thrashing
- Poor performance on large documents

**Apple Documentation Reference:**
Apple's TextKit 2 documentation recommends using `NSTextLayoutManager.invalidateLayout(for:)` for targeted regions and applying attributes only to changed ranges.

**Recommended Fix:**
1. Track which spans changed since the last highlight
2. Only apply attributes to changed ranges
3. Use paragraph-level invalidation via `MarkdownTextContentManager.boundingRangeForParagraph(containing:)`

---

## Issue 4: HIGH - Typing Attributes Restoration Timing

**Location:** `MarkdownTextView.swift` lines 351-353 (iOS), 605-612 (macOS)

**Problem:**
```swift
// Restore selection and typing attributes
textView.selectedRange = savedSelection
textView.typingAttributes = savedTypingAttrs  // After selection change
```

Typing attributes are restored **after** setting the selection. However, on iOS `UITextView`, changing `selectedRange` can reset `typingAttributes`. The order should be:
1. Save typing attributes
2. Apply attribute changes
3. Restore selection
4. **Wait for selection to settle**
5. Restore typing attributes

Additionally, if the user is actively typing during a highlight pass, the typing attributes may be overwritten before the restoration happens.

**Recommended Fix:**
Use `DispatchQueue.main.async` or `Task { @MainActor in }` to restore typing attributes after the current run loop iteration, ensuring selection has fully settled.

---

## Issue 5: MEDIUM - NSTextContentStorage Subclass Incomplete

**Location:** `MarkdownTextContentManager.swift`

**Problem:**
The `MarkdownTextContentManager` subclasses `NSTextContentStorage` but doesn't implement key protocol methods that would enable true TextKit 2 benefits:

1. **Missing `NSTextContentStorageDelegate` implementation** - The comment mentions it but no delegate is set
2. **Missing `textLayoutManager(_:textLayoutFragmentFor:in:)` override** - Would enable custom layout fragments per markdown element
3. **Missing incremental content tracking** - `lastEditedRange` is set but never used for incremental highlighting

**Apple Documentation Reference:**
Per WWDC 2021 "Meet TextKit 2":
- Custom `NSTextLayoutFragment` subclasses enable element-specific rendering
- `NSTextContentStorageDelegate` enables content transformation during layout

**Recommended Fix:**
Either:
1. Fully implement the TextKit 2 delegate pattern for custom element rendering, or
2. Simplify to use standard `NSTextContentStorage` without subclassing (current subclass adds minimal value)

---

## Issue 6: MEDIUM - Version Counter Race Condition

**Location:** `MarkdownTextView.swift` lines 241-264 (iOS), 534-556 (macOS)

**Problem:**
```swift
private var textVersion: UInt64 = 0

func incrementTextVersion() {
    textVersion &+= 1
}

func scheduleHighlight(text: String, textView: UITextView) {
    let versionAtSchedule = textVersion
    highlightTask = Task {
        let spans = await highlighter.parseDebounced(text)
        await MainActor.run {
            guard self.textVersion == versionAtSchedule else { return }  // Race!
            // ...
        }
    }
}
```

The version check happens after `await`, but `textVersion` could have been incremented **after** scheduling but **before** the MainActor block runs. This is a subtle race:
1. User types character A (version = 1)
2. Highlight task scheduled with versionAtSchedule = 1
3. User types character B (version = 2)
4. Task completes, enters MainActor block
5. Version check passes (1 == 1)? No, it fails correctly because we incremented.

Actually, the version check is correct for rejecting stale results. However, the **text comparison** on line 293/552 is redundant and can cause issues:
```swift
guard tv.text == text else { return }  // 'text' is captured, may differ from current
```

This double-check may reject valid highlight results if the user typed during debounce but the version incremented correctly.

**Recommended Fix:**
Remove the redundant text equality check; the version counter is sufficient.

---

## Issue 7: MEDIUM - SwiftUI Binding Feedback Loop

**Location:** `MarkdownTextView.swift` lines 189-227 (iOS), 479-511 (macOS)

**Problem:**
The `updateUIView`/`updateNSView` method both reads from and writes to the text view based on the binding:
```swift
func updateUIView(_ uiView: UITextView, context: Context) {
    let textChanged = uiView.text != text
    if textChanged {
        uiView.text = text  // Write
        // scheduleHighlight...
    }
}

// Meanwhile in textViewDidChange:
func textViewDidChange(_ textView: UITextView) {
    text = textView.text  // Write to binding -> triggers updateUIView
}
```

This creates a potential feedback loop:
1. User types -> `textViewDidChange` -> binding updates
2. Binding update triggers SwiftUI view update -> `updateUIView` called
3. `textChanged` check prevents infinite loop, BUT:
4. During the check, if text differs (e.g., autocorrect modified it), full replacement happens

**Recommended Fix:**
Add a flag to skip the next `updateUIView` after `textViewDidChange`:
```swift
private var isInternalTextChange = false

func textViewDidChange(_ textView: UITextView) {
    isInternalTextChange = true
    text = textView.text
}

func updateUIView(_ uiView: UITextView, context: Context) {
    guard !context.coordinator.isInternalTextChange else {
        context.coordinator.isInternalTextChange = false
        return
    }
    // ...
}
```

---

## Issue 8: MEDIUM - IME/Composition Mode Not Protected

**Location:** `MarkdownTextView.swift` throughout

**Problem:**
The code does not check for active IME composition before applying changes:
- `textView.markedTextRange` (iOS) indicates active composition
- `textView.hasMarkedText()` (macOS) indicates active composition

Applying attributes or replacing text during composition will:
- Break character composition (Japanese, Chinese, Korean input)
- Cause unexpected candidate window dismissal
- Produce incorrect text output

**Apple Documentation Reference:**
`UITextInput` protocol documentation states that `markedTextRange` should be checked before programmatic text modifications.

**Recommended Fix:**
```swift
// iOS
if textView.markedTextRange != nil { return }  // Composition in progress

// macOS
if textView.hasMarkedText() { return }  // Composition in progress
```

Add this check before:
1. Applying syntax highlighting
2. Programmatic text replacement
3. Selection restoration

---

## Issue 9: LOW - Missing Undo Registration

**Location:** `MarkdownTextView.swift` list continuation handling

**Problem:**
When list continuation modifies text via `storage.beginEditing()` / `endEditing()`, undo registration may not be properly coalesced:
```swift
storage.beginEditing()
storage.replaceCharacters(in: changeRange, with: result.newText)
// No explicit undo grouping
storage.endEditing()
```

**Recommended Fix:**
Use `textView.undoManager?.beginUndoGrouping()` and `endUndoGrouping()` or ensure modifications use the text view's proper editing methods that automatically register undo.

---

## Issue 10: LOW - Dynamic Type Not Fully Reactive

**Location:** `MarkdownTextView.swift` lines 250-277 (iOS only)

**Problem:**
The `contentSizeCategoryDidChange` notification handler exists on iOS but is missing on macOS. Additionally, when content size changes:
1. Font is recomputed
2. Full re-highlight is triggered (full document reset)

This can cause visible layout jumps when the user changes text size in Settings.

**Recommended Fix:**
1. Add macOS equivalent listener for font size preference changes
2. Use proportional/differential font updates instead of full reset

---

## Performance Concerns

### Large Document Handling

The highlighter already has sensible limits:
- `maxDocumentSize = 500_000` characters - highlighting skipped
- `largeDocumentThreshold = 50_000` characters - longer debounce

However, the full-document attribute reset during highlighting negates these benefits for documents just under the threshold.

### Debounce Interval

```swift
private let debounceInterval: UInt64 = 80_000_000 // 80ms
```

80ms is reasonable for responsive feel but may need tuning:
- Too short: Excessive CPU usage during fast typing
- Too long: Visible delay before highlighting appears

---

## Summary of Recommended Fixes (Priority Order)

| Priority | Issue | File:Line | Fix Summary |
|----------|-------|-----------|-------------|
| P0 | Full text replacement | MarkdownTextView:191,481 | Implement text diffing |
| P0 | List continuation full replacement | MarkdownTextView:374,629 | Surgical insertion only |
| P1 | Full document attribute reset | MarkdownTextView:319,578 | Incremental attribute updates |
| P1 | IME composition protection | Throughout | Check markedTextRange |
| P1 | Typing attributes timing | MarkdownTextView:351,605 | Async restoration |
| P2 | SwiftUI binding loop | MarkdownTextView:189,479 | Internal change flag |
| P2 | Incomplete NSTextContentStorage | MarkdownTextContentManager | Implement delegate or simplify |
| P3 | Redundant text check | MarkdownTextView:293,552 | Remove, trust version counter |
| P3 | Missing undo grouping | MarkdownTextView:381,640 | Add explicit undo groups |
| P3 | macOS Dynamic Type | MarkdownTextView macOS section | Add font preference observer |

---

## Apple Documentation References

1. **NSTextContentStorage Class Reference**
   https://developer.apple.com/documentation/uikit/nstextcontentstorage

2. **NSTextLayoutManager Class Reference**
   https://developer.apple.com/documentation/uikit/nstextlayoutmanager

3. **UITextInput Protocol**
   https://developer.apple.com/documentation/uikit/uitextinput

4. **WWDC 2021 - Meet TextKit 2** (Session 10061)
   https://developer.apple.com/videos/play/wwdc2021/10061/

5. **WWDC 2022 - What's new in TextKit and text views** (Session 10090)
   https://developer.apple.com/videos/play/wwdc2022/10090/

6. **WWDC 2023 - Build better document-based apps** (Session 10223)
   https://developer.apple.com/videos/play/wwdc2023/10223/

---

## Next Steps

1. **Immediate**: Add IME composition checks to prevent text corruption
2. **Short-term**: Implement text diffing for programmatic updates
3. **Medium-term**: Convert to incremental highlighting
4. **Long-term**: Consider full NSTextContentStorageDelegate implementation for custom element rendering
