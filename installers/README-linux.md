# MindPalace — Linux install

One file does everything. It carries the full source (and your palace data)
inside it, asks a few questions, builds, and wires up your desktop.

```bash
chmod +x install.sh
./install.sh
```

Useful variants:

```bash
./install.sh --dry-run
```

```bash
./install.sh --defaults
```

```bash
./install.sh --uninstall
```

`--dry-run` shows every change it would make without touching anything —
run this first on a new machine. `--uninstall` removes the app but **never**
your palace data.

> Building needs internet (packages, Rust, npm). For machines without it,
> there is an **offline package** with a prebuilt app inside — build it once
> on any Linux box with `./scripts/package-linux-offline.sh` (from the
> source zip), which emits `MindPalace-linux-offline.zip`.

## What it asks

| Prompt | Default | Notes |
|---|---|---|
| Install build dependencies | yes | pacman / apt / dnf detected from `/etc/os-release`; installs Rust (rustup) and Node if missing |
| Binary location | `~/.local/bin` | the `mindpalace` binary lands here |
| Palace location | `~/.local/share/MindPalace/palace.json` | your notes + vault; point it at a synced folder (Syncthing etc.) to share one palace across machines |
| Copy bundled palace data | yes | only if the target doesn't already have a palace.json |
| Open/hide hotkey | `Ctrl+Shift+Space` | on Hyprland this becomes a compositor bind; on X11 the app registers it itself |
| Floating window size | `650x500` | change later in `~/.config/hypr/mindpalace.{lua,conf}` and config.json |
| Autostart at login | yes | |
| Hyprland integration | yes (when detected) | window rules + the open/hide bind, see below |

## Omarchy / Hyprland

MindPalace floats by default: centered, 650×500, resizable. It is a normal
window otherwise — **your own togglefloating key** (`Super+T` on many Omarchy
setups) tiles it into the layout and floats it back, exactly like any other
window. The installer binds **nothing** except the open/hide hotkey and never
touches your existing keybinds.
The open/hide hotkey works by relaunching the binary — the app is
single-instance, so a second launch toggles the existing window.

The installer detects your config format:

- **`hyprland.lua`** (Omarchy quattro, Hyprland 0.55+): writes
  `~/.config/hypr/mindpalace.lua` and adds one `require` line to
  `hyprland.lua`.
- **`hyprland.conf`** (older setups): writes `~/.config/hypr/mindpalace.conf`
  and adds one `source` line, using the windowrule syntax that matches your
  Hyprland version (`hyprctl version`).

Everything it writes is marked as generated — delete the file and the one
require/source line (or run `--uninstall`) to undo.

**Frosted glass**: the window is a strong dark (or light) tint with a little
transparency. For the real frosted look, enable compositor blur in your
Hyprland `decoration { blur { ... } }` block — the glass picks it up through
the remaining alpha. The generated `.conf` rules include
`opacity 1.0 override` so theme-wide transparency rules don't stack on top
and wash the text out; if you use the Lua config and your theme dims
windows, add the same opacity rule for the `MindPalace` title.

## Other desktops

- **X11** (KDE/XFCE/GNOME-X11): the hotkey just works; autostart via
  `~/.config/autostart`.
- **GNOME/KDE on Wayland**: apps can't register global hotkeys — bind a key
  in your desktop's own shortcut settings to run `~/.local/bin/mindpalace`
  (launching again toggles the window).

## After install

- App settings live in `config.json` next to `palace.json`
  (`hotkey`, `fallbackHotkey`, `window: {width,height}`, `autostart`, `theme`).
- The app follows your system light/dark theme automatically — on Omarchy,
  switching themes switches MindPalace too (via the GTK color-scheme).
  `"theme": "dark"` or `"light"` in config.json forces one instead.
- The window: **Esc** or close hides to tray, quit from the tray menu.
  Full shortcut list: `app/SHORTCUTS.md` inside the archive (the installer
  extracts it to a temp dir; it's also in the repo).

## AI (optional, off by default)

The ✦ button in the titlebar connects an AI CLI if you have one (`claude`,
`codex`, `opencode`, or `ollama` — ollama runs fully offline). While off,
nothing is ever sent anywhere; everything except AI commands works without it.
Commands live in `SKILLS.md` next to palace.json — each `## name` section is a
`--name` command in the pad (`--translate`, `--rephrase` by default).

## Troubleshooting

- `mindpalace: command not found` → `~/.local/bin` isn't on your PATH.
- Build fails on missing `webkit2gtk` → re-run and accept the dependency
  install, or see the distro lines it prints.
- `hyprctl reload` complains → your Hyprland version may want different
  syntax; open `~/.config/hypr/mindpalace.{lua,conf}` and adjust — the file
  is small and commented.
