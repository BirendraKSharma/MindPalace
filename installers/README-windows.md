# MindPalace — Windows install

One file does everything: the real setup program is embedded inside
`install.ps1`. It asks a few questions (Enter accepts the default),
installs, configures, and launches.

```bash
powershell -ExecutionPolicy Bypass -File install.ps1
```

Variants:

```bash
powershell -ExecutionPolicy Bypass -File install.ps1 -Defaults
```

```bash
powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
```

`-Uninstall` removes the app but **never** your palace data.

## What it asks

| Prompt | Default | Notes |
|---|---|---|
| Install folder | `%LOCALAPPDATA%\MindPalace` | per-user, no admin rights needed |
| Palace location | existing `MINDPALACE_DATA`, else `%APPDATA%\MindPalace\palace.json` | your notes + vault; point it at a synced folder to share one palace across machines |
| Open/hide hotkey | `Ctrl+Shift+Space` | any `Mod+Mod+Key` combination, e.g. `Alt+Space`, `Ctrl+Alt+M` |
| Autostart at login | yes | |

## After install

- **Hotkey** toggles the window; **Esc** or the close button hides it to the
  tray; quit from the tray icon's menu.
- Settings live in `config.json` next to `palace.json`:

  ```json
  {
    "hotkey": "ctrl+shift+space",
    "fallbackHotkey": "alt+space",
    "window": { "width": 1000, "height": 720 },
    "autostart": true,
    "theme": "dark"
  }
  ```

  Every key is optional. Change it, quit from the tray, relaunch.
- The app follows the Windows light/dark app mode automatically, live.
  `"theme": "dark"` or `"light"` in config.json forces one instead.
- The `MINDPALACE_DATA` user environment variable points the app (and the
  MindPalace Claude Code skill) at your palace.json.

## AI (optional, off by default)

The ✦ button in the titlebar connects an AI CLI if you have one (`claude`,
`codex`, `opencode`, or `ollama` — ollama runs fully offline). While off,
nothing is ever sent anywhere; everything except AI commands works without it.
Commands live in `SKILLS.md` next to palace.json — each `## name` section is a
`--name` command in the pad (`--translate`, `--rephrase` by default).

## Notes

- The script is unsigned, hence `-ExecutionPolicy Bypass`. If SmartScreen
  prompts about the extracted setup program, choose "Run anyway" — it was
  built from this project's source.
- Reinstalling over an existing copy is fine; your data is a separate folder
  and is never written by the installer unless it's missing.
