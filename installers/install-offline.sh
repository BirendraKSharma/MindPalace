#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  MindPalace OFFLINE installer for Linux
#
#  Self-extracting and fully offline: a prebuilt AppImage (WebKit and all
#  libraries bundled) is appended after the __ARCHIVE__ marker, so this
#  needs no internet, no Rust, no Node and no distro packages. Run it,
#  answer the prompts (Enter accepts the default), done in seconds.
#
#  Generate this file with scripts/package-linux-offline.sh (on Linux).
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
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
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

# ── hotkey conversions (same style as config.json: Ctrl+Shift+Space) ──
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
APP_DIR_DEFAULT="$HOME/.local/lib/mindpalace"

# ── uninstall ────────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  bold "Uninstalling MindPalace (palace data stays where it is)"
  ask BIN_DIR "Where was the launcher installed" "$HOME/.local/bin"
  ask APP_DIR "Where were the app files installed" "$APP_DIR_DEFAULT"
  run rm -f "$BIN_DIR/mindpalace" "$BIN_DIR/mindpalace-toggle-tile"
  [ -d "$APP_DIR" ] && run rm -rf "$APP_DIR"
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

bold "MindPalace offline installer"

# ── extract the embedded payload (AppImage + helpers) ────────────────
ARCHIVE_LINE=$(awk '/^__ARCHIVE__$/{print NR+1; exit}' "$0" || true)
# (test via $(...) so a SIGPIPE from head can't fail the pipeline under pipefail)
if [ -z "$ARCHIVE_LINE" ] || [ -z "$(tail -n +"$ARCHIVE_LINE" "$0" | head -c 1)" ]; then
  echo "This copy has no embedded app — generate it with scripts/package-linux-offline.sh." >&2
  exit 1
fi
PAYLOAD=$(mktemp -d /tmp/mindpalace-pkg.XXXXXX)
trap 'rm -rf "$PAYLOAD"' EXIT
note "extracting bundled app to $PAYLOAD"
tail -n +"$ARCHIVE_LINE" "$0" | base64 -d | tar xz -C "$PAYLOAD"
if [ ! -f "$PAYLOAD/MindPalace.AppImage" ]; then
  echo "Payload is missing MindPalace.AppImage — the package is corrupt." >&2
  exit 1
fi

# ── questions ────────────────────────────────────────────────────────
ask BIN_DIR   "Install the launcher where"             "$HOME/.local/bin"
ask APP_DIR   "Install the app files where"            "$APP_DIR_DEFAULT"
ask DATA_FILE "Where should your palace live (palace.json)" "$HOME/.local/share/MindPalace/palace.json"
ask HOTKEY    "Global open/hide hotkey"                "Ctrl+Shift+Space"
ask WIN_SIZE  "Floating window size (WIDTHxHEIGHT)"    "650x500"
confirm "Start MindPalace automatically on login" y && AUTOSTART=true || AUTOSTART=false

WIN_W=${WIN_SIZE%%[xX×]*}; WIN_H=${WIN_SIZE##*[xX×]}
case "$WIN_W$WIN_H" in (*[!0-9]*) warn "could not parse '$WIN_SIZE' — using 650x500"; WIN_W=650; WIN_H=500 ;; esac

HYPR=0
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ -d "$HYPR_DIR" ]; then
  if confirm "Hyprland detected — write window rules + keybinds for it" y; then
    HYPR=1
  fi
fi

DATA_DIR=$(dirname "$DATA_FILE")
BIN="$BIN_DIR/mindpalace"

# ── install the app (extract the AppImage — no FUSE needed, instant start)
chmod +x "$PAYLOAD/MindPalace.AppImage"
if [ "$DRYRUN" = 1 ]; then
  note "dry-run: would extract MindPalace.AppImage into $APP_DIR"
else
  ( cd "$PAYLOAD" && ./MindPalace.AppImage --appimage-extract >/dev/null 2>&1 ) || true
  if [ -d "$PAYLOAD/squashfs-root" ]; then
    rm -rf "$APP_DIR"
    mkdir -p "$(dirname "$APP_DIR")"
    mv "$PAYLOAD/squashfs-root" "$APP_DIR"
  else
    # odd kernel/mount setups: keep the AppImage itself (needs FUSE to run)
    warn "could not extract the AppImage — installing it as-is (needs FUSE/fuse2 to run)"
    mkdir -p "$APP_DIR"
    cp "$PAYLOAD/MindPalace.AppImage" "$APP_DIR/MindPalace.AppImage"
  fi
fi

# launcher: a tiny wrapper so terminal launches also find the palace
if [ "$DRYRUN" = 0 ]; then
  if [ -x "$APP_DIR/AppRun" ]; then TARGET="$APP_DIR/AppRun"; else TARGET="$APP_DIR/MindPalace.AppImage"; fi
else
  TARGET="$APP_DIR/AppRun"
fi
run mkdir -p "$BIN_DIR" "$DATA_DIR"
write_file "$BIN" <<EOF
#!/bin/sh
# MindPalace launcher (generated by install-offline.sh)
export MINDPALACE_DATA="\${MINDPALACE_DATA:-$DATA_FILE}"
exec "$TARGET" "\$@"
EOF
run chmod 755 "$BIN"
# clean up the float/tile helper older versions installed (Hyprland's own
# togglefloating key now does that job — nothing is rebound anymore)
[ -e "$BIN_DIR/mindpalace-toggle-tile" ] && run rm -f "$BIN_DIR/mindpalace-toggle-tile"

ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
run mkdir -p "$ICON_DIR"
run cp "$PAYLOAD/icon.png" "$ICON_DIR/mindpalace.png"

write_file "$HOME/.local/share/applications/mindpalace.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MindPalace
Comment=Always-on-top scratchpad (launch again to toggle the window)
Exec=$BIN
Icon=mindpalace
Terminal=false
Categories=Utility;
EOF

# ── app settings: MERGE into config.json, never wipe the user's keys ──
if [ "$DRYRUN" = 1 ]; then
  note "dry-run: merge hotkey/autostart/window into $DATA_DIR/config.json"
elif [ -f "$DATA_DIR/config.json" ] && command -v jq >/dev/null 2>&1; then
  jq --arg hk "$HOTKEY" --argjson as "$AUTOSTART" --argjson w "$WIN_W" --argjson h "$WIN_H" \
    '. + {hotkey: $hk, autostart: $as, window: {width: $w, height: $h}}' \
    "$DATA_DIR/config.json" > "$DATA_DIR/config.json.tmp" && mv "$DATA_DIR/config.json.tmp" "$DATA_DIR/config.json"
elif [ -f "$DATA_DIR/config.json" ]; then
  warn "config.json exists and jq is missing — leaving it untouched; set \"hotkey\": \"$HOTKEY\" yourself if you changed it"
else
  write_file "$DATA_DIR/config.json" <<EOF
{
  "hotkey": "$HOTKEY",
  "autostart": $AUTOSTART,
  "window": { "width": $WIN_W, "height": $WIN_H }
}
EOF
fi

# ── Hyprland integration ─────────────────────────────────────────────
if [ "$HYPR" = 1 ]; then
  LUA_KEY=$(to_lua_key "$HOTKEY")

  if [ -f "$HYPR_DIR/hyprland.lua" ]; then
    # New Lua config (Hyprland 0.55+, Omarchy quattro)
    write_file "$HYPR_DIR/mindpalace.lua" <<EOF
-- MindPalace (generated by install-offline.sh — safe to delete, rerun installer to regenerate)
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
# MindPalace (generated by install-offline.sh — safe to delete, rerun installer to regenerate)
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
Exec=$BIN
Icon=mindpalace
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  fi
fi

# ── done ─────────────────────────────────────────────────────────────
echo
bold "Installed (fully offline)."
note "app        $APP_DIR"
note "launcher   $BIN"
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
# Do not edit below — everything after the marker is the embedded app.
__ARCHIVE__
