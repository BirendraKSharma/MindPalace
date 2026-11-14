# MindPalace — Keyboard Shortcuts

No toolbars. Everything is a key.

## Global (anywhere on the system)

| Key | Action |
|---|---|
| `Ctrl+Shift+Space` | Show / hide MindPalace (fallback: `Alt+Space`) |
| your togglefloating key | Hyprland only: MindPalace tiles/floats like any other window (the installer binds nothing extra) |

Both are what the installers set up by default — pick different keys during
install, or change them later in `config.json` next to `palace.json`
(`hotkey`, `fallbackHotkey`; on Hyprland edit `~/.config/hypr/mindpalace.{lua,conf}`).

## App

| Key | Action |
|---|---|
| `Esc` | Hide to tray (saves first) |
| `Ctrl+N` | New note |
| `Ctrl+S` | Save now (autosave runs anyway, 0.7s after you stop typing) |
| `Ctrl+V` with an image on the clipboard | Save the image into the vault (works anywhere in the window) |
| Drag & drop any file onto the window | Copy it into the vault as a file item |
| `Ctrl+K` | Jump to search |

## Search (while the search box is focused)

Fuzzy matching: characters just need to appear in order — `hspmaster` finds "hospital-master",
`bcklg excl` finds the Backlog Excel note. Multiple words must all match (any field).

| Key | Action |
|---|---|
| `↑` / `↓` | Move through results |
| `Enter` | Open the selected item in the pad |
| `Ctrl+Enter` | **Grab**: copy the item (text → text, image → image, file → its path) and hide the window |
| `Esc` | Clear the search (press again to hide the window) |

Hovering a list item shows `pin` / `arc` (archive) — archived items live under the `arc` filter, nothing is ever deleted.

## Editor — writing

| Key | Action |
|---|---|
| `(` `[` `{` `'` `"` `` ` `` | Auto-close the pair (VS Code style): wraps a selection, typing the closing char skips over it, `Backspace` deletes an empty pair |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo |
| `Ctrl+F` | Find in note (then `Enter` / `Shift+Enter` next/previous, `Esc` closes) |
| `Tab` / `Shift+Tab` | Indent / outdent line or selection |
| `Enter` in a list | Continue the markdown list |

## Editor — VS Code-style editing

| Key | Action |
|---|---|
| `Alt+Click` | Add another cursor (multi-cursor) |
| `Alt+Drag` | Column (rectangular) selection |
| `Ctrl+D` | Select next occurrence of current selection (repeat to add more cursors) |
| `Ctrl+A` | Select all |
| `Ctrl+Shift+K` | Delete line |
| `Alt+↑` / `Alt+↓` | Move line up / down |
| `Shift+Alt+↑` / `Shift+Alt+↓` | Copy line up / down |
| `Alt+L` | Select line (repeat to extend) |
| `Ctrl+[` / `Ctrl+]` | Outdent / indent line |
| `Ctrl+Enter` | Insert blank line below |
| `Ctrl+←` / `Ctrl+→` | Move by word |
| `Ctrl+Backspace` / `Ctrl+Delete` | Delete word left / right |
| `Home` / `End` | Smart line start / end |
| `Esc` (with multiple cursors) | Back to a single cursor |

## Inline commands (type on a line, press Enter)

| You type | What happens |
|---|---|
| `23 * 56 --calc` | The line becomes `23 * 56 = 1288`. Supports `+ - * / % ^ ( )`, decimals, `1,234` separators, `×`/`x`/`÷`. `%` is modulo. If the text isn't pure arithmetic, Enter just inserts a newline. |
| `tauri window rules --search` | Opens your browser with a web search for the text; the `--search` suffix is removed from the line. Engine: Google, or set `searchUrl` in `config.json` (e.g. `"https://duckduckgo.com/?q="`). |
| `こんにちは --translate` | **AI, only while connected**: translates the line (auto Japanese↔English), result appears on the next line. |
| `some rough text --rephrase` | **AI, only while connected**: rephrases the line to be clearer, same language. |
| `anything --yourskill` | Any `## yourskill` section you add to `SKILLS.md` (next to palace.json) becomes a command — no code needed. |

Calc and search work offline, cursor can be anywhere on the line.

**AI is off by default** — connect it with the star button in the titlebar (it
probes for the `claude`, `codex`, `opencode` or `ollama` CLI; ollama is the
fully-offline option, set `"aiModel"` in config.json). While disconnected,
`--skill` lines are plain text and nothing is ever sent anywhere. While
connected, only the single line you run a command on is sent.

## Markdown (typed, styled live — no toolbar)

| Syntax | Result |
|---|---|
| `# text` → `### text` | Headings (sized in the editor) |
| `**bold**`, `*italic*`, `~~strike~~` | Inline emphasis |
| `` `code` `` | Inline code |
| `- item`, `1. item` | Lists |
| `> quote` | Quote |
| `[label](url)` | Link |
