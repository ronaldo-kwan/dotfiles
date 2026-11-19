#!/usr/bin/env bash
# Set up this computer from ~/dotfiles. Safe to run more than once.
#
# Needs (install first, see README):
#   sudo apt install git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
#
# Does NOT use sudo. Steps that need sudo or a sign-in are listed at the end.
# If one step fails, the others still run, and failures are listed at the end.

set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, skip, have, run_step, DOTFILES, SETUP

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
  if has_nerd_font; then
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
  local -a apps
  mapfile -t apps < <(grep -v '^\s*$' "$SETUP/flatpaks.txt")
  quiet "Installing ${#apps[@]} Flatpak apps (already installed ones are skipped)" \
    flatpak install -y --noninteractive flathub "${apps[@]}"
}

# 5. GNOME extensions ----------------------------------------------------------------
# Downloads each extension in setup/gnome-extensions.txt from extensions.gnome.org,
# in the version that matches this computer's GNOME, and marks it as enabled.
# New extensions start working after you log out and back in.
# REINSTALL_EXTENSIONS=1 downloads them again even if installed (post-upgrade.sh uses
# this after a new Ubuntu release, which brings a new GNOME version).
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
    if [[ "${REINSTALL_EXTENSIONS:-0}" != 1 ]] && gnome-extensions info "$uuid" >/dev/null 2>&1; then
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
  local saved="$SETUP/apps" f
  [[ -d "$saved" ]] || { skip "no saved app settings"; return 0; }
  for f in "$saved"/autostart/*.desktop; do
    [[ -f "$f" ]] && put_file "$f" "$HOME/.config/autostart/$(basename "$f")"
  done
  [[ -f "$saved/mimeapps.list" ]] && put_file "$saved/mimeapps.list" "$HOME/.config/mimeapps.list"
  if [[ -f "$saved/qBittorrent/qBittorrent.conf" ]]; then
    if pgrep -x qbittorrent >/dev/null; then
      skip "qBittorrent is open; close it and run install.sh again (it saves its settings on exit)"
    else
      put_file "$saved/qBittorrent/qBittorrent.conf" "$HOME/.config/qBittorrent/qBittorrent.conf"
      for f in "$saved"/qBittorrent/themes/*; do
        [[ -f "$f" ]] && put_file "$f" "$HOME/.config/qBittorrent/themes/$(basename "$f")"
      done
    fi
  fi
  note "apps that start at login apply from your next login"
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
  elif [[ -d "$OBSIDIAN_VAULT/.git" ]] && ! git -C "$OBSIDIAN_VAULT" rev-parse -q --verify HEAD >/dev/null; then
    # The vault was cloned while the notes repo was still empty: fetch the notes now.
    if git -C "$OBSIDIAN_VAULT" fetch -q origin 2>/dev/null \
       && git -C "$OBSIDIAN_VAULT" rev-parse -q --verify origin/main >/dev/null; then
      git -C "$OBSIDIAN_VAULT" checkout -q -f -B main origin/main
      git -C "$OBSIDIAN_VAULT" branch -q -u origin/main
      echo "    notes fetched into ${OBSIDIAN_VAULT/#$HOME/\~}"
    else
      echo "    vault already there; the notes repo is still empty"
    fi
  else
    echo "    vault already there: ${OBSIDIAN_VAULT/#$HOME/\~}"
  fi
  # Only into a vault that's there: creating the folder here would stop the notes
  # from being cloned on a later run.
  if [[ -d "$SETUP/apps/obsidian" && -d "$OBSIDIAN_VAULT" && ! -f "$OBSIDIAN_VAULT/.obsidian/appearance.json" ]]; then
    mkdir -p "$OBSIDIAN_VAULT/.obsidian"
    cp -r --update=none "$SETUP/apps/obsidian/." "$OBSIDIAN_VAULT/.obsidian/"
    echo "    Obsidian settings and Catppuccin theme added to the vault"
  fi
  register_obsidian_vault
}

# Add the vault to Obsidian's list of vaults and make it the one that opens, so
# Obsidian opens straight into it instead of asking. Only while Obsidian is closed,
# because Obsidian rewrites this list when it quits.
register_obsidian_vault() {
  [[ -d "$OBSIDIAN_VAULT" ]] || return 0
  local list
  if have flatpak && flatpak info md.obsidian.Obsidian >/dev/null 2>&1; then
    list="$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
  elif have obsidian; then
    list="$HOME/.config/obsidian/obsidian.json"
  else
    echo "    Obsidian isn't installed yet; run install.sh again after installing it"
    return 0
  fi
  if pgrep -x obsidian >/dev/null; then
    echo "    Obsidian is open: close it and run install.sh again, or choose \"Open folder as vault\""
    return 0
  fi
  mkdir -p "$(dirname "$list")"
  python3 -I -c '
import json, os, secrets, sys, time
path, vault = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except ValueError:
        data = {}
vaults = data.setdefault("vaults", {})
known = [v for v in vaults.values() if v.get("path") == vault]
for v in vaults.values():
    v.pop("open", None)                 # only this vault opens
if known:
    known[0]["open"] = True
    print("    Obsidian will open your vault (already in its list)")
else:
    vaults[secrets.token_hex(8)] = {"path": vault, "ts": int(time.time() * 1000), "open": True}
    print("    vault added to Obsidian; it opens straight into it")
json.dump(data, open(path, "w"))
' "$list" "$OBSIDIAN_VAULT"
}

# 10. Safety checks ---------------------------------------------------------------------
# Secret check before commits (in ~/dotfiles and the vault), and a weekly reminder
# (Sunday evening, or the next login) when settings changed since the last dotsave or
# changes aren't committed. The reminder only notifies; it never commits.
setup_safety_checks() {
  local d
  for d in "$DOTFILES" "$OBSIDIAN_VAULT"; do
    [[ -d "$d/.git" ]] || continue
    git -C "$d" config core.hooksPath "$DOTFILES/.githooks"
    echo "    secret check before commits: ${d/#$HOME/\~}"
  done
  # Signed commits, if this computer has an SSH key (dot ssh creates one).
  bash "$DOTFILES/scripts/ssh-setup.sh" --signing-only
  if have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now dotfiles-reminder.timer 2>/dev/null
    echo "    weekly reminder on (see: systemctl --user list-timers dotfiles-reminder.timer)"
  else
    skip "no systemd user session, so the weekly reminder isn't switched on"
  fi
}

# Main ---------------------------------------------------------------------------------
header "Set up configs and desktop" \
  "Config links, Nerd Font, VS Code extensions, Flatpak apps, GNOME extensions," \
  "desktop look, shortcuts and settings, wallpaper, app settings, Obsidian," \
  "secret check before commits and a weekly reminder. No sudo needed." \
  "Files it replaces are kept as <name>.orig."
STEP_TOTAL=10
# -y / --yes (used by fresh-install.sh), or Yes to everything chosen earlier, skips this.
yes_flag "$@"
ask "Continue?" || { echo "Nothing changed."; exit 0; }

run_step "Linking config files"                          link_configs
run_step "JetBrainsMono Nerd Font"                       install_font
run_step "VS Code extensions"                            install_vscode_extensions
run_step "Flatpak apps"                                  install_flatpaks
run_step "GNOME extensions"                              install_gnome_extensions
run_step "Desktop look, shortcuts and settings, extension settings and dock" restore_gnome_settings
run_step "Wallpaper and lock screen"                     set_wallpaper
run_step "App settings (login apps, default apps, qBittorrent)" restore_app_settings
run_step "Obsidian vault and settings"                   restore_obsidian
run_step "Secret check, signed commits and weekly reminder" setup_safety_checks

summary; ok=$?
if [[ "$UI_NESTED" == 0 ]]; then
  printf '\n%sStill to do yourself%s\n' "$C_B" "$C_N"
  note "Run ~/dotfiles/install-apps.sh (apps, NVIDIA driver, weekly updates), then this again for VS Code's extensions and Obsidian"
  note "Log out and back in (starts the GNOME extensions), then open a new terminal"
  note "Sign in to your apps (Steam, browsers, Discord, Bitwarden, Backups/Google Drive)"
fi
exit "$ok"
