# Exporting Notes

Quartz Notes can export your notes to four formats for sharing, printing, or archiving.

## Export formats

| Format | Best for | Method |
|--------|----------|--------|
| **PDF** | Printing, sharing read-only documents | CoreText pagination (native, no web view) |
| **HTML** | Web publishing, email | AST-based semantic HTML with stylesheet |
| **RTF** | Pasting into Word, Pages, or email | Rich attributed string conversion |
| **Markdown** | Backup, migration to other apps | Raw `.md` with frontmatter |

## How to export

1. Open the note you want to export
2. Click the **Share** button in the toolbar
3. Select the desired format from the menu
4. Choose a save location in the file dialog

## PDF export details

PDF export uses Apple's CoreText framework (`CTFramesetter`) for native text layout. This produces clean, properly paginated PDFs without the overhead or rendering artifacts of a web-based approach.

The PDF includes:
- Note title as a header
- Full markdown content rendered with formatting
- Page numbers
- Proper margins and page breaks

## HTML export details

HTML export walks the Markdown AST (Abstract Syntax Tree) using a custom visitor and generates semantic HTML tags:

- Headings become `<h1>` through `<h6>`
- Bold becomes `<strong>`, italic becomes `<em>`
- Code blocks get `<pre><code>` with language class
- Links are preserved as `<a href="...">`

A built-in stylesheet provides clean, readable styling.

## Batch export

Currently, export is per-note. For full vault export, use the backup feature (Settings > Data & Sync > Create Backup).

---

**Next:** [Appearance Settings](../settings/appearance.md)
