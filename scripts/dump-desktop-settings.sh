#!/usr/bin/env bash
# Print a snapshot of desktop settings that aren't in gnome-desktop.dconf:
# window and screenshot shortcuts, power, sound, Files, file dialogs,
# search order, backups, and a few app settings.
#
# Used by scripts/snapshot.sh to write setup/desktop-settings.dconf.
# Restore with: dconf load / < setup/desktop-settings.dconf
#
# Things GNOME remembers by itself (window sizes, last folders, timestamps) are
# left out, because they shouldn't be copied to another computer.

set -euo pipefail

# Print one dconf folder with full section names, leaving out the given keys.
dump() { # dump /path/ 'key1|key2|...'
  local path="$1" skip="${2:-}" rel
  rel="${path#/}"; rel="${rel%/}"
  dconf dump "$path" \
    | { if [[ -n "$skip" ]]; then grep -vE "^(${skip})="; else cat; fi; } \
    | awk -v rel="$rel" '
        /^\[.*\]$/ { s = substr($0, 2, length($0) - 2); print "[" (s == "/" ? rel : rel "/" s) "]"; next }
        { print }'
  echo
}

# Print only the listed keys of one dconf folder (skipping ones that aren't set).
keys() { # keys /path/ key1 key2 ...
  local path="$1" rel out="" k v; shift
  rel="${path#/}"; rel="${rel%/}"
  for k in "$@"; do
    v="$(dconf read "$path$k")"
    [[ -n "$v" ]] && out+="$k=$v"$'\n'
  done
  [[ -n "$out" ]] && printf '[%s]\n%s\n' "$rel" "$out"
  return 0
}

echo "# More desktop settings: window and screenshot shortcuts, power, sound, Files,"
echo "# file dialogs, search order, backups and app settings."
echo "# Load with: dconf load / < desktop-settings.dconf"
echo

# Window shortcuts (Super+W closes, Super+1-4 switches workspace, ...).
# maximize/unmaximize are managed by the Tiling Assistant extension, so they're left out.
dump /org/gnome/desktop/wm/keybindings/ 'maximize|unmaximize'
# Shell shortcuts (screenshot, notification list, freeing Super+1-4)
dump /org/gnome/shell/keybindings/
keys /org/gnome/shell/ last-selected-power-profile remember-mount-password

# Power (for example: never sleep when plugged in) and sound theme
dump /org/gnome/settings-daemon/plugins/power/
dump /org/gnome/desktop/sound/

# Files app view (list view and its columns), not its window size
dump /org/gnome/nautilus/preferences/
dump /org/gnome/nautilus/list-view/

# Open/save dialogs (hidden files, columns, sorting), not their window size or position
dump /org/gtk/settings/file-chooser/ 'window-size|window-position|sidebar-width|last-folder-uri'
dump /org/gtk/gtk4/settings/file-chooser/ 'window-size|window-position|sidebar-width|last-folder-uri'

# Search order in Activities
dump /org/gnome/desktop/search-providers/

# Backups (Deja Dup): where and how often. Your Google sign-in is never stored here;
# connect it once in the Backups app.
dump /org/gnome/deja-dup/ 'periodic-timestamp|prompt-check|nag-check|window-height|window-width|full-backup-[a-z-]*|last-[a-z-]*'

# Apps
keys /org/gnome/TextEditor/ style-scheme
keys /org/gnome/Ptyxis/ use-system-font font-name
keys /com/ubuntu/update-notifier/ show-livepatch-status-icon

# Ptyxis keeps its colours in a per-install profile, so install.sh applies this
# to whatever profile the new computer has.
uuid="$(dconf read /org/gnome/Ptyxis/default-profile-uuid | tr -d "'")"
if [[ -n "$uuid" ]]; then
  palette="$(dconf read "/org/gnome/Ptyxis/Profiles/$uuid/palette")"
  [[ -n "$palette" ]] && echo "# ptyxis-palette=$palette"
fi
exit 0
