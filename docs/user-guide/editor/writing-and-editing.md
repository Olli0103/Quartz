# Writing & Editing

The Quartz Notes editor is built on Apple's TextKit 2 framework, providing a fast, native editing experience with real-time syntax highlighting.

## Creating a new note

- Press **Cmd+N** to create a new note
- Click the **+** button in the sidebar or note list
- Use the **Quick Capture** bar on the Dashboard to jot a quick thought

New notes are created as `.md` files in the currently selected folder.

## The editing experience

- **Native text editing** — Full support for macOS text system features: autocorrect, spell check, dictionary lookup, text replacement
- **Real-time syntax highlighting** — Headings, bold, italic, code, links, and blockquotes are styled as you type
- **No mode switching** — You write in Markdown and see styled text simultaneously. No separate "edit" and "preview" modes
- **Writing Tools** — On macOS 15.1+, Apple's built-in Writing Tools (rewrite, proofread, summarize) are available in the editor

## Autosave

Quartz Notes automatically saves your work 1 second after you stop typing. You never need to manually save, but you can press **Cmd+S** to force an immediate save.

The unsaved changes indicator (a small colored dot next to the note title) shows when changes haven't been saved yet.

## Undo & Redo

- **Undo:** Cmd+Z
- **Redo:** Cmd+Shift+Z

The undo history is per-note and clears when you switch to a different note.

## External modification detection

If another app modifies your note file while it's open in Quartz Notes, a banner appears offering to:

- **Reload** — Discard your changes and load the external version
- **Keep Editing** — Dismiss the banner and continue with your version

## Status bar

At the bottom of the editor, a status bar shows:
- Word count
- Estimated reading time

## Multi-window editing

On macOS, you can open a note in a separate window:

1. Right-click a note in the sidebar
2. Select **Open in New Window**

Or use **File > Open Vault** to work with multiple vaults simultaneously.

---

**Next:** [Markdown Syntax](markdown-syntax.md)
