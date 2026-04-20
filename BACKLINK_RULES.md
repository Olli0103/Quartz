# Backlink Rules

These rules are based on the actual QuartzKit implementation in:

- `QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift`
- `QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift`
- `QuartzKit/Sources/QuartzKit/Data/Markdown/WikiLinkExtractor.swift`

## 1. How backlinks are computed

- Quartz scans every note body in the vault.
- It extracts body wiki links with `WikiLinkExtractor`.
- For a target note, Quartz lowercases the target note filename stem and compares it to each extracted wiki link target lowercased.
- A backlink exists only when `wikiLink.target.lowercased() == targetNoteStem.lowercased()`.

## 2. Supported link syntax

Quartz indexes these wiki-link forms:

- `[[Note]]`
- `[[Note|Alias]]`
- `[[Note#Heading]]`
- `[[Note#Heading|Alias]]`

Links inside fenced code blocks and inline code are ignored.

## 3. Must internal links be wiki links?

For backlink indexing, yes.

- `BacklinkUseCase` uses `WikiLinkExtractor`, not standard Markdown-link parsing.
- `LinkSuggestionService` also only checks existing `[[...]]` links when suppressing duplicate suggestions.

Do not rely on standard Markdown links like `[Alexandra](Alexandra.md)` for internal backlink relationships.

## 4. How matching works

- Matching is case-insensitive.
- Matching is based on the extracted wiki-link target after removing any alias (`|...`) and heading anchor (`#...`).
- Matching compares against the target note filename stem, not the full relative path.

Examples:

- `[[Alexandra]]` matches `Alexandra.md`
- `[[Alexandra#Current priorities]]` also matches `Alexandra.md`
- `[[Alexandra|Alex]]` also matches `Alexandra.md`

## 5. What filename collisions break or confuse backlinking

Hard problem:

- If two notes in the vault share the same case-insensitive basename stem, backlink scanning cannot safely distinguish them because matching uses the lowercased filename stem.

Examples:

- `Alexandra.md` and another `alexandra.md`
- `03-02-2026-03-02-2026.md` in multiple folders

Operational rule:

- Duplicate case-insensitive basenames must be treated as blockers or routed to manual review.
- Do not guess which note a wiki link target should resolve to.
