#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  MindPalace installer for Linux (Omarchy / Arch / Debian / Fedora)
#
#  Self-extracting: the project source (and your palace data, if bundled)
#  is appended to this file after the __ARCHIVE__ marker. Run it, answer
#  the prompts (Enter accepts the default), done.
#
#  Flags:
#    --defaults    no questions, accept every default
#    --dry-run     show what would be done, change nothing
#    --uninstall   remove the app (palace data is never touched)
#    --help
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

DEFAULTS=0 DRYRUN=0 UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --defaults) DEFAULTS=1 ;;
    --dry-run) DRYRUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
    *) echo "unknown flag: $a (see --help)" >&2; exit 1 ;;
  esac
done

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
note()  { printf '  \033[2m%s\033[0m\n' "$*"; }
warn()  { printf '  \033[33m! %s\033[0m\n' "$*"; }
run() { # honor --dry-run for anything that changes the system
  if [ "$DRYRUN" = 1 ]; then printf '  \033[36mdry-run:\033[0m %s\n' "$*"; else "$@"; fi
}
ask() { # ask VAR "question" "default"
  local var=$1 q=$2 def=$3 reply
  if [ "$DEFAULTS" = 1 ]; then reply=$def; else
    read -r -p "$(printf '\033[1m?\033[0m %s [%s]: ' "$q" "$def")" reply || reply=""
    reply=${reply:-$def}
  fi
  printf -v "$var" '%s' "$reply"
}
confirm() { # confirm "question" default(y/n) → return 0 for yes
  local q=$1 def=${2:-y} reply
  if [ "$DEFAULTS" = 1 ]; then reply=$def; else
    read -r -p "$(printf '\033[1m?\033[0m %s [%s]: ' "$q" "$def")" reply || reply=""
    reply=${reply:-$def}
  fi
  [[ "$reply" =~ ^[Yy] ]]
}
write_file() { # write_file PATH <<'EOF' ... (honors --dry-run)
  local path=$1
  if [ "$DRYRUN" = 1 ]; then
    printf '  \033[36mdry-run: write %s:\033[0m\n' "$path"; sed 's/^/    │ /'
  else
    mkdir -p "$(dirname "$path")"; cat > "$path"
  fi
}

# ── hotkey conversions ───────────────────────────────────────────────
# Input style: Ctrl+Shift+Space / Super+T (what the app's config.json uses)
to_lua_key() { # → "CTRL + SHIFT + Space"
  local out="" tok
  IFS='+' read -ra toks <<< "$1"
  for tok in "${toks[@]}"; do
    tok=$(echo "$tok" | tr -d ' ')
    case "${tok,,}" in
      ctrl|control) tok="CTRL" ;;
      shift) tok="SHIFT" ;;
      alt) tok="ALT" ;;
      super|win|cmd|mod) tok="SUPER" ;;
      *) tok="$(tr '[:lower:]' '[:upper:]' <<< "${tok:0:1}")${tok:1}" ;;
    esac
    out+="${out:+ + }$tok"
  done
  printf '%s' "$out"
}
to_conf_mods() { # → "CTRL SHIFT" (everything but the last token)
  local out="" tok
  IFS='+' read -ra toks <<< "$1"
  for tok in "${toks[@]::${#toks[@]}-1}"; do
    tok=$(echo "$tok" | tr -d ' ')
    case "${tok,,}" in
      ctrl|control) tok="CTRL" ;; shift) tok="SHIFT" ;; alt) tok="ALT" ;;
      super|win|cmd|mod) tok="SUPER" ;; *) tok=$(tr '[:lower:]' '[:upper:]' <<< "$tok") ;;
    esac
    out+="${out:+ }$tok"
  done
  printf '%s' "$out"
}
to_conf_key() { # → "Space" (last token, first letter upper)
  local toks; IFS='+' read -ra toks <<< "$1"
  local k=$(echo "${toks[-1]}" | tr -d ' ')
  printf '%s' "$(tr '[:lower:]' '[:upper:]' <<< "${k:0:1}")${k:1}"
}

HYPR_DIR="$HOME/.config/hypr"

# ── uninstall ────────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  bold "Uninstalling MindPalace (palace data stays where it is)"
  ask BIN_DIR "Where was the binary installed" "$HOME/.local/bin"
  run rm -f "$BIN_DIR/mindpalace" "$BIN_DIR/mindpalace-toggle-tile"
  run rm -f "$HOME/.local/share/applications/mindpalace.desktop"
  run rm -f "$HOME/.local/share/icons/hicolor/128x128/apps/mindpalace.png"
  run rm -f "$HOME/.config/autostart/mindpalace.desktop"
  for f in "$HYPR_DIR/mindpalace.lua" "$HYPR_DIR/mindpalace.conf"; do
    [ -e "$f" ] && run rm -f "$f"
  done
  if [ -f "$HYPR_DIR/hyprland.lua" ] && grep -q 'mindpalace' "$HYPR_DIR/hyprland.lua"; then
    run sed -i '/mindpalace/d' "$HYPR_DIR/hyprland.lua"
  fi
  if [ -f "$HYPR_DIR/hyprland.conf" ] && grep -q 'mindpalace' "$HYPR_DIR/hyprland.conf"; then
    run sed -i '/mindpalace/d' "$HYPR_DIR/hyprland.conf"
  fi
  command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && run hyprctl reload >/dev/null
  bold "Done. Your palace.json and vault were not touched."
  exit 0
fi

bold "MindPalace installer"

# ── locate the source: embedded archive, or a repo checkout ──────────
SRC_DIR=""
CLEANUP_SRC=0
ARCHIVE_LINE=$(awk '/^__ARCHIVE__$/{print NR+1; exit}' "$0" || true)
# (test via $(...) so a SIGPIPE from head can't fail the pipeline under pipefail)
HAS_PAYLOAD=0
if [ -n "$ARCHIVE_LINE" ] && [ -n "$(tail -n +"$ARCHIVE_LINE" "$0" | head -c 1)" ]; then
  HAS_PAYLOAD=1
fi
if [ "$HAS_PAYLOAD" = 1 ]; then
  SRC_DIR=$(mktemp -d /tmp/mindpalace-src.XXXXXX)
  CLEANUP_SRC=1
  note "extracting bundled source to $SRC_DIR"
  tail -n +"$ARCHIVE_LINE" "$0" | base64 -d | tar xz -C "$SRC_DIR"
elif [ -d "$(dirname "$0")/../app" ]; then
  SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
  note "using repo checkout at $SRC_DIR"
else
  echo "No embedded archive and no repo found next to this script." >&2
  exit 1
fi
trap 'if [ "$CLEANUP_SRC" = 1 ]; then rm -rf "$SRC_DIR"; fi' EXIT

# ── distro + dependencies ────────────────────────────────────────────
PM=""
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in
    *arch*) PM=pacman ;;
    *debian*|*ubuntu*) PM=apt ;;
    *fedora*|*rhel*) PM=dnf ;;
  esac
fi
case "$PM" in
  pacman) DEPS=(webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module libappindicator-gtk3 librsvg xdotool jq)
          DEP_CMD=(sudo pacman -S --needed --noconfirm) ;;
  apt)    DEPS=(libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev jq)
          DEP_CMD=(sudo apt install -y) ;;
  dnf)    DEPS=(webkit2gtk4.1-devel openssl-devel curl wget file gcc gcc-c++ make libappindicator-gtk3-devel librsvg2-devel libxdo-devel jq)
          DEP_CMD=(sudo dnf install -y) ;;
  *)      DEPS=(); warn "unrecognized distro — install the Tauri Linux deps yourself (see app/LINUX.md)" ;;
esac
if [ ${#DEPS[@]} -gt 0 ] && confirm "Install build dependencies via $PM (${#DEPS[@]} packages)" y; then
  run "${DEP_CMD[@]}" "${DEPS[@]}"
fi

# Rust + Node
if ! command -v cargo >/dev/null 2>&1; then
  if confirm "Rust not found — install rustup now" y; then
    run bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  else
    echo "cargo is required to build. Aborting." >&2; exit 1
  fi
fi
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -v | sed 's/^v//' | cut -d. -f1)
  [ "$NODE_MAJOR" -lt 18 ] && warn "Node $NODE_MAJOR is too old (need 18+) — install a newer Node first" && exit 1
else
  case "$PM" in
    pacman) NODE_PKGS=(nodejs npm) ;;
    apt)    NODE_PKGS=(nodejs npm) ;;
    dnf)    NODE_PKGS=(nodejs) ;;
    *)      NODE_PKGS=() ;;
  esac
  if [ ${#NODE_PKGS[@]} -gt 0 ] && confirm "Node.js not found — install via $PM" y; then
    run "${DEP_CMD[@]}" "${NODE_PKGS[@]}"
  else
    echo "Node.js 18+ is required to build. Aborting." >&2; exit 1
  fi
fi

# ── questions ────────────────────────────────────────────────────────
ask BIN_DIR   "Install the binary where"              "$HOME/.local/bin"
ask DATA_FILE "Where should your palace live (palace.json)" "$HOME/.local/share/MindPalace/palace.json"
ask HOTKEY    "Global open/hide hotkey"               "Ctrl+Shift+Space"
ask WIN_SIZE  "Floating window size (WIDTHxHEIGHT)"   "650x500"
confirm "Start MindPalace automatically on login" y && AUTOSTART=true || AUTOSTART=false

WIN_W=${WIN_SIZE%%[xX×]*}; WIN_H=${WIN_SIZE##*[xX×]}
case "$WIN_W$WIN_H" in (*[!0-9]*) warn "could not parse '$WIN_SIZE' — using 650x500"; WIN_W=650; WIN_H=500 ;; esac

HYPR=0
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ -d "$HYPR_DIR" ]; then
  if confirm "Hyprland detected — write window rules + keybinds for it" y; then
    HYPR=1
  fi
fi

# ── AI backend selection ───────────────────────────────────────────────
AI_BACKEND="off"
AI_COMMAND=""
AI_MODEL=""
if [ "$DEFAULTS" = 1 ]; then
  AI_BACKEND="off"   # privacy default: AI stays off until user connects manually
else
  echo
  echo "AI backends found on this system:"
  FOUND=()
  for name in claude codex opencode ollama; do
    if command -v "$name" >/dev/null 2>&1; then
      FOUND+=("$name")
      echo "  ${#FOUND[@]}) $name"
    fi
  done
  echo "  0) none (AI off — enable later from the titlebar button)"
  echo "  c) custom (enter your own AI command)"
  read -r -p "Configure AI backend [0]: " AI_CHOICE
  AI_CHOICE=${AI_CHOICE:-0}
  case "$AI_CHOICE" in
    0) AI_BACKEND="off" ;;
    c|C)
      read -r -p "Custom AI command (argv JSON, e.g. [\"/usr/bin/opencode\",\"run\",\"{prompt}\"]): " AI_COMMAND
      AI_BACKEND="custom"
      ;;
    *)
      idx=$((AI_CHOICE - 1))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#FOUND[@]}" ]; then
        AI_BACKEND="${FOUND[$idx]}"
        if [ "$AI_BACKEND" = "ollama" ]; then
          read -r -p "Ollama model (e.g. qwen2.5:3b): " AI_MODEL
          AI_MODEL=${AI_MODEL:-qwen2.5:3b}
        fi
      else
        AI_BACKEND="off"
      fi
      ;;
  esac
fi

DATA_DIR=$(dirname "$DATA_FILE")
BIN="$BIN_DIR/mindpalace"

# ── bundled palace data ──────────────────────────────────────────────
if [ -f "$SRC_DIR/agent/data/palace.json" ]; then
  if [ -f "$DATA_FILE" ]; then
    note "palace.json already exists at $DATA_FILE — keeping it"
  elif confirm "This package contains palace data — copy it to $DATA_DIR" y; then
    run mkdir -p "$DATA_DIR"
    run cp "$SRC_DIR/agent/data/palace.json" "$DATA_FILE"
    [ -d "$SRC_DIR/agent/data/vault" ] && run cp -r "$SRC_DIR/agent/data/vault" "$DATA_DIR/"
  fi
fi

# ── build ────────────────────────────────────────────────────────────
bold "Building (first Rust build takes a while — coffee time)"
if [ "$DRYRUN" = 1 ]; then
  note "dry-run: would run npm install && npm run tauri build in $SRC_DIR/app"
else
  (cd "$SRC_DIR/app" && npm install && npm run tauri build)
fi
BUILT="$SRC_DIR/app/src-tauri/target/release/app"
if [ "$DRYRUN" = 0 ] && [ ! -x "$BUILT" ]; then
  echo "Build finished but $BUILT is missing — check the build output above." >&2
  exit 1
fi

# ── install files ────────────────────────────────────────────────────
run mkdir -p "$BIN_DIR" "$DATA_DIR"
run install -m 755 "$BUILT" "$BIN"
# clean up the float/tile helper older versions installed (Hyprland's own
# togglefloating key now does that job — nothing is rebound anymore)
[ -e "$BIN_DIR/mindpalace-toggle-tile" ] && run rm -f "$BIN_DIR/mindpalace-toggle-tile"

ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
run mkdir -p "$ICON_DIR"
run cp "$SRC_DIR/app/src-tauri/icons/128x128.png" "$ICON_DIR/mindpalace.png"

write_file "$HOME/.local/share/applications/mindpalace.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MindPalace
Comment=Always-on-top scratchpad (launch again to toggle the window)
Exec=env "MINDPALACE_DATA=$DATA_FILE" "$BIN"
Icon=mindpalace
Terminal=false
Categories=Utility;
EOF

# app settings: the app reads these at startup (hotkey works on X11;
# on Wayland the compositor bind below is the hotkey). MERGE into an
# existing config.json — a reinstall must never wipe the user's keys
# (ai, searchUrl, theme, window, ...).
if [ "$DRYRUN" = 1 ]; then
  note "dry-run: merge hotkey/autostart/window/ai into $DATA_DIR/config.json"
elif [ -f "$DATA_DIR/config.json" ] && command -v jq >/dev/null 2>&1; then
  if [ "$AI_BACKEND" = "custom" ]; then
    AI_CMD_JSON="$AI_COMMAND"
  else
    AI_CMD_JSON="[]"
  fi
  jq --arg hk "$HOTKEY" --argjson as "$AUTOSTART" --argjson w "$WIN_W" --argjson h "$WIN_H" \
     --arg ai "$AI_BACKEND" --argjson ac "$AI_CMD_JSON" --arg am "$AI_MODEL" \
     '. + {hotkey: $hk, autostart: $as, window: {width: $w, height: $h}, ai: $ai, aiCommand: $ac, aiModel: $am}' \
     "$DATA_DIR/config.json" > "$DATA_DIR/config.json.tmp" && mv "$DATA_DIR/config.json.tmp" "$DATA_DIR/config.json"
elif [ -f "$DATA_DIR/config.json" ]; then
  warn "config.json exists and jq is missing — leaving it untouched; set \"hotkey\": \"$HOTKEY\" yourself if you changed it"
else
  if [ "$AI_BACKEND" = "custom" ]; then
    AI_CMD_JSON="$AI_COMMAND"
  else
    AI_CMD_JSON="[]"
  fi
  write_file "$DATA_DIR/config.json" <<EOF
{
  "hotkey": "$HOTKEY",
  "autostart": $AUTOSTART,
  "window": { "width": $WIN_W, "height": $WIN_H },
  "ai": "$AI_BACKEND",
  "aiCommand": $AI_CMD_JSON,
  "aiModel": "$AI_MODEL"
}
EOF
fi

# ── Hyprland integration ─────────────────────────────────────────────
if [ "$HYPR" = 1 ]; then
  LUA_KEY=$(to_lua_key "$HOTKEY")

  if [ -f "$HYPR_DIR/hyprland.lua" ]; then
    # New Lua config (Hyprland 0.55+, Omarchy quattro)
    write_file "$HYPR_DIR/mindpalace.lua" <<EOF
-- MindPalace (generated by install.sh — safe to delete, rerun installer to regenerate)
hl.env("MINDPALACE_DATA", "$DATA_FILE")

-- Floats by default (change the size here); your compositor's own
-- togglefloating key tiles/floats it like any other window.
hl.window_rule({
    name   = "mindpalace",
    match  = { title = "^MindPalace\$" },
    float  = true,
    size   = { $WIN_W, $WIN_H },
    center = true,
})

-- Open/hide: relaunching toggles the running instance (single-instance app)
hl.bind("$LUA_KEY", hl.dsp.exec_cmd("$BIN"))
EOF
    if [ "$AUTOSTART" = true ]; then
      if [ "$DRYRUN" = 1 ]; then note "dry-run: append autostart hook to mindpalace.lua"; else
        cat >> "$HYPR_DIR/mindpalace.lua" <<EOF

hl.on("hyprland.start", function()
    hl.exec_cmd("$BIN")
end)
EOF
      fi
    fi
    # hook it into hyprland.lua once, matching the file's require style
    if ! grep -q 'mindpalace' "$HYPR_DIR/hyprland.lua"; then
      if grep -q 'require("hypr\.' "$HYPR_DIR/hyprland.lua"; then
        REQ='require("hypr.mindpalace")'
      else
        REQ='require("mindpalace")'
      fi
      if [ "$DRYRUN" = 1 ]; then note "dry-run: append $REQ to hyprland.lua"; else
        printf '\n%s\n' "$REQ" >> "$HYPR_DIR/hyprland.lua"
      fi
    fi
  else
    # Classic .conf config — syntax depends on the Hyprland version
    MINOR=$( (hyprctl -j version 2>/dev/null || true) | (jq -r '.tag // "v0.0"' 2>/dev/null || echo v0.0) | sed 's/^v//' | cut -d. -f2 || true)
    case "$MINOR" in (''|*[!0-9]*) MINOR=0 ;; esac
    if [ "$MINOR" = 0 ]; then
      warn "could not detect the Hyprland version — assuming 0.53+ syntax (edit mindpalace.conf if reload complains)"
      MINOR=53
    fi
    CONF_MODS=$(to_conf_mods "$HOTKEY"); CONF_KEY=$(to_conf_key "$HOTKEY")
    if [ "$MINOR" -ge 53 ]; then
      RULES="windowrule = float on, match:title ^MindPalace\$
windowrule = size $WIN_W $WIN_H, match:title ^MindPalace\$
windowrule = center on, match:title ^MindPalace\$
windowrule = opacity 1.0 override, match:title ^MindPalace\$"
    else
      RULES="windowrulev2 = float, title:^(MindPalace)\$
windowrulev2 = size $WIN_W $WIN_H, title:^(MindPalace)\$
windowrulev2 = center, title:^(MindPalace)\$
windowrulev2 = opacity 1.0 override, title:^(MindPalace)\$"
    fi
    write_file "$HYPR_DIR/mindpalace.conf" <<EOF
# MindPalace (generated by install.sh — safe to delete, rerun installer to regenerate)
# Floats by default (change the size here); your compositor's own
# togglefloating key tiles/floats it like any other window. The opacity
# override keeps theme-wide transparency rules from stacking on the app's
# own glass.
env = MINDPALACE_DATA,$DATA_FILE
$RULES

# Open/hide: relaunching toggles the running instance (single-instance app)
bind = $CONF_MODS, $CONF_KEY, exec, $BIN
EOF
    if [ "$AUTOSTART" = true ]; then
      if [ "$DRYRUN" = 1 ]; then note "dry-run: append exec-once to mindpalace.conf"; else
        printf '\nexec-once = %s\n' "$BIN" >> "$HYPR_DIR/mindpalace.conf"
      fi
    fi
    if [ -f "$HYPR_DIR/hyprland.conf" ] && ! grep -q 'mindpalace.conf' "$HYPR_DIR/hyprland.conf"; then
      if [ "$DRYRUN" = 1 ]; then note "dry-run: append source line to hyprland.conf"; else
        printf '\nsource = %s\n' "$HYPR_DIR/mindpalace.conf" >> "$HYPR_DIR/hyprland.conf"
      fi
    fi
  fi

  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ "$DRYRUN" = 0 ]; then
    if ! hyprctl reload; then
      warn "hyprctl reload reported an error — check ~/.config/hypr/mindpalace.* against your Hyprland version"
    fi
  fi
else
  # Non-Hyprland autostart via XDG
  if [ "$AUTOSTART" = true ]; then
    write_file "$HOME/.config/autostart/mindpalace.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MindPalace
Exec=env "MINDPALACE_DATA=$DATA_FILE" "$BIN"
Icon=mindpalace
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  fi
fi

# ── done ─────────────────────────────────────────────────────────────
echo
bold "Installed."
note "binary     $BIN"
note "palace     $DATA_FILE"
note "hotkey     $HOTKEY$( [ "$HYPR" = 1 ] && printf ' (Hyprland bind)' )"
note "window     ${WIN_W}x${WIN_H} floating$( [ "$HYPR" = 1 ] && printf ' — your togglefloating key tiles it' )"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not on your PATH" ;; esac
if [ "$HYPR" = 0 ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  warn "On Wayland, apps can't register global hotkeys — bind a key in your"
  warn "desktop's shortcut settings to run: $BIN  (launching again = toggle)"
fi
note "uninstall any time: $(basename "$0") --uninstall"
exit 0
# Do not edit below — everything after the marker is the embedded archive.
__ARCHIVE__
