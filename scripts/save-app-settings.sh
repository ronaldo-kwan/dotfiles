#!/usr/bin/env bash
# Copy app settings worth keeping into setup/apps/ (used by scripts/snapshot.sh):
#   - apps that start at login        (~/.config/autostart/)
#   - default apps (browser, video...) (~/.config/mimeapps.list)
#   - display settings (scale, resolution) (~/.config/monitors.xml, without serial numbers)
#   - qBittorrent settings and theme   (~/.config/qBittorrent/)
#   - Obsidian vault settings and theme (<vault>/.obsidian/, not the notes or plugin files)
#   - Brave Origin's own settings      (an allowlist from its Preferences and Local State: scripts/brave-settings.py)
#
# Paths inside your home folder are stored as @HOME@ so they work for any username.
# install.sh puts them back (restore_app_settings).

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_DIR="${1:-$DOTFILES/setup}"   # optional argument: a different setup folder
OUT="$SETUP_DIR/apps"
# Only the parts this computer chose on the website (see snapshot.sh); everything otherwise.
# shellcheck source=bin/lib.sh
source "$DOTFILES/bin/lib.sh"
CFG="$HOME/.config"

mkdir -p "$OUT"

# 1. Apps that start at login: one small .desktop file per app, only for the Flatpak apps
#    in flatpaks.txt. install.sh puts back only those (each file is named after its app's
#    Flatpak ID), so others (an app you since removed, one from elsewhere) aren't saved.
if chosen desktop; then
  rm -rf "$OUT/autostart"
  for f in "$CFG"/autostart/*.desktop; do
    { [[ -f "$f" ]] && grep -qxF "$(basename "$f" .desktop)" "$SETUP_DIR/flatpaks.txt" 2>/dev/null; } || continue
    mkdir -p "$OUT/autostart"
    cp "$f" "$OUT/autostart/"
  done
fi

# 1b. Brave Origin: only the settings scripts/brave-settings.py names (appearance, tabs, new
#     tab page, languages, downloads, HTTPS mode, fonts, the defaults for every site, content
#     filtering), not the rest of its Preferences or Local State: account, sync, open tabs,
#     the per-site lists and the passwords' encryption key stay here.
if chosen app:brave-origin && [[ -f "$BRAVE_PREFS" ]]; then
  # (The saved file goes in too: its search engine stays if this profile hasn't picked one.)
  python3 -I "$DOTFILES/scripts/brave-settings.py" save "$BRAVE_PREFS" "$OUT/brave-settings.json" > "$OUT/brave-settings.json.new" \
    && mv "$OUT/brave-settings.json.new" "$OUT/brave-settings.json"
  rm -f "$OUT/brave-settings.json.new"
fi

# 2. Default apps
if chosen desktop && [[ -f "$CFG/mimeapps.list" ]]; then
  sed "s|$HOME|@HOME@|g" "$CFG/mimeapps.list" > "$OUT/mimeapps.list"
fi

# 2b. Display settings (scale, resolution, refresh rate): GNOME's monitors.xml. It names
#     each screen by maker, model and serial number; the serial is left out (this repo is
#     public), and install.sh fills it in again from a connected screen of the same maker
#     and model, so they're only ever used with this screen.
if chosen desktop && [[ -f "$CFG/monitors.xml" ]]; then
  sed -E 's|<serial>[^<]*</serial>|<serial>@SERIAL@</serial>|g' "$CFG/monitors.xml" > "$OUT/monitors.xml"
fi

# 3. qBittorrent: settings without cookies, window sizes or layout; plus custom themes
if chosen pkg:qbittorrent; then rm -rf "$OUT/qBittorrent"; fi
if chosen pkg:qbittorrent && [[ -f "$CFG/qBittorrent/qBittorrent.conf" ]]; then
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

# 4. Obsidian: settings of the open vault (theme, appearance, which plugins are on), not
#    the notes. Left out:
#    - workspace*.json: only remembers open tabs and window layout.
#    - plugins/: community plugins' program files (often megabytes) and their data.json,
#      where plugins keep their own settings and sometimes API keys or sign-ins. This
#      repo is public. community-plugins.json still lists them, so a new computer knows
#      which to install from Settings → Community plugins.
#    No vault on this computer (Obsidian never opened, or no notes repo yet): the saved
#    settings stay as they are, so a new computer doesn't wipe them with dot save.
OBS_CFG="$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
if chosen notes && [[ -f "$OBS_CFG" ]]; then
  vault="$(python3 -I -c '
import json, sys
vaults = json.load(open(sys.argv[1])).get("vaults", {}).values()
open_ = [v["path"] for v in vaults if v.get("open")] or [v["path"] for v in vaults]
print(open_[0] if open_ else "")' "$OBS_CFG")"
  if [[ -n "$vault" && -d "$vault/.obsidian" ]]; then
    rm -rf "$OUT/obsidian"
    mkdir -p "$OUT/obsidian"
    (cd "$vault/.obsidian" && find . -type f ! -name 'workspace*.json' ! -path './plugins/*' -print0) \
      | while IFS= read -r -d '' f; do
          mkdir -p "$OUT/obsidian/$(dirname "$f")"
          cp "$vault/.obsidian/$f" "$OUT/obsidian/$f"
        done
  fi
fi
