# Markdown Syntax

Quartz Notes uses standard Markdown with some common extensions. Everything you write is plain text — no proprietary formatting.

## Headings

```markdown
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
```

The `#` prefix characters are muted in the editor so your headings look clean while remaining editable.

**Shortcuts:** Cmd+1 through Cmd+6 for heading levels.

## Text formatting

| Syntax | Result | Shortcut |
|--------|--------|----------|
| `**bold**` | **bold** | Cmd+B |
| `*italic*` | *italic* | Cmd+I |
| `~~strikethrough~~` | ~~strikethrough~~ | Cmd+Shift+X |
| `` `inline code` `` | `inline code` | Cmd+E |

The delimiter characters (`**`, `*`, `~~`, `` ` ``) are automatically muted in the editor for cleaner reading.

## Links

```markdown
[Link text](https://example.com)
```

Links appear in blue in the editor. **Shortcut:** Cmd+Shift+L

## Lists

### Bullet lists
```markdown
- Item one
- Item two
  - Nested item
```

### Numbered lists
```markdown
1. First item
2. Second item
3. Third item
```

### Task lists (checkboxes)
```markdown
- [ ] Unchecked task
- [x] Completed task
```

**List continuation:** When you press Enter at the end of a list item, Quartz Notes automatically continues the list with the appropriate prefix. Press Enter on an empty list item to exit the list.

## Blockquotes

```markdown
> This is a blockquote.
> It can span multiple lines.
```

Blockquotes appear in italic with a secondary color. **Shortcut:** Cmd+Shift+Q

## Code blocks

````markdown
```
Code block without language
```

```python
def hello():
    print("Hello, world!")
```
````

Code blocks use a monospaced font (SF Mono) with a subtle background tint.

**Shortcut:** Cmd+Shift+E for a code block.

## Tables

```markdown
| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |
```

Table pipe `|` and dash `-` characters are automatically muted for readability. **Shortcut:** Available in the formatting toolbar.

## Frontmatter

You can add YAML frontmatter at the top of any note:

```markdown
---
title: My Note Title
tags: [project, idea, draft]
created: 2026-03-27
---

Your note content starts here.
```

Quartz Notes reads `title` and `tags` from frontmatter for display in the sidebar, note list, and search.

---

**Next:** [Formatting Toolbar](formatting-toolbar.md)
