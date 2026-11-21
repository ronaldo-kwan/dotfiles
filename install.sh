#!/usr/bin/env bash
# Set up this computer from ~/dotfiles. Safe to run more than once.
#
# Needs (install first, see README):
#   sudo apt install git gh gum curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
#
# Does NOT use sudo. Steps that need sudo or a sign-in are listed at the end.
# If one step fails, the others still run, and failures are listed at the end.
#
#   ~/dotfiles/install.sh                 asks first
#   ~/dotfiles/install.sh --yes           without asking
#   DRY_RUN=1 ~/dotfiles/install.sh --yes  only shows what it would change (downloads are checked)

set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, skip, have, run, did, run_steps, DOTFILES, SETUP

# 1. Link config files with stow ------------------------------------------------
link_configs() {
  if ! have stow; then
    skip "stow isn't installed (sudo apt install stow), so nothing was linked"
    return 0
  fi
  local pkgs f target; mapfile -t pkgs < <(chosen_packages)
  # Move aside real files that stow would refuse to replace.
  while IFS= read -r -d '' f; do
    target="$HOME/${f#*/}"
    if [[ -e "$target" && ! -L "$target" ]]; then
      run mv "$target" "$target.orig"
      did "kept existing ${target/#$HOME/\~} as ${target/#$HOME/\~}.orig"
    fi
  done < <(config_files "${pkgs[@]}")
  # --no-folding links individual files, so apps that write extra files into
  # their config folder (like btop's log) don't write them into this repo.
  run stow --dir="$DOTFILES" --target="$HOME" --no-folding --restow "${pkgs[@]}"
  did "linked: ${pkgs[*]}"
}

# 2. Fonts -----------------------------------------------------------------------
# Everything is Roboto. Roboto itself is an Ubuntu package (fonts-roboto, installed by
# install-apps.sh from setup/apt-packages.txt); these two aren't packaged:
#   - RobotoMono Nerd Font (terminal): Roboto Mono plus the icons the prompt uses
#   - Roboto Mono (desktop): the monospace font, from Google Fonts' own repo
# Both are pinned: one version, checked against its checksum, so every computer gets the
# same font and a changed file is never used. Moving to a newer version: docs/maintenance.md.
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/RobotoMono.tar.xz"
NERD_FONT_SHA256="61f53438b240a00c87c92dc2c372db0bbb264473b36a8144ea62babf787f8383"
ROBOTO_MONO_URL="https://raw.githubusercontent.com/google/fonts/333480ba7b601a89b75e5e84352c6cdf48086593/ofl/robotomono"
ROBOTO_MONO_FILES=(   # file|sha256
  "RobotoMono[wght].ttf|66a80e79d17e4c7cabd162e2916578a4cc08fd19eef6e2a643305eae9c567b2b"
  "RobotoMono-Italic[wght].ttf|49ac343bb7b070071e53f0a8a501d68d140ed98ebd0a43b6b8fb96cf22f09ff7")
install_fonts() {
  local want_nerd=0 want_mono=0 tmp f name url
  chosen terminal && ! has_nerd_font && want_nerd=1
  chosen desktop && ! has_roboto_mono && want_mono=1
  if (( !want_nerd && !want_mono )); then
    chosen terminal || chosen desktop || { skip "not chosen"; return 0; }
    echo "    already installed"
    return 0
  fi
  if ! have curl; then
    skip "curl isn't installed (sudo apt install curl), so the fonts weren't downloaded"
    return 0
  fi
  tmp="$(mktemp -d)"
  if (( want_nerd )); then
    fetch_checked "$NERD_FONT_URL" "$NERD_FONT_SHA256" "$tmp/RobotoMono.tar.xz"
    mkdir -p "$tmp/extract"
    tar -xJf "$tmp/RobotoMono.tar.xz" -C "$tmp/extract"
    copy_into "$NERD_FONT_DIR" "$tmp"/extract/RobotoMonoNerdFont*.ttf
    did "RobotoMono Nerd Font"
  fi
  if (( want_mono )); then
    mkdir -p "$tmp/mono"
    for f in "${ROBOTO_MONO_FILES[@]}"; do
      name="${f%%|*}"; url="${name//\[/%5B}"; url="${url//\]/%5D}"
      fetch_checked "$ROBOTO_MONO_URL/$url" "${f#*|}" "$tmp/mono/$name"
    done
    copy_into "$MONO_FONT_DIR" "$tmp"/mono/*.ttf
    did "Roboto Mono"
  fi
  rm -rf "$tmp"
  run fc-cache -f "$HOME/.local/share/fonts"
}

# 3. VS Code extensions --------------------------------------------------------------
install_vscode_extensions() {
  need app:code || return 0
  if ! have code; then
    skip "VS Code isn't installed yet"
    return 0
  fi
  local ext
  while read -r ext; do
    run_quiet code --install-extension "$ext" && did "$ext"
  done < <(list_of vscode-extensions.txt)
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
  mapfile -t apps < <(chosen_from flatpaks.txt flatpak:)
  (( ${#apps[@]} )) || { skip "no Flatpak apps chosen"; return 0; }
  quiet "Installing ${#apps[@]} Flatpak apps (already installed ones are skipped)" \
    flatpak install -y --noninteractive flathub "${apps[@]}"
}

# Flatpak apps read fontconfig from their own folder (~/.var/app/<id>/config), not
# ~/.config/fontconfig, so each gets a copy of the Roboto settings. Runs again after
# new Flatpak apps are installed: `dot install`.
flatpak_fonts() {
  need desktop || return 0
  have flatpak || { skip "flatpak isn't installed"; return 0; }
  local conf="$DOTFILES/fontconfig/.config/fontconfig/fonts.conf" app n=0
  while read -r app; do
    [[ -n "$app" ]] || continue
    if [[ "$DRY_RUN" == 1 ]]; then put_file "$conf" "$HOME/.var/app/$app/config/fontconfig/fonts.conf"
    else put_file "$conf" "$HOME/.var/app/$app/config/fontconfig/fonts.conf" >/dev/null; fi   # one line for all
    n=$((n + 1))
  done < <(flatpak list --app --columns=application 2>/dev/null)
  did "$n Flatpak apps use Roboto"
}

# 5. GNOME extensions ----------------------------------------------------------------
# Downloads each extension in setup/gnome-extensions.txt from extensions.gnome.org,
# in the version that matches this computer's GNOME, and marks it as enabled.
# New extensions start working after you log out and back in.
# REINSTALL_EXTENSIONS=1 downloads them again even if installed (post-upgrade.sh uses
# this after a new Ubuntu release, which brings a new GNOME version).
install_gnome_extensions() {
  need desktop || return 0
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
    if [[ "${REINSTALL_EXTENSIONS:-0}" != 1 ]] && gnome-extensions info "$uuid" >/dev/null 2>&1; then
      echo "    $uuid: already installed"
    else
      info="$(curl -fsSG https://extensions.gnome.org/extension-info/ \
        --data-urlencode "uuid=$uuid" --data-urlencode "shell_version=$shell_version")"
      url="$(python3 -I -c 'import sys,json; print(json.load(sys.stdin)["download_url"])' <<< "$info")"
      curl -fsSL -o "$tmp/ext.zip" "https://extensions.gnome.org$url"
      run gnome-extensions install --force "$tmp/ext.zip"
      did "$uuid: installed"
    fi
    # Add it to the enabled list (keeps everything already enabled). Held back during
    # fresh-install.sh, which switches everything on just before its restart.
    [[ "${DEFER_DESKTOP:-0}" == 1 ]] && continue
    run gsettings set org.gnome.shell enabled-extensions "$(python3 -I -c '
import sys, ast
current = ast.literal_eval(sys.argv[1].removeprefix("@as "))
if sys.argv[2] not in current:
    current.append(sys.argv[2])
print(current)' "$(gsettings get org.gnome.shell enabled-extensions)" "$uuid")"
  done < <(list_of gnome-extensions.txt)
  rm -rf "$tmp"
  if [[ "${DEFER_DESKTOP:-0}" == 1 ]]; then
    note "downloaded; switched on at the end, just before the restart"; return 0
  fi
  run gsettings set org.gnome.shell disable-user-extensions false
  did "enabled (they start after you log out and back in)"
}

# 6. GNOME settings ----------------------------------------------------------------
# fresh-install.sh sets DEFER_DESKTOP=1, so the desktop doesn't change look halfway
# through; it runs `install.sh --desktop-only` right before restarting instead.
held_back() { note "held back: applied at the end, just before the restart"; }

restore_gnome_settings() {
  need desktop || return 0
  if ! have dconf || ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  [[ "${DEFER_DESKTOP:-0}" == 1 ]] && { held_back; return 0; }
  # The look (theme, icons, fonts, accent colour, dark mode, window buttons, workspaces,
  # exactly which extensions are on or off, including Ubuntu's built-in ones like Ubuntu
  # Dock), shortcuts, extension settings, and the rest: power, sound, Files, file dialogs,
  # search order, backups and app settings (see DCONF_FILES in lib.sh). @HOME@, in the
  # folders Backups leaves out, becomes this computer's home folder.
  local e f palette='' uuid
  for e in "${DCONF_FILES[@]}"; do
    f="$SETUP/${e%%|*}"
    [[ -f "$f" ]] || continue
    if [[ "$DRY_RUN" == 1 ]]; then echo "    would load setup/${e%%|*} into dconf ${e#*|}"
    else fill_home "$f" | dconf load "${e#*|}"; fi
  done
  run gsettings set org.gnome.shell favorite-apps "$(cat "$SETUP/dock-favorites.txt")"
  # Ptyxis keeps its colours in a profile with a different ID on each computer.
  if [[ -f "$SETUP/desktop-settings.dconf" ]]; then
    palette="$(sed -n 's/^# ptyxis-palette=//p' "$SETUP/desktop-settings.dconf")"
  fi
  uuid="$(dconf read /org/gnome/Ptyxis/default-profile-uuid | tr -d "'")"
  if [[ -n "$palette" && -n "$uuid" ]]; then
    run dconf write "/org/gnome/Ptyxis/Profiles/$uuid/palette" "$palette"
  fi
  did "restored"
}

# 7. Wallpaper -----------------------------------------------------------------------
# The wallpaper isn't stored in this repo: it's downloaded from the Catppuccin wallpaper
# collection (github.com/zhichaoh/catppuccin-wallpapers, MIT) and checked against this
# fingerprint, so a changed file is never used.
WALLPAPER_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/tropic_island_night.jpg"
WALLPAPER_SHA256="166f34d21ec26c41ea70f0cbee829205222918184458b152ea2a15e6a334495c"
set_wallpaper() {
  need desktop || return 0
  if ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  [[ "${DEFER_DESKTOP:-0}" == 1 ]] && { held_back; return 0; }
  local wall="$WALLPAPER" uri tmp
  if [[ ! -f "$wall" ]]; then
    have curl || { skip "curl isn't installed, so the wallpaper wasn't downloaded"; return 0; }
    tmp="$(mktemp -d)"
    fetch_checked "$WALLPAPER_URL" "$WALLPAPER_SHA256" "$tmp/${wall##*/}"
    copy_into "$(dirname "$wall")" "$tmp/${wall##*/}"
    rm -rf "$tmp"
  fi
  uri="file://$wall"
  run gsettings set org.gnome.desktop.background picture-uri "$uri"
  run gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
  run gsettings set org.gnome.desktop.screensaver picture-uri "$uri"   # lock screen
  did "set"
}

# 8. App settings -------------------------------------------------------------------
# Apps that start at login, default apps, qBittorrent (saved by `dotsave` in setup/apps/).
# Existing files that differ are kept as <name>.orig.
put_file() { # put_file <saved file> <destination>: copy, turning @HOME@ into this home folder
  local src="$1" dst="$2"
  if [[ -f "$dst" ]] && cmp -s <(fill_home "$src") "$dst"; then return 0; fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "    would write ${dst/#$HOME/\~}$([[ -f "$dst" ]] && echo " (yours kept as .orig)")"; return 0
  fi
  mkdir -p "$(dirname "$dst")"
  [[ -f "$dst" ]] && mv "$dst" "$dst.orig"
  fill_home "$src" > "$dst"
  echo "    ${dst/#$HOME/\~}"
}

restore_app_settings() {
  local saved="$SETUP/apps" f
  [[ -d "$saved" ]] || { skip "no saved app settings"; return 0; }
  for f in "$saved"/autostart/*.desktop; do   # named after the app's Flatpak ID
    [[ -f "$f" ]] && chosen "flatpak:$(basename "$f" .desktop)" && put_file "$f" "$HOME/.config/autostart/$(basename "$f")"
  done
  if [[ -f "$saved/mimeapps.list" ]] && chosen desktop; then put_file "$saved/mimeapps.list" "$HOME/.config/mimeapps.list"; fi
  if [[ -f "$saved/qBittorrent/qBittorrent.conf" ]] && chosen pkg:qbittorrent; then
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
# vault settings (theme, which plugins are on) come from setup/apps/obsidian/ if the vault has none.
restore_obsidian() {
  need notes || return 0
  if [[ ! -d "$VAULT" ]]; then
    if have gh && gh repo view obsidian-vault >/dev/null 2>&1; then
      run gh repo clone obsidian-vault "$VAULT" -- --quiet
      did "notes cloned to ${VAULT/#$HOME/\~}"
    else
      skip "no obsidian-vault repo found on GitHub (or gh isn't signed in), so no notes cloned"
    fi
  elif [[ -d "$VAULT/.git" ]] && ! git -C "$VAULT" rev-parse -q --verify HEAD >/dev/null; then
    # The vault was cloned while the notes repo was still empty: fetch the notes now.
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "    would fetch the notes into ${VAULT/#$HOME/\~}, if the notes repo has any by now"
    elif git -C "$VAULT" fetch -q origin 2>/dev/null \
       && git -C "$VAULT" rev-parse -q --verify origin/main >/dev/null; then
      git -C "$VAULT" checkout -q -f -B main origin/main
      git -C "$VAULT" branch -q -u origin/main
      echo "    notes fetched into ${VAULT/#$HOME/\~}"
    else
      echo "    vault already there; the notes repo is still empty"
    fi
  else
    echo "    vault already there: ${VAULT/#$HOME/\~}"
  fi
  # Only into a vault that's there: creating the folder here would stop the notes
  # from being cloned on a later run.
  if [[ -d "$SETUP/apps/obsidian" && -d "$VAULT" && ! -f "$VAULT/.obsidian/appearance.json" ]]; then
    run mkdir -p "$VAULT/.obsidian"
    run cp -r --update=none "$SETUP/apps/obsidian/." "$VAULT/.obsidian/"
    did "Obsidian settings and Catppuccin theme added to the vault"
  fi
  register_obsidian_vault
}

# Add the vault to Obsidian's list of vaults and make it the one that opens, so
# Obsidian opens straight into it instead of asking. Only while Obsidian is closed,
# because Obsidian rewrites this list when it quits.
register_obsidian_vault() {
  [[ -d "$VAULT" ]] || return 0
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
  if [[ "$DRY_RUN" == 1 ]]; then echo "    would make Obsidian open your vault (${list/#$HOME/\~})"; return 0; fi
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
' "$list" "$VAULT"
}

# 10. Safety checks ---------------------------------------------------------------------
# Secret check before commits (in ~/dotfiles and the vault), and a weekly reminder
# (Sunday evening, or the next login) when settings changed since the last dotsave or
# changes aren't committed. The reminder only notifies; it never commits.
setup_safety_checks() {
  need safety || return 0
  local d
  for d in "$DOTFILES" "$VAULT"; do
    [[ -d "$d/.git" ]] || continue
    run git -C "$d" config core.hooksPath "$DOTFILES/.githooks"
    did "secret check before commits: ${d/#$HOME/\~}"
  done
  # Signed commits, if this computer has an SSH key (dot ssh creates one).
  run bash "$DOTFILES/scripts/ssh-setup.sh" --signing-only
  if has_user_systemd; then
    run systemctl --user daemon-reload
    run systemctl --user enable --now dotfiles-reminder.timer 2>/dev/null
    did "weekly reminder on (see: systemctl --user list-timers dotfiles-reminder.timer)"
  else
    skip "no systemd user session, so the weekly reminder isn't switched on"
  fi
}

# Main ---------------------------------------------------------------------------------
# --desktop-only: just the visible part (extensions on, theme, fonts, shortcuts, settings,
# wallpaper), in one go. fresh-install.sh runs this right before restarting.
if [[ "${1:-}" == "--desktop-only" ]]; then
  switch_on_extensions() { have gsettings && run gsettings set org.gnome.shell disable-user-extensions false; return 0; }
  run_steps \
    "Desktop look, shortcuts and settings, extensions on or off|restore_gnome_settings" \
    "Allow GNOME extensions|switch_on_extensions" \
    "Wallpaper and lock screen|set_wallpaper"
  summary; exit $?
fi

title="Set up configs and desktop"; [[ "$DRY_RUN" == 1 ]] && title+=" (dry run: changes nothing)"
header "$title" \
  "Config links, Roboto fonts, VS Code extensions, Flatpak apps, GNOME extensions," \
  "desktop look, shortcuts and settings, wallpaper, app settings, Obsidian," \
  "secret check before commits and a weekly reminder. No sudo needed." \
  "Files it replaces are kept as <name>.orig."
# -y / --yes (used by fresh-install.sh), or Yes to everything chosen earlier, skips this.
yes_flag "$@"
[[ "$DRY_RUN" == 1 ]] && note "Dry run: shows what it would change; downloads are made and checked, nothing is installed."
ask_or_quit "Continue?"
[[ "$DRY_RUN" == 1 ]] || git_identity

run_steps \
  "Linking config files|link_configs" \
  "Fonts (Roboto Mono and RobotoMono Nerd Font)|install_fonts" \
  "VS Code extensions|install_vscode_extensions" \
  "Flatpak apps|install_flatpaks" \
  "Roboto in Flatpak apps|flatpak_fonts" \
  "GNOME extensions|install_gnome_extensions" \
  "Desktop look, shortcuts and settings, extension settings and dock|restore_gnome_settings" \
  "Wallpaper and lock screen|set_wallpaper" \
  "App settings (login apps, default apps, qBittorrent)|restore_app_settings" \
  "Obsidian vault and settings|restore_obsidian" \
  "Secret check, signed commits and weekly reminder|setup_safety_checks"

summary; ok=$?
if [[ "$UI_NESTED" == 0 && "$DRY_RUN" != 1 ]]; then
  printf '\n%sStill to do yourself%s\n' "$C_B" "$C_N"
  note "Run ~/dotfiles/install-apps.sh (apps, NVIDIA driver, weekly updates), then this again for VS Code's extensions and Obsidian"
  note "Log out and back in (starts the GNOME extensions), then open a new terminal"
  note "Sign in to your apps (Steam, browsers, Discord, Backups/Google Drive)"
fi
exit "$ok"
