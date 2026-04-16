# Release Notes

## Architecture Overview

Quartz keeps the editor native on Apple platforms and stores notes as plain markdown. This fixture intentionally mixes long paragraphs, blank lines, and repeated heading levels because the open/reopen rendering bug showed up most clearly in existing notes that had already accumulated real structure.

### Rendering Goals

The first visible render must match the stable post-edit render. Reopening the same note must preserve the same heading styling, paragraph spacing, and inline semantics without waiting for an additional local edit to heal the line.

## Writing Workflow

Existing notes often contain:

- long paragraphs with wrapped text
- repeated heading levels
- inline code like `print(value)`
- markdown links such as [Quartz](https://example.com/quartz)
- wiki links like [[Release Plan]]
- short math fragments like $x^2 + y^2$

### Long Paragraph Sample

This paragraph is deliberately long so the text system has to lay out a realistic amount of content before it reaches the next heading. The bug this fixture protects against was not about tiny synthetic notes. It showed up when a previously authored note reopened and only part of the heading line visually carried the correct font and color while the rest of the line looked like body text until the user touched it.

## Product Quality

Quartz should behave like a trustworthy writing tool. Rendering cannot depend on whether the user recently touched the line. Initial open, reopen, and post-edit presentation must agree for headings, paragraphs, code spans, links, and other already supported constructs.

### Stable Reload Expectations

On reopen, the editor should not reuse stale line-level visual state. It should rebuild the authoritative attributed representation from the current semantic spans and apply it coherently to the mounted text storage.

## Mixed Semantics

Paragraph text can include `inline code`, [links](https://example.com), and [[Internal References]] without leaking background or color styling into surrounding text.

### Repeated Sections

The remaining sections extend the document length while keeping the structure realistic.

## Section A

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section B

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section C

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section D

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section E

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section F

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section G

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.

## Section H

### Notes

This existing note section mirrors the way a real knowledge-base document grows over time. The heading line above should render with one consistent heading style across the entire visible heading text.
