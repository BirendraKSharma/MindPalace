# MindPalace — Linux OFFLINE install

One file, no internet, no compiler: a prebuilt AppImage (with WebKitGTK and
every library bundled) is embedded inside `install.sh`. It installs in
seconds on any Linux machine.

```bash
chmod +x install.sh
./install.sh
```

Variants:

```bash
./install.sh --dry-run
```

```bash
./install.sh --defaults
```

```bash
./install.sh --uninstall
```

`--dry-run` shows every change without touching anything. `--uninstall`
removes the app but **never** your palace data.

## What it asks

| Prompt | Default |
|---|---|
| Launcher location | `~/.local/bin` |
| App files location | `~/.local/lib/mindpalace` |
| Palace location | `~/.local/share/MindPalace/palace.json` |
| Open/hide hotkey | `Ctrl+Shift+Space` |
| Floating window size | `650x500` |
| Autostart at login | yes |
| Hyprland integration | yes (when detected) |

On Hyprland/Omarchy the window floats by default (centered, resizable);
**your own togglefloating key** tiles it like any other window — the
installer binds nothing except the open/hide hotkey.

## How it differs from the normal installer

| | `MindPalace-linux.zip` | this package |
|---|---|---|
| Internet needed | yes (deps, Rust, npm) | **no** |
| Install time | 10–20 min (compiles) | **seconds** |
| Size | ~2 MB | ~80–100 MB |
| Needs Rust/Node | yes | no |

The AppImage is extracted at install time (no FUSE needed, instant app
startup). Hyprland/Omarchy integration, theming, hotkey and autostart are
identical to the normal installer, and reinstalling **merges** into your
existing `config.json` instead of overwriting it.

## Rebuilding this package

On any Linux machine with the build deps (see `BUILDING.md` in the source
zip):

```bash
./scripts/package-linux-offline.sh
```

That produces `dist/MindPalace-linux-offline.zip` ready to share.

## After install / troubleshooting

- Settings: `config.json` next to `palace.json` (`hotkey`, `window`,
  `autostart`, `theme`, `searchUrl`, `ai`). The app follows your system
  light/dark theme; `"theme": "dark"` or `"light"` forces one.
- `mindpalace: command not found` → `~/.local/bin` isn't on your PATH.
- The AI ✦ button is optional and off by default — nothing ever leaves the
  app while off. `ollama` is the fully offline AI option.
