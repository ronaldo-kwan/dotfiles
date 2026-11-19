#!/usr/bin/env bash
# Write the snapshot files (what's installed and how the desktop is set up) into a
# setup folder. Used by `dotsave` (into ~/dotfiles/setup) and by check.sh (into a
# temporary copy, to see whether the saved snapshots are out of date).
#   scripts/snapshot.sh [setup-folder]     default: ~/dotfiles/setup
# setup/apt-packages.txt is written by hand, so it's not touched here.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
d="${1:-$DOTFILES/setup}"
[[ -d "$d" ]] || { echo "snapshot.sh: $d not found" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have code    && code --list-extensions > "$d/vscode-extensions.txt"
have flatpak && flatpak list --app --columns=application > "$d/flatpaks.txt"

if have dconf; then
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
  dconf dump /org/gnome/shell/extensions/ \
    | grep -vE '^(last-version-installed|overridden-settings|check-x11wayland|cli-toggle)=' \
    | sed '/^\[ding\]$/{N;/\n$/d}' > "$d/gnome-extension-settings.dconf"
  # Shortcuts, power, sound, Files, file dialogs, search order, backups, app settings
  bash "$DOTFILES/scripts/dump-desktop-settings.sh" > "$d/desktop-settings.dconf"
fi

# Apps that start at login, default apps, qBittorrent, Obsidian settings
bash "$DOTFILES/scripts/save-app-settings.sh" "$d"

have gsettings && gsettings get org.gnome.shell favorite-apps > "$d/dock-favorites.txt"
exit 0
