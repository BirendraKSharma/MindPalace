#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  MindPalace — one-command install for Linux
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/BirendraKSharma/MindPalace/main/install.sh | bash
#
#  Downloads the source, installs build deps + Rust + Node if missing,
#  builds from source, and installs the app. Your palace data is never
#  touched. Re-run anytime to upgrade.
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Downloading MindPalace source…"
curl -fsSL "https://github.com/BirendraKSharma/MindPalace/archive/refs/heads/main.tar.gz" \
  | tar xz -C "$TMPDIR"

SRC_DIR=$(find "$TMPDIR" -maxdepth 1 -type d -name 'MindPalace-*' | head -1)
if [ -z "$SRC_DIR" ]; then
  echo "ERROR: failed to extract source archive." >&2
  exit 1
fi

echo "==> Running installer from $SRC_DIR…"
bash "$SRC_DIR/installers/install.sh" --defaults

echo
echo "==> Done. Launch with Ctrl+Shift+Space or run: mindpalace"