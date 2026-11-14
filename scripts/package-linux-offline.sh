#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  Builds the OFFLINE Linux package:  dist/MindPalace-linux-offline.zip
#  (README + a self-extracting install.sh with a prebuilt AppImage inside)
#
#  Run this ON A LINUX MACHINE (e.g. your Omarchy box) from the repo or
#  an extracted MindPalace-source.zip. The BUILD machine needs internet
#  and the normal build deps (see BUILDING.md); the package it produces
#  installs fully offline on other machines.
#
#  Usage:  ./scripts/package-linux-offline.sh [--skip-build]
#    --skip-build   reuse an existing AppImage instead of rebuilding
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

command -v node >/dev/null 2>&1 || { echo "node not found — see BUILDING.md"; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "cargo not found — see BUILDING.md (rustup.rs)"; exit 1; }

# ── 1. Build the AppImage (bundles WebKitGTK → runs anywhere) ────────
if [ "$SKIP_BUILD" = 0 ]; then
  echo ">> Building the AppImage (first Rust build takes a while)..."
  ( cd "$REPO/app" && npm install && npm run tauri build -- --bundles appimage )
fi
APPIMAGE=$(ls -t "$REPO"/app/src-tauri/target/release/bundle/appimage/*.AppImage 2>/dev/null | head -n 1 || true)
if [ -z "$APPIMAGE" ]; then
  echo "No AppImage found under app/src-tauri/target/release/bundle/appimage/ — build failed?" >&2
  exit 1
fi
echo ">> AppImage: $APPIMAGE ($(du -h "$APPIMAGE" | cut -f1))"

# ── 2. Payload tarball: AppImage + helpers ───────────────────────────
STAGE=$(mktemp -d /tmp/mindpalace-offline.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
cp "$APPIMAGE" "$STAGE/MindPalace.AppImage"
cp "$REPO/app/src-tauri/icons/128x128.png" "$STAGE/icon.png"
TGZ="$STAGE/payload.tgz"
tar -czf "$TGZ" -C "$STAGE" MindPalace.AppImage icon.png

# ── 3. Self-extracting installer ─────────────────────────────────────
OUT="$REPO/dist/linux-offline"
mkdir -p "$OUT"
TEMPLATE="$REPO/installers/install-offline.sh"
# template must end with the __ARCHIVE__ marker line
tail -n 1 "$TEMPLATE" | grep -q '^__ARCHIVE__$' || { echo "install-offline.sh must end with __ARCHIVE__"; exit 1; }
cp "$TEMPLATE" "$OUT/install.sh"
base64 "$TGZ" >> "$OUT/install.sh"
chmod +x "$OUT/install.sh"
cp "$REPO/installers/README-linux-offline.md" "$OUT/README.md"

# ── 4. Shipping zip ──────────────────────────────────────────────────
ZIP="$REPO/dist/MindPalace-linux-offline.zip"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
  ( cd "$REPO/dist" && rm -rf MindPalace-linux-offline && cp -r linux-offline MindPalace-linux-offline \
    && zip -qr MindPalace-linux-offline.zip MindPalace-linux-offline && rm -rf MindPalace-linux-offline )
elif command -v python3 >/dev/null 2>&1; then
  ( cd "$REPO/dist" && rm -rf MindPalace-linux-offline && cp -r linux-offline MindPalace-linux-offline \
    && python3 -c "import shutil; shutil.make_archive('MindPalace-linux-offline','zip','.','MindPalace-linux-offline')" \
    && rm -rf MindPalace-linux-offline )
else
  echo "!! neither zip nor python3 found — ship the dist/linux-offline/ folder as-is"
fi

echo
echo "Done:"
ls -lh "$OUT/install.sh" "$ZIP" 2>/dev/null || ls -lh "$OUT/install.sh"
echo "Install on any Linux machine (no internet needed):  ./install.sh"
