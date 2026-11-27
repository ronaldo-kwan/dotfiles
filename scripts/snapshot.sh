#!/usr/bin/env bash
# Write the snapshot files (what's installed and how the desktop is set up) into a
# setup folder. Used by `dot save` and `dot push` (into ~/code/github/dotfiles/setup) and by check.sh (into a
# temporary copy, to see whether the saved snapshots are out of date).
#   scripts/snapshot.sh [setup-folder]     default: ~/code/github/dotfiles/setup
# setup/apt-packages.txt is written by hand, so it's not touched here.
# With website choices (~/.config/dotfiles/choices), only the chosen parts are refreshed:
# a computer with just the terminal mustn't overwrite the saved desktop settings or apps.

set -uo pipefail

# shellcheck source=../bin/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib.sh"   # DOTFILES, have, chosen
d="${1:-$DOTFILES/setup}"
[[ -d "$d" ]] || { echo "snapshot.sh: $d not found" >&2; exit 1; }
rc=0   # 1 if a snapshot couldn't be written (dot then says so)

have code && chosen app:code && code --list-extensions > "$d/vscode-extensions.txt"
# Flatpaks: what's installed, plus the saved ones this computer didn't choose.
if have flatpak; then
  {
    flatpak list --app --columns=application
    grep -v '^\s*$' "$d/flatpaks.txt" 2>/dev/null | while read -r a; do chosen "flatpak:$a" || echo "$a"; done
  } | sort -u > "$d/flatpaks.txt.new" && mv "$d/flatpaks.txt.new" "$d/flatpaks.txt"
  rm -f "$d/flatpaks.txt.new"   # left over if flatpak failed
fi

if have dconf && chosen desktop; then
  {
    echo "# Desktop look: theme, icons, fonts, accent, dark mode, window buttons, workspaces,"
    echo "# and which GNOME extensions are switched on or off (including Ubuntu's built-in ones)"
    echo "# Load with: dconf load /org/gnome/ < gnome-desktop.dconf"
    dconf dump /org/gnome/desktop/interface/ | sed 's|^\[/\]$|[desktop/interface]|'
    echo
    dconf dump /org/gnome/desktop/wm/preferences/ | sed 's|^\[/\]$|[desktop/wm/preferences]|'
    echo
    printf '[mutter]\ndynamic-workspaces=%s\n' "$(dconf read /org/gnome/mutter/dynamic-workspaces)"
    echo
    printf '[shell]\nenabled-extensions=%s\ndisabled-extensions=%s\n' \
      "$(gsettings get org.gnome.shell enabled-extensions)" \
      "$(gsettings get org.gnome.shell disabled-extensions)"
  } > "$d/gnome-desktop.dconf"
  dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$d/gnome-shortcuts.dconf"
  # Leave out extensions' internal records, which shouldn't be restored elsewhere
  # (indicator-position-max: Caffeine's count of top-bar icons, which changes by itself),
  # then any section left empty.
  dconf dump /org/gnome/shell/extensions/ \
    | grep -vE '^(last-version-installed|overridden-settings|check-x11wayland|cli-toggle|indicator-position-max)=' \
    | sed '/^\[[^]]*\]$/{N;/\n$/d}' > "$d/gnome-extension-settings.dconf"
  # Shortcuts, power, sound, Files, file dialogs, search order, backups, app settings.
  # Written to a new file first: if the script stops partway, the saved one stays as it
  # was (a half-written one would lose every setting after the point it stopped).
  if bash "$DOTFILES/scripts/dump-desktop-settings.sh" > "$d/desktop-settings.dconf.new"; then
    mv "$d/desktop-settings.dconf.new" "$d/desktop-settings.dconf"
  else
    rm -f "$d/desktop-settings.dconf.new"
    echo "snapshot.sh: couldn't read the desktop settings; setup/desktop-settings.dconf left as it was" >&2
    rc=1
  fi
fi

# Apps that start at login, default apps, qBittorrent, Obsidian settings
bash "$DOTFILES/scripts/save-app-settings.sh" "$d"

have gsettings && chosen desktop && gsettings get org.gnome.shell favorite-apps > "$d/dock-favorites.txt"
exit "$rc"
