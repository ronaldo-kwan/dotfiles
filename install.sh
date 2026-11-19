#!/usr/bin/env bash
# Set up this computer from ~/dotfiles. Safe to run more than once.
#
# Needs (install first, see README):
#   sudo apt install git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
#
# Does NOT use sudo. Steps that need sudo or a sign-in are listed at the end.
# If one step fails, the others still run, and failures are listed at the end.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DOTFILES/setup"
PACKAGES=(bash git starship ghostty btop lazygit terminal-default vscode claude)
FAILED=()

say()  { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
skip() { printf '    skipped: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Run one step in a subshell with "stop on error", and record it if it fails.
run_step() {
  local title="$1"; shift
  say "$title"
  ( set -e; "$@" )
  local rc=$?
  if (( rc != 0 )); then
    printf '    \033[1;31mfailed\033[0m (exit code %s)\n' "$rc"
    FAILED+=("$title")
  fi
}

# 1. Link config files with stow ------------------------------------------------
link_configs() {
  if ! have stow; then
    skip "stow isn't installed (sudo apt install stow), so nothing was linked"
    return 0
  fi
  for pkg in "${PACKAGES[@]}"; do
    # Move aside real files that stow would refuse to replace.
    while IFS= read -r -d '' src; do
      target="$HOME/${src#"$DOTFILES/$pkg/"}"
      if [[ -e "$target" && ! -L "$target" ]]; then
        mv "$target" "$target.orig"
        echo "    kept existing ${target/#$HOME/\~} as ${target/#$HOME/\~}.orig"
      fi
    done < <(find "$DOTFILES/$pkg" -type f -print0)
  done
  # --no-folding links individual files, so apps that write extra files into
  # their config folder (like btop's log) don't write them into this repo.
  stow --dir="$DOTFILES" --target="$HOME" --no-folding --restow "${PACKAGES[@]}"
  echo "    linked: ${PACKAGES[*]}"
}

# 2. JetBrainsMono Nerd Font -----------------------------------------------------
install_font() {
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont" tmp
  if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    echo "    already installed"
    return 0
  fi
  if ! have curl; then
    skip "curl isn't installed (sudo apt install curl), so the font wasn't downloaded"
    return 0
  fi
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/JetBrainsMono.tar.xz" \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  mkdir -p "$tmp/extract" "$font_dir"
  tar -xJf "$tmp/JetBrainsMono.tar.xz" -C "$tmp/extract"
  cp "$tmp"/extract/JetBrainsMonoNerdFont-*.ttf "$font_dir/"
  rm -rf "$tmp"
  fc-cache -f "$font_dir"
  echo "    installed"
}

# 3. VS Code extensions --------------------------------------------------------------
install_vscode_extensions() {
  if ! have code; then
    skip "VS Code isn't installed yet"
    return 0
  fi
  while read -r ext; do
    [[ -z "$ext" ]] && continue
    code --install-extension "$ext" >/dev/null && echo "    $ext"
  done < "$SETUP/vscode-extensions.txt"
}

# 4. Flatpak apps ---------------------------------------------------------------
install_flatpaks() {
  if ! have flatpak; then
    skip "flatpak isn't installed (sudo apt install flatpak)"
    return 0
  fi
  if ! flatpak remotes --columns=name | grep -qx flathub; then
    skip "Flathub isn't set up. Run: sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
    return 0
  fi
  mapfile -t apps < <(grep -v '^\s*$' "$SETUP/flatpaks.txt")
  flatpak install -y --noninteractive flathub "${apps[@]}"
}

# 5. GNOME extensions ----------------------------------------------------------------
# Downloads each extension in setup/gnome-extensions.txt from extensions.gnome.org,
# in the version that matches this computer's GNOME, and marks it as enabled.
# New extensions start working after you log out and back in.
install_gnome_extensions() {
  local missing=()
  for c in gnome-extensions gnome-shell curl python3; do have "$c" || missing+=("$c"); done
  if (( ${#missing[@]} > 0 )); then
    skip "needs ${missing[*]}"
    return 0
  fi
  local shell_version tmp uuid info url
  shell_version="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
  tmp="$(mktemp -d)"
  while read -r uuid; do
    [[ -z "$uuid" || "$uuid" == \#* ]] && continue
    if gnome-extensions info "$uuid" >/dev/null 2>&1; then
      echo "    $uuid: already installed"
    else
      info="$(curl -fsSG https://extensions.gnome.org/extension-info/ \
        --data-urlencode "uuid=$uuid" --data-urlencode "shell_version=$shell_version")"
      url="$(python3 -I -c 'import sys,json; print(json.load(sys.stdin)["download_url"])' <<< "$info")"
      curl -fsSL -o "$tmp/ext.zip" "https://extensions.gnome.org$url"
      gnome-extensions install --force "$tmp/ext.zip"
      echo "    $uuid: installed"
    fi
    # Add it to the enabled list (keeps everything already enabled).
    gsettings set org.gnome.shell enabled-extensions "$(python3 -I -c '
import sys, ast
current = ast.literal_eval(sys.argv[1].removeprefix("@as "))
if sys.argv[2] not in current:
    current.append(sys.argv[2])
print(current)' "$(gsettings get org.gnome.shell enabled-extensions)" "$uuid")"
  done < "$SETUP/gnome-extensions.txt"
  gsettings set org.gnome.shell disable-user-extensions false
  rm -rf "$tmp"
  echo "    enabled (they start after you log out and back in)"
}

# 6. GNOME settings ----------------------------------------------------------------
restore_gnome_settings() {
  if ! have dconf || ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  # Theme, icons, fonts, accent colour, dark mode, window buttons, workspaces, and
  # exactly which extensions are on or off (this also switches off Ubuntu's
  # built-in ones you turned off, like Ubuntu Dock and desktop icons).
  dconf load /org/gnome/ < "$SETUP/gnome-desktop.dconf"
  dconf load /org/gnome/settings-daemon/plugins/media-keys/ < "$SETUP/gnome-shortcuts.dconf"
  dconf load /org/gnome/shell/extensions/ < "$SETUP/gnome-extension-settings.dconf"
  gsettings set org.gnome.shell favorite-apps "$(cat "$SETUP/dock-favorites.txt")"
  # Window and screenshot shortcuts, power, sound, Files, file dialogs, search order,
  # backups and app settings.
  if [[ -f "$SETUP/desktop-settings.dconf" ]]; then
    dconf load / < "$SETUP/desktop-settings.dconf"
    # Ptyxis keeps its colours in a profile with a different ID on each computer.
    local palette uuid
    palette="$(sed -n 's/^# ptyxis-palette=//p' "$SETUP/desktop-settings.dconf")"
    uuid="$(dconf read /org/gnome/Ptyxis/default-profile-uuid | tr -d "'")"
    if [[ -n "$palette" && -n "$uuid" ]]; then
      dconf write "/org/gnome/Ptyxis/Profiles/$uuid/palette" "$palette"
    fi
  fi
  echo "    restored"
}

# 7. Wallpaper -----------------------------------------------------------------------
set_wallpaper() {
  if ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  local wall_dir="$HOME/Pictures/Wallpapers/current" wall uri
  wall="$(ls "$SETUP"/wallpaper/*.jpg | head -1)"
  mkdir -p "$wall_dir"
  cp --update=none "$wall" "$wall_dir/"
  uri="file://$wall_dir/$(basename "$wall")"
  gsettings set org.gnome.desktop.background picture-uri "$uri"
  gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
  gsettings set org.gnome.desktop.screensaver picture-uri "$uri"   # lock screen
  echo "    set"
}

# 8. App settings -------------------------------------------------------------------
# Apps that start at login, default apps, qBittorrent (saved by `dotsave` in setup/apps/).
# Existing files that differ are kept as <name>.orig.
put_file() { # put_file <saved file> <destination>: copy, turning @HOME@ into this home folder
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && cmp -s <(sed "s|@HOME@|$HOME|g" "$src") "$dst"; then return 0; fi
  [[ -f "$dst" ]] && mv "$dst" "$dst.orig"
  sed "s|@HOME@|$HOME|g" "$src" > "$dst"
  echo "    ${dst/#$HOME/\~}"
}

restore_app_settings() {
  local apps="$SETUP/apps" f
  [[ -d "$apps" ]] || { skip "no saved app settings"; return 0; }
  for f in "$apps"/autostart/*.desktop; do
    [[ -f "$f" ]] && put_file "$f" "$HOME/.config/autostart/$(basename "$f")"
  done
  [[ -f "$apps/mimeapps.list" ]] && put_file "$apps/mimeapps.list" "$HOME/.config/mimeapps.list"
  if [[ -f "$apps/qBittorrent/qBittorrent.conf" ]]; then
    if pgrep -x qbittorrent >/dev/null; then
      skip "qBittorrent is open; close it and run install.sh again (it saves its settings on exit)"
    else
      put_file "$apps/qBittorrent/qBittorrent.conf" "$HOME/.config/qBittorrent/qBittorrent.conf"
      for f in "$apps"/qBittorrent/themes/*; do
        [[ -f "$f" ]] && put_file "$f" "$HOME/.config/qBittorrent/themes/$(basename "$f")"
      done
    fi
  fi
  echo "    done (apps that start at login apply from your next login)"
}

# 9. Obsidian -----------------------------------------------------------------------
# Notes come from your private GitHub repo "obsidian-vault" (not from this repo);
# vault settings (theme, plugins) come from setup/apps/obsidian/ if the vault has none.
OBSIDIAN_VAULT="$HOME/Documents/Obsidian Vault"
restore_obsidian() {
  if [[ ! -d "$OBSIDIAN_VAULT" ]]; then
    if have gh && gh repo view obsidian-vault >/dev/null 2>&1; then
      gh repo clone obsidian-vault "$OBSIDIAN_VAULT" -- --quiet
      echo "    notes cloned to ${OBSIDIAN_VAULT/#$HOME/\~}"
    else
      skip "no obsidian-vault repo found on GitHub (or gh isn't signed in), so no notes cloned"
    fi
  else
    echo "    vault already there: ${OBSIDIAN_VAULT/#$HOME/\~}"
  fi
  if [[ -d "$SETUP/apps/obsidian" && ! -f "$OBSIDIAN_VAULT/.obsidian/appearance.json" ]]; then
    mkdir -p "$OBSIDIAN_VAULT/.obsidian"
    cp -r --update=none "$SETUP/apps/obsidian/." "$OBSIDIAN_VAULT/.obsidian/"
    echo "    Obsidian settings and Catppuccin theme added to the vault"
  fi
  echo "    in Obsidian, choose \"Open folder as vault\" and pick that folder (first time only)"
}

# Main ---------------------------------------------------------------------------------
echo "This will set up your configs from $DOTFILES:"
echo "  link config files, install the Nerd Font, VS Code extensions, Flatpak apps and GNOME extensions,"
echo "  and restore your desktop look (theme, icons, dark mode, accent colour, window buttons,"
echo "  workspaces, fonts), keyboard shortcuts, power, Files and dialog settings, backups settings,"
echo "  extension settings, dock, wallpaper, lock screen, apps that start at login,"
echo "  default apps and qBittorrent settings."
echo "Existing files that would be replaced are kept as <name>.orig."
echo "Keyboard shortcuts replace any custom shortcuts already on this computer."
read -rp "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Nothing changed."; exit 0; }

run_step "Linking config files"                          link_configs
run_step "JetBrainsMono Nerd Font"                       install_font
run_step "VS Code extensions"                            install_vscode_extensions
run_step "Flatpak apps"                                  install_flatpaks
run_step "GNOME extensions"                              install_gnome_extensions
run_step "Desktop look, shortcuts and settings, extension settings and dock" restore_gnome_settings
run_step "Wallpaper and lock screen"                     set_wallpaper
run_step "App settings (login apps, default apps, qBittorrent)" restore_app_settings
run_step "Obsidian vault and settings"                   restore_obsidian

if (( ${#FAILED[@]} > 0 )); then
  say "Finished with problems. These steps failed (see messages above):"
  printf '  - %s\n' "${FAILED[@]}"
else
  say "Done."
fi
cat <<'EOF'

Still to do yourself:
  - Optional: install Chrome, VS Code, Claude Desktop, Proton VPN and OBS with
    ~/dotfiles/install-apps.sh (uses sudo, asks before each app).
    Then run install.sh again to add VS Code's extensions.
  - Optional: weekly updates script in system/ (needs sudo, see README).
  - Log out and back in (this also starts the GNOME extensions), then open a new terminal.
EOF

(( ${#FAILED[@]} == 0 ))
