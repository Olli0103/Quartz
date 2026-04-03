import Testing
import Foundation
@testable import QuartzKit

// MARK: - Single Toggle Tests

@Suite("MarkdownTaskToggle — Single Toggle")
struct TaskToggleSingleTests {

    private let toggle = MarkdownTaskToggle()

    @Test("Toggle unchecked to checked")
    func toggleUncheckedToChecked() {
        let text = "- [ ] Buy groceries"
        let result = toggle.toggle(in: text, at: 10)
        #expect(result != nil)
        #expect(result!.isChecked == true)
        #expect(result!.replacementText == "[x]")
        #expect(result!.replacementRange.length == 3)
    }

    @Test("Toggle checked to unchecked")
    func toggleCheckedToUnchecked() {
        let text = "- [x] Buy groceries"
        let result = toggle.toggle(in: text, at: 10)
        #expect(result != nil)
        #expect(result!.isChecked == false)
        #expect(result!.replacementText == "[ ]")
    }

    @Test("Toggle uppercase X")
    func toggleUppercaseX() {
        let text = "- [X] Done task"
        let result = toggle.toggle(in: text, at: 5)
        #expect(result != nil)
        #expect(result!.isChecked == false)
        #expect(result!.replacementText == "[ ]")
    }

    @Test("Non-task line returns nil")
    func nonTaskLine() {
        let text = "Just a regular line"
        let result = toggle.toggle(in: text, at: 5)
        #expect(result == nil)
    }

    @Test("List item without checkbox returns nil")
    func listWithoutCheckbox() {
        let text = "- Buy groceries"
        let result = toggle.toggle(in: text, at: 5)
        #expect(result == nil)
    }

    @Test("Asterisk list marker")
    func asteriskMarker() {
        let text = "* [ ] Task with asterisk"
        let result = toggle.toggle(in: text, at: 5)
        #expect(result != nil)
        #expect(result!.isChecked == true)
    }

    @Test("Plus list marker")
    func plusMarker() {
        let text = "+ [ ] Task with plus"
        let result = toggle.toggle(in: text, at: 5)
        #expect(result != nil)
        #expect(result!.isChecked == true)
    }

    @Test("Ordered list marker")
    func orderedMarker() {
        let text = "1. [ ] First task"
        let result = toggle.toggle(in: text, at: 5)
        #expect(result != nil)
        #expect(result!.isChecked == true)
    }

    @Test("Indented task")
    func indentedTask() {
        let text = "    - [ ] Nested task"
        let result = toggle.toggle(in: text, at: 10)
        #expect(result != nil)
        #expect(result!.isChecked == true)
    }

    @Test("Cursor at start of line still works")
    func cursorAtLineStart() {
        let text = "- [ ] Task"
        let result = toggle.toggle(in: text, at: 0)
        #expect(result != nil)
    }

    @Test("Cursor at end of line still works")
    func cursorAtLineEnd() {
        let text = "- [ ] Task"
        let result = toggle.toggle(in: text, at: 10)
        #expect(result != nil)
    }

    @Test("Toggle in multi-line document targets correct line")
    func multiLineDocument() {
        let text = "# Title\n- [ ] First\n- [x] Second\n- [ ] Third"
        // Cursor in "Second" line
        let nsText = text as NSString
        let secondLoc = nsText.range(of: "Second").location
        let result = toggle.toggle(in: text, at: secondLoc)
        #expect(result != nil)
        #expect(result!.isChecked == false) // was checked, now unchecked
    }

    @Test("Replacement range is correct for applying edit")
    func replacementRangeCorrect() {
        let text = "- [ ] Task"
        let result = toggle.toggle(in: text, at: 0)!
        // Replace "[ ]" with "[x]"
        let nsText = text as NSString
        let replaced = nsText.replacingCharacters(in: result.replacementRange, with: result.replacementText)
        #expect(replaced == "- [x] Task")
    }
}

// MARK: - Cascade Toggle Tests

@Suite("MarkdownTaskToggle — Cascade Toggle")
struct TaskToggleCascadeTests {

    private let toggle = MarkdownTaskToggle()

    @Test("Cascade toggles parent and children")
    func cascadeToggle() {
        let text = """
        - [ ] Parent
          - [ ] Child 1
          - [ ] Child 2
        """
        let result = toggle.toggleWithChildren(in: text, at: 3)
        #expect(result != nil)
        #expect(result!.count == 3) // parent + 2 children
        #expect(result!.allSatisfy { $0.isChecked == true })
    }

    @Test("Cascade stops at same indentation level")
    func cascadeStopsAtSameIndent() {
        let text = """
        - [ ] Parent
          - [ ] Child
        - [ ] Sibling
        """
        let result = toggle.toggleWithChildren(in: text, at: 3)
        #expect(result != nil)
        #expect(result!.count == 2) // parent + child only, not sibling
    }

    @Test("Cascade unchecks all when parent is checked")
    func cascadeUncheck() {
        let text = """
        - [x] Parent
          - [x] Child 1
          - [x] Child 2
        """
        let result = toggle.toggleWithChildren(in: text, at: 3)
        #expect(result != nil)
        #expect(result!.allSatisfy { $0.isChecked == false })
    }

    @Test("Cascade skips non-checkbox children")
    func cascadeSkipsNonCheckbox() {
        let text = """
        - [ ] Parent
          - [ ] Child with checkbox
          - Regular list item
          - [ ] Another checkbox child
        """
        let result = toggle.toggleWithChildren(in: text, at: 3)
        #expect(result != nil)
        #expect(result!.count == 3) // parent + 2 checkbox children
    }

    @Test("No cascade on non-task line")
    func noCascadeOnNonTask() {
        let text = "Just regular text"
        let result = toggle.toggleWithChildren(in: text, at: 5)
        #expect(result == nil)
    }

    @Test("Single task with no children")
    func singleTaskNoCascade() {
        let text = "- [ ] Solo task"
        let result = toggle.toggleWithChildren(in: text, at: 5)
        #expect(result != nil)
        #expect(result!.count == 1)
    }

    @Test("Cascade skips blank lines between children")
    func cascadeSkipsBlankLines() {
        let text = "- [ ] Parent\n  - [ ] Child 1\n\n  - [ ] Child 2\n"
        let result = toggle.toggleWithChildren(in: text, at: 3)
        #expect(result != nil)
        #expect(result!.count == 3) // parent + 2 children despite blank line
    }
}

// MARK: - Checkbox Detection Tests

@Suite("MarkdownTaskToggle — Checkbox Detection")
struct TaskToggleCheckboxDetectionTests {

    private let toggle = MarkdownTaskToggle()

    @Test("Detects unchecked dash checkbox")
    func uncheckedDash() {
        let info = toggle.findCheckbox(in: "- [ ] Task")
        #expect(info != nil)
        #expect(info!.isChecked == false)
    }

    @Test("Detects checked dash checkbox")
    func checkedDash() {
        let info = toggle.findCheckbox(in: "- [x] Task")
        #expect(info != nil)
        #expect(info!.isChecked == true)
    }

    @Test("No checkbox in regular line")
    func noCheckbox() {
        let info = toggle.findCheckbox(in: "Regular text")
        #expect(info == nil)
    }

    @Test("No checkbox in list without brackets")
    func listNoBrackets() {
        let info = toggle.findCheckbox(in: "- Just a list")
        #expect(info == nil)
    }

    @Test("Bracket offset points to [")
    func bracketOffsetCorrect() {
        let line = "- [ ] Task"
        let info = toggle.findCheckbox(in: line)!
        let char = line[line.index(line.startIndex, offsetBy: info.bracketOffset)]
        #expect(char == "[")
    }

    @Test("Indented bracket offset correct")
    func indentedBracketOffset() {
        let line = "    - [ ] Task"
        let info = toggle.findCheckbox(in: line)!
        let char = line[line.index(line.startIndex, offsetBy: info.bracketOffset)]
        #expect(char == "[")
    }

    @Test("Checkbox at end of line (no trailing content)")
    func checkboxAtEnd() {
        let info = toggle.findCheckbox(in: "- [ ]")
        #expect(info != nil)
        #expect(info!.isChecked == false)
    }

    @Test("Checkbox with newline")
    func checkboxWithNewline() {
        let info = toggle.findCheckbox(in: "- [ ]\n")
        #expect(info != nil)
    }
}
