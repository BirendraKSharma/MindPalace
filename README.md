# MindPalace

Always-on-top scratchpad for your notes, thoughts, and quick AI commands. Frameless, acrylic-glass window that floats above everything — press a hotkey, jot something down, press again to hide.

```
23 * 56 --calc      →  23 * 56 = 1288
tauri window rules --search   → opens browser with search results
こんにちは --translate        →  AI translates (Japanese ↔ English)
some rough text --rephrase    →  AI rewrites for clarity
```

AI is **off by default** (privacy). Click the ✦ titlebar button to connect — nothing is ever sent while off.

---

## One-command install

### Linux (Arch / Omarchy / Debian / Fedora)

```bash
curl -fsSL https://raw.githubusercontent.com/BirendraKSharma/MindPalace/main/install.sh | bash
```

What it does: installs build deps + Rust + Node if missing, builds from source, installs the `mindpalace` binary to `~/.local/bin`, adds the desktop shortcut, and (on Hyprland/Omarchy) wires up the `Ctrl+Shift+Space` hotkey and floating window rules.

### Windows

```powershell
iwr -useb https://raw.githubusercontent.com/BirendraKSharma/MindPalace/main/install.ps1 | iex
```

What it does: downloads the source, builds with Rust + Node, installs the app to `%LOCALAPPDATA%\MindPalace`, sets `MINDPALACE_DATA`, and creates the shortcut. Requires [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022) ("Desktop development with C++" workload) for the Rust linker.

> Your palace data (`palace.json`) is never touched by installs or uninstalls — it survives upgrades.

---

## Features

| Feature | How |
|---|---|
| **Calc** | `23 * 56 --calc` — offline arithmetic, no `eval()` |
| **Search** | `query --search` — opens your browser |
| **Fuzzy search** | `Ctrl+K` in the sidebar over title/tags/content |
| **AI translate** | `text --translate` — Japanese ↔ English (AI-connected only) |
| **AI rephrase** | `text --rephrase` — clearer, same language (AI-connected only) |
| **Custom AI skills** | Add `## name` sections to `SKILLS.md` — no code needed |
| **Images** | Paste (`Ctrl+V`) or drag-drop images into the vault |
| **Files** | Drag-drop any file — copied into the vault |
| **Global hotkey** | `Ctrl+Shift+Space` toggles show/hide |
| **Tray** | Click to toggle, right-click for Show/Hide/Quit |
| **Autostart** | Optional launch on login |

---

## AI setup (opt-in, privacy-first)

AI is off by default. Connect it from the ✦ titlebar button.

The app finds `claude`, `codex`, `opencode`, or `ollama` on `PATH`, or you can use a `custom` command in `config.json`:

```json
{
  "ai": "custom",
  "aiCommand": [
    "/full/path/to/opencode",
    "run",
    "{prompt}"
  ]
}
```

Skills live in `SKILLS.md` next to `palace.json` — each `## name` section becomes a `--name` command. `--translate` and `--rephrase` ship by default.

Only the single line you run a command on is ever sent — never the whole note or your palace.

---

## Quick start

```bash
# Linux
mindpalace                    # or Ctrl+Shift+Space
# type in the pad, press Enter to save
# Ctrl+K to search, Ctrl+N for new note
```

---

## Contributing

All source is in this repo — frontend (`app/src/`, React + TypeScript), backend (`app/src-tauri/src/lib.rs`, Rust/Tauri 2), and installers (`installers/`).

```bash
git clone https://github.com/BirendraKSharma/MindPalace.git
cd MindPalace/app
npm install
npm run tauri dev        # dev run
npm run tauri build      # release build
```

See `BUILDING.md` for platform prerequisites and `SHORTCUTS.md` for every key.

---

## Repository layout

```
app/               # Tauri 2 app — React frontend + Rust backend
installers/        # install.sh (Linux) and install.ps1 (Windows)
scripts/           # packaging scripts for shipping zips
agent/             # dev-time data store (palace.json + vault)
.claude/           # Claude Code skill that organizes the palace
BUILDING.md        # build prerequisites per platform
PLAN.md            # design notes and roadmap
SHORTCUTS.md       # every key and inline command
LICENSE            # MIT
```

---

## License

MIT — do whatever you like. If you fork, strip `agent/data/` (your palace is private) before sharing.