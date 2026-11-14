---
name: mindpalace
description: Manage, organize, and search the user's MindPalace scratchpad (the items in agent/data/palace.json and legacy notes in mind.txt). Use this whenever the user says things like "organize my mindpalace", "tidy my palace", "clean up my notes", "what did I save about X", "find my note on X", "add this to my mindpalace", or "import mind.txt" — even if they don't say the word "skill". Claude Code does the AI work directly (no API key is available), editing the JSON store itself.
---

# MindPalace Management

MindPalace is the user's personal scratchpad (see `PLAN.md` at the repo root). Items live in
`agent/data/palace.json` — a JSON array matching the `Item` type in `agent/src/store.ts`:

```json
{
  "id": "8-char id", "type": "text|image|file",
  "content": "text body, or vault path for image/file items",
  "title": "", "tags": [], "summary": "",
  "createdAt": "ISO date", "pinned": false, "archived": false
}
```

The user has no Anthropic API key, so the `agent/` TypeScript module's AI functions cannot run.
**You are the AI layer**: read and edit `palace.json` directly with file tools. Offline CLI
commands still work if convenient: `cd agent; npm run palace -- add "text"` / `-- list`.

The Tauri app in `app/` reads and writes the same `palace.json` (dev builds resolve it
relative to the repo; `MINDPALACE_DATA` overrides). It reloads the file when its window
regains focus, so your edits appear next time the user opens it.

## Ground rules (every mode)

- **Never delete an item or modify its `content`.** Content is the user's capture; only
  metadata (`title`, `tags`, `summary`, `pinned`, `archived`) is yours to improve. Set
  `archived: true` only when the user explicitly asks.
- Before any bulk write, copy `palace.json` to `palace.backup.json` in the same folder.
- Items mix Japanese and English (hospital-system work notes, dev snippets). Keep each
  item's own language for its title; tags are lowercase English for consistent search.
- After editing, verify the file is still valid JSON parseable as an array.

## Modes

Pick the mode from what the user asked:

### organize (default when they just say "organize/tidy my mindpalace")

1. Read all items.
2. For items with a missing/truncated title, empty tags, or empty summary: write a short
   descriptive title (≤60 chars), 2–5 tags, and a one-sentence summary of why it was saved.
   For `image` items the content is a path under `agent/data/` (e.g. `vault/xxxx.png`) —
   Read the image file itself to see it, then summarize what it shows so it becomes
   text-searchable. For `file` items go by name/extension only; never open vault files as text.
3. Normalize tags across items — same concept, same tag (e.g. `hospital-master`, not both
   `hospitalmaster` and `hospital_master`).
4. Report, don't touch: likely duplicates (cite ids), stale-looking items, and anything
   that might belong together as one topic.
5. Finish with a short report: items updated, tags normalized, duplicates/suggestions.

### ask ("what did I save about X", "find my note on X")

Search titles, tags, summaries, and content (try both Japanese and English terms).
Answer from the items, citing ids like `[61088946]`, and quote the relevant capture.
If nothing matches, say so — don't invent.

### add ("add this to my mindpalace", "save this")

Append a new item: fresh 8-char id, `type: "text"`, `createdAt` now, and write the
title/tags/summary yourself at capture time. Keep the user's text as `content` verbatim.

### import ("import mind.txt")

`mind.txt` at the repo root is the user's old flat scratchpad. Split it into discrete
items (a topic, note, or snippet each — blank-line runs and heading changes are the usual
boundaries), preserve each chunk verbatim as `content`, enrich metadata, and append all of
them to `palace.json`. Show a count and sample before writing; never modify `mind.txt` itself.
