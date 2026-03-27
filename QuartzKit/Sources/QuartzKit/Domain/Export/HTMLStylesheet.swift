import Foundation

/// Embedded CSS for HTML export — clean, modern, print-friendly.
///
/// Uses system font stack (-apple-system, SF Pro Text), 720px max-width,
/// dark mode via `prefers-color-scheme`, and a print stylesheet that
/// expands link URLs inline.
enum HTMLStylesheet {
    static let css = """
    :root {
      --text: #1d1d1f;
      --text-secondary: #6e6e73;
      --bg: #ffffff;
      --code-bg: #f5f5f7;
      --border: #d2d2d7;
      --link: #0066cc;
      --blockquote-border: #d2d2d7;
      --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      --font-mono: "SF Mono", ui-monospace, Menlo, monospace;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: var(--font-sans);
      font-size: 16px;
      line-height: 1.65;
      color: var(--text);
      background: var(--bg);
      max-width: 720px;
      margin: 0 auto;
      padding: 2.5rem 1.5rem;
      -webkit-font-smoothing: antialiased;
    }
    h1, h2, h3, h4, h5, h6 {
      font-weight: 700;
      margin-top: 1.8em;
      margin-bottom: 0.4em;
      line-height: 1.25;
    }
    h1 { font-size: 2em; margin-top: 0; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1.1em; }
    h5 { font-size: 1em; }
    h6 { font-size: 0.9em; color: var(--text-secondary); }
    p { margin-bottom: 1em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 600; }
    em { font-style: italic; }
    del { text-decoration: line-through; color: var(--text-secondary); }
    code {
      font-family: var(--font-mono);
      font-size: 0.88em;
      background: var(--code-bg);
      padding: 0.15em 0.35em;
      border-radius: 4px;
    }
    pre {
      background: var(--code-bg);
      padding: 1em 1.2em;
      border-radius: 8px;
      overflow-x: auto;
      margin-bottom: 1em;
      line-height: 1.5;
    }
    pre code {
      background: none;
      padding: 0;
      font-size: 0.85em;
    }
    blockquote {
      border-left: 3px solid var(--blockquote-border);
      margin: 0 0 1em 0;
      padding: 0.4em 0 0.4em 1em;
      color: var(--text-secondary);
    }
    ul, ol { margin-bottom: 1em; padding-left: 1.5em; }
    li { margin-bottom: 0.3em; }
    li > ul, li > ol { margin-bottom: 0; margin-top: 0.3em; }
    hr {
      border: none;
      border-top: 1px solid var(--border);
      margin: 2em 0;
    }
    img {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
      margin: 1em 0;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 1em;
    }
    th, td {
      border: 1px solid var(--border);
      padding: 0.5em 0.75em;
      text-align: left;
    }
    th { font-weight: 600; background: var(--code-bg); }
    input[type="checkbox"] {
      margin-right: 0.4em;
      vertical-align: middle;
    }
    .quartz-title {
      font-size: 2.2em;
      font-weight: 800;
      margin-bottom: 0.6em;
      letter-spacing: -0.02em;
    }
    .quartz-meta {
      font-size: 0.85em;
      color: var(--text-secondary);
      margin-bottom: 2em;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --text: #f5f5f7;
        --text-secondary: #a1a1a6;
        --bg: #1d1d1f;
        --code-bg: #2c2c2e;
        --border: #48484a;
        --blockquote-border: #48484a;
        --link: #4da3ff;
      }
    }
    @media print {
      body { max-width: none; padding: 0; color: #000; background: #fff; }
      a { color: #000; text-decoration: underline; }
      a[href]::after { content: " (" attr(href) ")"; font-size: 0.8em; color: #666; }
      pre { border: 1px solid #ddd; }
      blockquote { border-left-color: #999; }
    }
    """
}
