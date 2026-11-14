# Building MindPalace from source

MindPalace is a Tauri 2 app: a React/TypeScript frontend inside a tiny Rust
shell. This guide takes you from a fresh machine to your own build — change
anything you like and ship your own version.

## Prerequisites

**All platforms**

- **Rust** — install via [rustup](https://rustup.rs) (stable toolchain).
- **Node.js 20+** — [nodejs.org](https://nodejs.org) or your package manager.

**Windows**

- Visual Studio **Build Tools** with the "Desktop development with C++"
  workload (the Rust MSVC toolchain needs its linker).
- WebView2 runtime — preinstalled on Windows 10/11.

**Linux** (Tauri needs the WebKitGTK stack)

```bash
# Arch / Omarchy
sudo pacman -S --needed webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module libappindicator-gtk3 librsvg xdotool
```

```bash
# Debian / Ubuntu
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
```

```bash
# Fedora
sudo dnf install webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel librsvg2-devel libxdo-devel
```

## Run and build

```bash
cd app
npm install
npm run tauri dev     # development run (the first Rust build takes a while)
npm run tauri build   # release build
```

Release artifacts land under `app/src-tauri/target/release/`:
the bare executable, plus an NSIS installer on Windows
(`bundle/nsis/*-setup.exe`) or .deb/.rpm/AppImage on Linux.

In dev runs the palace data lives in `agent/data/` (created on first save);
installed builds read the `MINDPALACE_DATA` location — see `app/README.md`.

## Repository map

| Path | What it is |
|---|---|
| `app/src/` | React frontend — `App.tsx` (shell, titlebar, sidebar), `Editor.tsx` (CodeMirror pad), `commands.ts` (inline `--command` parsing, offline calculator) |
| `app/src-tauri/src/lib.rs` | The entire Rust side: window/tray/hotkey, storage, vault, `--search`, the AI bridge |
| `app/src-tauri/tauri.conf.json` | Window flags (frameless, transparent, always-on-top), bundle + icons |
| `agent/` | Dev-time data directory and the palace JSON store |
| `installers/` | Templates for the self-extracting installers (`install.ps1`, `install.sh`, `install-offline.sh`, per-OS READMEs) |
| `scripts/package.ps1` | Builds the three shipping zips in `dist/` (see below) |
| `.claude/skills/mindpalace` | Claude Code skill that organizes/searches the palace |
| `PLAN.md` | Design notes and roadmap |

Docs worth reading before you customize: `app/README.md` (data locations,
platform behavior), `app/SHORTCUTS.md` (every key and inline command),
`app/LINUX.md` (Hyprland/Omarchy specifics).

## Where to customize

- **Inline commands**: offline ones (like `--calc`) live in
  `app/src/commands.ts` + the Enter handler in `Editor.tsx`; `--search` is in
  `lib.rs` (`web_search`). AI commands need **no code at all** — every
  `## name` section in `SKILLS.md` (next to palace.json, created on first AI
  connect) becomes a `--name` command.
- **AI backends**: `lib.rs` (`AI_BACKENDS`, `backend_argv`) — presets for
  claude / codex / opencode / ollama, or set `"ai": "custom"` with an
  `"aiCommand"` argv template in config.json. AI is **off by default**; while
  off the app never spawns any AI process.
- **Look**: all colors are CSS variables at the top of `app/src/App.css`,
  with dark as the default and a light block under
  `@media (prefers-color-scheme: light)` — the app follows the OS theme
  (`"theme": "dark" | "light"` in config.json forces one).
- **config.json keys** (next to palace.json): `hotkey`, `fallbackHotkey`,
  `window {width,height}`, `autostart`, `searchUrl`, `theme`,
  `ai`, `aiModel`, `aiCommand`.

## Packaging installers (optional)

`scripts/package.ps1` (Windows PowerShell) builds `dist/`:

- `MindPalace-windows.zip` — README + `install.ps1` with the NSIS setup exe
  embedded (base64 in a trailing block comment).
- `MindPalace-linux.zip` — README + `install.sh` with a source tarball
  embedded; it builds on the target machine and wires up the desktop
  (Hyprland rules, autostart).
- `MindPalace-source.zip` — this source tree, for developers.

`scripts/package-linux-offline.sh` (run **on Linux**) builds a fourth one:
`dist/MindPalace-linux-offline.zip` — a prebuilt AppImage wrapped in a
self-extracting installer that needs **no internet, Rust or Node** on the
target machine and installs in seconds (~100 MB instead of 2 MB).

On Linux you don't need the packager: `npm run tauri build` already gives
you .deb / .rpm / AppImage, or run `installers/install.sh` from the repo.

## License / sharing

Personal project — if you fork it, strip `agent/data/` (your palace is
private data) before sharing anything.
