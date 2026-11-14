# MindPalace on Linux

**Easiest path**: the one-file installer. Run `scripts/package.ps1` on the Windows
machine to generate `dist/linux/` (install.sh + README), copy that folder to the
Linux box, and run `./install.sh`. It installs dependencies, builds, and sets up
Hyprland rules, hotkeys, and autostart interactively — everything below is what
it automates, kept here as the manual reference.

The same codebase builds natively for Linux. You must build **on** a Linux machine
(no cross-compiling from Windows); the output is a `.deb`, `.rpm`, and an AppImage
under `src-tauri/target/release/bundle/`.

## 1. Install build dependencies

**Debian / Ubuntu**
```bash
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
```

**Fedora**
```bash
sudo dnf install webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel librsvg2-devel libxdo-devel
```

**Arch / Omarchy**
```bash
sudo pacman -S --needed webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module libappindicator-gtk3 librsvg xdotool
```

Plus Rust (`rustup`) and Node 20+ on all of them.

## 2. Build

```bash
cd app
npm install
npm run tauri dev     # try it
npm run tauri build   # .deb / .rpm / AppImage
```

## 3. Platform behavior

| Feature | Linux behavior |
|---|---|
| Glass blur | No OS acrylic. The window ships with a dark translucent tint (`.linux .shell` in `src/App.css`). On Hyprland, enable compositor blur (below) for true glass — you can lower the tint's alpha once blur is on. |
| Global hotkey | Works on **X11**. On **Wayland** (Hyprland, GNOME) apps cannot register global hotkeys — bind a compositor key instead (below). The app is single-instance: launching it again toggles the existing window, so a key bound to `exec` the binary *is* the hotkey. |
| Always on top | Works on X11. On Hyprland, add a `pin` window rule if you want it on every workspace (pinned windows can't tile, so the installer doesn't pin by default). |
| Tray | Works via appindicator. Hyprland needs a bar with a tray (Waybar has one); GNOME needs the AppIndicator extension. |
| Autostart | XDG autostart entry, handled by the same plugin (release builds only). |
| Everything else | Drag & drop, clipboard image paste, open/reveal, storage — all work unchanged. |

## 4. Hyprland setup (Omarchy)

> The installer writes all of this for you, picking the right syntax. Hyprland's
> config changed twice recently: 0.53+ rejects `windowrulev2` (new form:
> `windowrule = float on, match:title ^MindPalace$`), and 0.55+/Omarchy quattro
> use a Lua config (`hyprland.lua`) where the installer writes `mindpalace.lua`
> with `hl.window_rule({ match = { title = "^MindPalace$" }, float = true,
> size = {650, 500}, center = true })` plus the open/hide `hl.bind` line.
> No float↔tile key is bound: your own `togglefloating` bind tiles/floats
> MindPalace like any other window.
> Below is the classic pre-0.53 syntax.

```ini
# ~/.config/hypr/hyprland.conf

# Float by default; your togglefloating key tiles it like any window
windowrulev2 = float, title:^(MindPalace)$
windowrulev2 = size 650 500, title:^(MindPalace)$
windowrulev2 = center, title:^(MindPalace)$
windowrulev2 = opacity 1.0 override, title:^(MindPalace)$

# Real glass: compositor blur behind the transparent window
decoration {
    blur {
        enabled = true
        size = 8
        passes = 2
    }
}

# The hotkey: relaunching toggles the running instance
bind = CTRL SHIFT, SPACE, exec, mindpalace
```

(`mindpalace` = the installed binary, or the AppImage path.)

## 5. Sharing one palace across machines

The whole palace is a folder: `agent/data/` (`palace.json` + `vault/`). Put it in a
synced folder (Syncthing, OneDrive, Dropbox) and point both machines at it:

```bash
# Linux (e.g. in the .desktop file or shell profile)
export MINDPALACE_DATA="$HOME/Sync/MindPalace/palace.json"
```

```powershell
# Windows
setx MINDPALACE_DATA "C:\Users\s-kumar\Sync\MindPalace\palace.json"
```

The vault is resolved relative to that file, so it travels along.
