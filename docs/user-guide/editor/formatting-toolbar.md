# Formatting Toolbar

The formatting toolbar provides quick access to all Markdown formatting without memorizing syntax.

## macOS Toolbar

On macOS, the formatting toolbar is embedded in the window's title bar area. It contains:

| Button | Action | Shortcut |
|--------|--------|----------|
| **B** | Bold | Cmd+B |
| *I* | Italic | Cmd+I |
| ~~S~~ | Strikethrough | Cmd+Shift+X |
| `<>` | Inline Code | Cmd+E |
| H | Heading Dropdown (H1-H6) | Cmd+1 through Cmd+6 |
| List | Bullet List | — |
| 1. | Numbered List | — |
| [ ] | Checkbox | — |
| Link | Insert Link | Cmd+Shift+L |
| Quote | Blockquote | Cmd+Shift+Q |
| Code | Code Block | Cmd+Shift+E |
| Table | Insert Table | — |
| AI | AI Writing Assistant | — |

## Heading Dropdown

Click the heading button to reveal a dropdown menu with heading levels 1 through 6. The current heading level at the cursor position is indicated.

## How formatting works

Quartz Notes wraps your selected text with the appropriate Markdown syntax:

- **With selected text:** `**selected text**` for bold
- **Without selection:** Inserts the syntax pair and places the cursor between them: `****` with cursor in the middle

The toolbar buttons reflect the current formatting state at the cursor position. For example, if your cursor is inside bold text, the Bold button appears active.

---

**Next:** [Focus Mode](focus-mode.md)
