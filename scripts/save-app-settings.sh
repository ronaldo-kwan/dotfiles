#!/usr/bin/env bash
# Copy app settings worth keeping into setup/apps/ (used by `dotsave`):
#   - apps that start at login        (~/.config/autostart/)
#   - default apps (browser, video...) (~/.config/mimeapps.list)
#   - qBittorrent settings and theme   (~/.config/qBittorrent/)
#   - Obsidian vault settings and theme (<vault>/.obsidian/, not the notes)
#
# Paths inside your home folder are stored as @HOME@ so they work for any username.
# install.sh puts them back (restore_app_settings).

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$DOTFILES/setup/apps"
CFG="$HOME/.config"

mkdir -p "$OUT"

# 1. Apps that start at login: one small .desktop file per app
rm -rf "$OUT/autostart"
if compgen -G "$CFG/autostart/*.desktop" >/dev/null; then
  mkdir -p "$OUT/autostart"
  cp "$CFG"/autostart/*.desktop "$OUT/autostart/"
fi

# 2. Default apps
if [[ -f "$CFG/mimeapps.list" ]]; then
  sed "s|$HOME|@HOME@|g" "$CFG/mimeapps.list" > "$OUT/mimeapps.list"
fi

# 3. qBittorrent: settings without cookies, window sizes or layout; plus custom themes
rm -rf "$OUT/qBittorrent"
if [[ -f "$CFG/qBittorrent/qBittorrent.conf" ]]; then
  mkdir -p "$OUT/qBittorrent"
  python3 -I - "$CFG/qBittorrent/qBittorrent.conf" "$HOME" > "$OUT/qBittorrent/qBittorrent.conf" <<'PY'
import re, sys
conf, home = sys.argv[1], sys.argv[2]
drop_sections = {"Network", "MainWindow", "OptionsDialog", "TorrentProperties"}
drop_key = re.compile(r"(^Qt6\\|Size$|geometry|HeaderState|(?i:pass|cookie|token|secret|auth))")
section, out = None, []
for line in open(conf, encoding="utf-8"):
    line = line.rstrip("\n")
    m = re.match(r"^\[(.+)\]$", line)
    if m:
        section = m.group(1)
        if section not in drop_sections:
            out.append(line)
        continue
    if section in drop_sections or not line.strip():
        if not line.strip() and out and out[-1] != "":
            out.append("")
        continue
    key = line.split("=", 1)[0]
    if drop_key.search(key):
        continue
    out.append(line.replace(home, "@HOME@"))
print("\n".join(out).strip() + "\n", end="")
PY
  if [[ -d "$CFG/qBittorrent/themes" ]]; then
    cp -r "$CFG/qBittorrent/themes" "$OUT/qBittorrent/"
  fi
fi

# 4. Obsidian: settings of the open vault (theme, plugins, appearance), not the notes.
#    workspace*.json only remembers open tabs and window layout, so it's left out.
OBS_CFG="$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
rm -rf "$OUT/obsidian"
if [[ -f "$OBS_CFG" ]]; then
  vault="$(python3 -I -c '
import json, sys
vaults = json.load(open(sys.argv[1])).get("vaults", {}).values()
open_ = [v["path"] for v in vaults if v.get("open")] or [v["path"] for v in vaults]
print(open_[0] if open_ else "")' "$OBS_CFG")"
  if [[ -n "$vault" && -d "$vault/.obsidian" ]]; then
    mkdir -p "$OUT/obsidian"
    (cd "$vault/.obsidian" && find . -type f ! -name 'workspace*.json' -print0) \
      | while IFS= read -r -d '' f; do
          mkdir -p "$OUT/obsidian/$(dirname "$f")"
          cp "$vault/.obsidian/$f" "$OUT/obsidian/$f"
        done
  fi
fi
