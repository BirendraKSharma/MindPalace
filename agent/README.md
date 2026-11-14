# MindPalace Agent

The AI layer from Phase 4 of [PLAN.md](../PLAN.md), built as a standalone TypeScript module so the future Tauri app can call it directly (`enrichItem`, `ask`, `organize`). Until the app exists, a small CLI exercises it.

## What it does

| Function | Model behavior |
|---|---|
| `enrichItem(item)` | One cheap structured-output call: generates **title, 2–5 tags, one-line summary** for a capture. Best-effort — a capture is never lost if the API call fails. |
| `ask(question)` | Agent loop with search/read tools over the palace. Answers with `[id]` citations. |
| `organize()` | Agent loop that fills missing metadata, normalizes tags, reports (never auto-archives) duplicates. Metadata-only: there is deliberately **no delete tool**. |

Storage is a JSON file (`data/palace.json`) with the same shape as the planned SQLite `items` table — swap `src/store.ts` to SQLite later without touching the agent.

## No API key? Use the skill instead

The user's account is enterprise (no Console API key), so the functions above can't call
the API. The project skill at `.claude/skills/mindpalace/SKILL.md` covers the same jobs
through Claude Code itself: in any session in this repo, say **"organize my mindpalace"**,
**"what did I save about X"**, **"add this to my mindpalace"**, or **"import mind.txt"**.
It edits the same `data/palace.json`, backs up before bulk writes, and never touches item
content. This module stays as the integration layer for the future app, for when a key exists.

## Setup

```powershell
cd agent
npm install
$env:ANTHROPIC_API_KEY = "sk-ant-..."   # or set it permanently in Windows env vars
```

Optional: `$env:MINDPALACE_MODEL` overrides the model (default `claude-opus-5-5`).

## Usage

```powershell
npm run palace -- add "some note text"
npm run palace -- list
npm run palace -- ask "what did I note about fax validation?"
npm run palace -- organize
```

`add`/`list` work offline; `ask`/`organize` and enrichment need the API key.
