# MindPalace — Plan & Feature Roadmap

A personal, always-available scratchpad that stores **text, images, and files**, lives on top of all windows, opens with a global keyboard shortcut, and gets smarter over time with an AI layer for organizing and searching. Replaces `mind.txt`.

---

## 1. Core idea

One frameless, glassy, always-on-top window. Press a hotkey anywhere in Windows → MindPalace appears → paste / type / drop something → press the hotkey again → it's gone, and the thing is saved. Zero friction capture first; organization is the AI's job, not yours.

**Design principles**

- Capture must take < 2 seconds. Never show a dialog, never ask where to save.
- Everything is one kind of thing: an **item** (text, image, or file). No folders to choose at capture time.
- Search is the only navigation. Like fzf/telescope: type a few characters, items filter instantly.
- UI is monochrome glass (Hyprland-style): blur/acrylic background, thin 1px borders, no colored buttons, subtle hover states only.

---

## 2. Recommended tech stack

| Concern | Choice | Why |
|---|---|---|
| App shell | **Tauri 2** (Rust + system WebView) | ~10 MB RAM idle vs Electron's ~150 MB — matters for an always-running app. First-class global shortcuts, tray, autostart, always-on-top. |
| UI | **React + TypeScript + Tailwind** | Matches your existing stack; easy to get the glass look with CSS. |
| Glass effect | `window-vibrancy` crate (Acrylic/Mica on Win 11) + transparent window | Real OS-level blur, not a fake CSS blur. |
| Storage | **SQLite** (bundled, via `tauri-plugin-sql` or rusqlite) + a `vault/` folder for file/image blobs | Local-first, one file to back up, FTS5 built in. |
| Keyword search | SQLite **FTS5** + a fuzzy scorer (fzf-style) in Rust | Instant as-you-type over thousands of items. Works for Japanese with trigram tokenizer. |
| Semantic search / AI | **Claude API** (`claude-haiku-5-5` for tagging/titling, `claude-sonnet-5-5` for organize/chat) + local embeddings via `sqlite-vec` | Haiku keeps per-capture cost negligible; embeddings make "that note about hospital fax validation" findable without exact words. |

Alternative if you want zero Rust: **Electron** (supports `backgroundMaterial: 'acrylic'` on Win 11). Faster to start, heavier to run forever. Tauri is the better fit for a resident app.

---

## 3. UX spec (v1)

```
┌──────────────────────────────────────────────  ─ ✕ ┐   ← minimize / close only, no title text
│  🔍 type to search…                    [All|Text|Img|File]  ← single row: search + section filter
├─────────────────────────────────────────────────────┤
│  ▸ item                                    2m ago   │
│  ▸ item (image thumbnail)                  1h ago   │   ← newest first, keyboard navigable
│  ▸ item                                    yesterday │
├─────────────────────────────────────────────────────┤
│  + type a note, Ctrl+V an image, or drop a file     │   ← capture bar, always focused on open
└─────────────────────────────────────────────────────┘
```

- **Global hotkey** (suggest `Alt+Space` or `Ctrl+Shift+Space`): toggles show/hide. Window opens centered or at last position, capture bar focused.
- **Always on top**, skip taskbar, lives in the **system tray** (close button = hide, not quit).
- **Esc** hides. **Enter** saves text. **Ctrl+V** with an image on the clipboard saves the image. **Drag & drop** any file copies it into the vault.
- Click an item: text → expands inline for copy/edit; image → preview; file → opens / reveal in Explorer.
- `Ctrl+C` on a selected item copies it back to the clipboard (the whole point of a scratchpad).

---

## 4. Data model

```sql
items(
  id, type,            -- text | image | file
  content,             -- text body, or relative path into vault/
  title,               -- AI-generated or first line
  tags,                -- AI-generated, JSON array
  summary,             -- AI-generated one-liner (what FTS/embeddings index for files/images)
  created_at, accessed_at, pinned, archived
)
items_fts(...)         -- FTS5 trigram (handles Japanese + English)
items_vec(...)         -- sqlite-vec embeddings (phase 4)
```

Vault layout: `%APPDATA%/MindPalace/{mindpalace.db, vault/2026/11/<uuid>.<ext>}` — plain files, trivially backed up or synced.

---

## 5. Build phases

### Phase 1 — Scratchpad MVP (build this first)
> Status 2026-11-11: built in `app/` (Tauri 2 + React). One deviation: storage is the shared
> `agent/data/palace.json` (same store as the agent CLI and the `mindpalace` skill), not SQLite —
> SQLite/FTS5 moves to Phase 3 when search outgrows JSON.
- Tauri app: frameless transparent window, acrylic blur, always-on-top, tray icon, autostart with Windows.
- Global hotkey toggle.
- Capture + list + persist **text** items in SQLite.
- Minimize/close buttons (close = hide to tray).
- **Done when:** you can hotkey → paste text → hotkey away, and it survives a reboot. You stop opening `mind.txt`.

### Phase 2 — Images & files
> Status 2026-11-11: built. Vault lives at `agent/data/vault/`; clipboard paste, drag & drop,
> sidebar thumbnails, preview pane with open/reveal/copy. Remaining from this phase: none.
- Clipboard image paste (PNG into vault, thumbnail in list).
- Drag & drop files (copy into vault, show name + icon + size).
- Section filter row (All / Text / Images / Files).
- Copy-back to clipboard, open, reveal-in-Explorer actions.

### Phase 3 — Lazy search
> Status 2026-11-11: built, minus SQLite (JSON store is fast enough at this scale). fzf-style
> fuzzy scoring in `app/src/fuzzy.ts`, Ctrl+K → ↑/↓ → Enter opens / Ctrl+Enter grabs-and-hides,
> pin/archive hover actions, `arc` filter for archived items.
- FTS5 + fuzzy scoring, results re-rank on every keystroke (<50 ms target).
- Keyboard-only flow: type → ↑/↓ → Enter copies, Ctrl+Enter opens.
- Pin items to top; archive instead of delete.

### Phase 4 — AI layer
- On capture (async, never blocks the UI): Haiku generates **title, tags, one-line summary**; for images, a description (what's in the screenshot) so images become text-searchable.
- **Semantic search**: embed summaries, blend vector similarity with fuzzy score.
- **Organize command**: a button/shortcut that asks Claude to cluster items into topics, propose merges of duplicates, and flag stale items — shown as suggestions you accept, never auto-applied.
- **Ask your palace**: a query mode ("what was that fax validation rule?") answered from your items with citations to them.
- `mind.txt` importer: Claude splits the file into discrete items, titles and tags each one.

### Phase 5 — Polish / later ideas
- Clipboard history mode (opt-in watcher, auto-capture everything copied).
- OCR on images (Windows.Media.Ocr is built into Windows, free, handles Japanese).
- Quick-capture without opening the window (hotkey #2 = "save clipboard silently" + toast).
- Item expiry ("keep for a week" items that auto-archive).
- Markdown + Mermaid rendering for text items (your notes already contain Mermaid).
- Export (markdown dump), encrypted vault option, multi-device sync via the vault folder in OneDrive/Syncthing.
- MCP server exposing the palace, so Claude Code sessions can read/write your scratchpad.

---

## 6. Risks / decisions to make early

- **Acrylic on Windows**: true transparency + blur in Tauri needs `transparent: true`, no window shadow quirks on some GPUs — prototype the glass window on day 1 before building anything else.
- **Japanese search**: default FTS5 tokenizer won't split Japanese; use the **trigram** tokenizer from the start so 「電話番号」 is findable.
- **AI cost/privacy**: everything is local except the AI calls. Keep AI optional per-item (a setting: auto-enrich on/off), and never send file contents — only names — unless you opt in.
- **One window, not a note app**: resist adding folders, notebooks, or rich editing. The moment it needs management, it has failed its purpose.
