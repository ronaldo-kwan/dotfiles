#!/usr/bin/env bash
# Set up this computer from ~/code/github/dotfiles. Safe to run more than once.
#
# Needs (install first, see README):
#   sudo apt install git gh gum curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak \
#     nodejs npm pyflakes3 shellcheck
#
# Does NOT use sudo. Steps that need sudo or a sign-in are listed at the end.
# If one step fails, the others still run, and failures are listed at the end.
#
#   ~/code/github/dotfiles/bin/install.sh                 asks first
#   ~/code/github/dotfiles/bin/install.sh --yes           without asking
#   DRY_RUN=1 ~/code/github/dotfiles/bin/install.sh --yes  only shows what it would change (downloads are checked)

set -uo pipefail

# shellcheck source=bin/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, skip, have, run, did, run_steps, DOTFILES, SETUP

# 1. Link config files with stow ------------------------------------------------
link_configs() {
  if ! have stow; then
    skip "stow isn't installed (sudo apt install stow), so nothing was linked"
    return 0
  fi
  local pkgs f target; mapfile -t pkgs < <(chosen_packages)
  # Move aside real files that stow would refuse to replace. An .orig already there is
  # your file from before the dotfiles, so it's kept, and the newer file goes to .orig.<date>.
  # Broken links go: stow refuses them too. They're left when the repo's folders move
  # (before v2.0.0 the packages were at the top of the repo, not in home/).
  while IFS= read -r -d '' f; do
    target="$HOME/${f#*/}"
    if [[ -L "$target" && ! -e "$target" ]]; then
      run rm "$target"
      did "removed the broken link ${target/#$HOME/\~}"
    elif [[ -e "$target" && ! -L "$target" ]]; then
      local backup="$target.orig"
      [[ -e "$backup" ]] && backup="$target.orig.$(date +%Y%m%d-%H%M%S)"
      run mv "$target" "$backup"
      did "kept existing ${target/#$HOME/\~} as ${backup/#$HOME/\~}"
    fi
  done < <(config_files "${pkgs[@]}")
  # --no-folding links individual files, so apps that write extra files into
  # their config folder (like btop's log) don't write them into this repo.
  run stow --dir="$STOW_DIR" --target="$HOME" --no-folding --restow "${pkgs[@]}"
  did "linked: ${pkgs[*]}"
  # bat reads its themes from a cache: add the Catppuccin one from ~/.config/bat/themes.
  if [[ " ${pkgs[*]} " == *" bat "* ]] && have batcat && ! bat_theme_ok; then
    run_quiet batcat cache --build && did "bat: Catppuccin Mocha theme ready"
  fi
}

# 2. Fonts -----------------------------------------------------------------------
# Everything is Roboto. Roboto itself is an Ubuntu package (fonts-roboto, installed by
# install-apps.sh from setup/apt-packages.txt); these two aren't packaged:
#   - RobotoMono Nerd Font (terminal): Roboto Mono plus the icons the prompt uses
#   - Roboto Mono (desktop): the monospace font, from Google Fonts' own repo
# Both are pinned to one version (NERD_FONT_VERSION, ROBOTO_MONO_FILES in lib.sh), checked
# against its checksum, so every computer gets the same font and a changed file is never
# used. A missing or other version is (re)installed. Newer version: docs/maintenance.md.
install_fonts() {
  local want_nerd=0 want_mono=0 tmp f name url
  chosen terminal && ! nerd_font_current && want_nerd=1
  chosen desktop && ! roboto_mono_current && want_mono=1
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
    fetch_checked "$NERD_FONT_URL" "$NERD_FONT_SHA256" "$tmp/RobotoMono.tar.xz" \
      "Downloading RobotoMono Nerd Font $NERD_FONT_VERSION"
    mkdir -p "$tmp/extract"
    tar -xJf "$tmp/RobotoMono.tar.xz" -C "$tmp/extract"
    copy_into "$NERD_FONT_DIR" "$tmp"/extract/RobotoMonoNerdFont*.ttf
    # Which version this is, for dot check (the files themselves don't say).
    [[ "$DRY_RUN" == 1 ]] || echo "$NERD_FONT_SHA256" > "$NERD_FONT_PIN"
    did "RobotoMono Nerd Font $NERD_FONT_VERSION"
  fi
  if (( want_mono )); then
    mkdir -p "$tmp/mono"
    for f in "${ROBOTO_MONO_FILES[@]}"; do
      name="${f%%|*}"; url="${name//\[/%5B}"; url="${url//\]/%5D}"
      fetch_checked "$ROBOTO_MONO_URL/$url" "${f#*|}" "$tmp/mono/$name" "Downloading Roboto Mono ($name)"
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
  local ext failed=() out
  while read -r ext; do
    if [[ "$DRY_RUN" == 1 ]]; then run code --install-extension "$ext"; continue; fi
    # On a failure, VS Code's own last line says why ("not found", a network error, ...).
    if out="$(code --install-extension "$ext" 2>&1)"; then did "$ext"
    else failed+=("$ext"); warn "$ext: $(grep -v '^\s*$' <<< "$out" | tail -1)"; fi
  done < <(list_of vscode-extensions.txt)
  # The others are installed; the step shows ✘ for the ones that weren't.
  (( ${#failed[@]} == 0 )) || { warn "couldn't install: ${failed[*]} (run dot install again)"; return 1; }
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
  # Started in the background by fresh-install.sh (lib.sh): the first run leaves them be,
  # the second waits for them, then checks below that they're all there.
  if flatpaks_installing; then
    if [[ "${FLATPAKS_WAIT:-0}" != 1 ]]; then
      echo "    installing in the background (since the terminal tools); checked when install.sh runs again"
      return 0
    fi
    flatpaks_wait
  fi
  local app new=()
  for app in "${apps[@]}"; do flatpak info "$app" >/dev/null 2>&1 || new+=("$app"); done
  quiet "Installing ${#apps[@]} Flatpak apps (already installed ones are skipped)" \
    flatpak install -y --noninteractive flathub "${apps[@]}"
  for app in ${new[@]+"${new[@]}"}; do mark_added "flatpak:$app"; done   # for dot uninstall
}

# Flatpak apps read fontconfig from their own folder (~/.var/app/<id>/config), not
# ~/.config/fontconfig, so each gets a copy of the Roboto settings. Runs again after
# new Flatpak apps are installed: `dot install`.
flatpak_fonts() {
  need desktop || return 0
  have flatpak || { skip "flatpak isn't installed"; return 0; }
  local conf="$STOW_DIR/fontconfig/.config/fontconfig/fonts.conf" app n=0
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

# download_extension <uuid> <GNOME version> <zip>: download the version of an extension
# made for this GNOME. If it can't, prints why (no internet is not the same problem as
# no version for this GNOME, which is common just after an Ubuntu upgrade).
EXTENSIONS_SITE="${EXTENSIONS_SITE:-https://extensions.gnome.org}"   # (tests use another)
download_extension() {
  local uuid="$1" gnome="$2" zip="$3" code url
  if ! code="$(curl -sSG -o "$zip.json" -w '%{http_code}' "$EXTENSIONS_SITE/extension-info/" \
         --data-urlencode "uuid=$uuid" --data-urlencode "shell_version=$gnome" 2>/dev/null)"; then
    echo "couldn't reach ${EXTENSIONS_SITE#https://} (no internet?)"; return 1
  fi
  case "$code" in
    200) ;;
    404) echo "${EXTENSIONS_SITE#https://} has no version of it for GNOME $gnome (yet)"; return 1 ;;
    *)   echo "${EXTENSIONS_SITE#https://} answered with an error (HTTP $code); try again later"; return 1 ;;
  esac
  url="$(python3 -I -c 'import sys,json; print(json.load(sys.stdin)["download_url"])' < "$zip.json" 2>/dev/null)" \
    || { echo "unexpected answer from ${EXTENSIONS_SITE#https://}"; return 1; }
  curl -fsSL -o "$zip" "$EXTENSIONS_SITE$url" 2>/dev/null \
    || { echo "found a version for GNOME $gnome, but its download failed"; return 1; }
}

install_gnome_extensions() {
  need desktop || return 0
  local missing=()
  for c in gnome-extensions gnome-shell curl python3; do have "$c" || missing+=("$c"); done
  if (( ${#missing[@]} > 0 )); then
    skip "needs ${missing[*]}"
    return 0
  fi
  local shell_version tmp uuid why was_there failed=()
  shell_version="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
  tmp="$(mktemp -d)"
  while read -r uuid; do
    was_there=0; gnome-extensions info "$uuid" >/dev/null 2>&1 && was_there=1
    if [[ "${REINSTALL_EXTENSIONS:-0}" != 1 ]] && (( was_there )); then
      echo "    $uuid: already installed"
    # One that isn't available for this GNOME version (common just after an Ubuntu
    # upgrade) or doesn't download is left out, saying why; the others still go ahead.
    elif ! why="$(download_extension "$uuid" "$shell_version" "$tmp/ext.zip")"; then
      warn "$uuid: $why"
      failed+=("$uuid"); continue
    elif ! run gnome-extensions install --force "$tmp/ext.zip"; then
      warn "$uuid: downloaded, but gnome-extensions couldn't install it"
      failed+=("$uuid"); continue
    else
      did "$uuid: installed"
      (( was_there )) || mark_added "extension:$uuid"   # for dot uninstall: it wasn't yours before
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
    note "downloaded; switched on at the end, just before the restart"
    (( ${#failed[@]} == 0 )) || { warn "missing: ${failed[*]}; try again later with dot install"; return 1; }
    return 0
  fi
  run gsettings set org.gnome.shell disable-user-extensions false
  did "enabled (they start after you log out and back in)"
  (( ${#failed[@]} == 0 )) || { warn "missing: ${failed[*]}; try again later with dot install"; return 1; }
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
  # Ptyxis keeps its colours in a profile with a different ID on each computer. It only
  # makes one the first time it's opened, so on a new computer there's none yet: make it
  # here (32 hex digits, as Ptyxis does), and Ptyxis uses it from its first start.
  if [[ -f "$SETUP/desktop-settings.dconf" ]]; then
    palette="$(sed -n 's/^# ptyxis-palette=//p' "$SETUP/desktop-settings.dconf")"
  fi
  if [[ -n "$palette" ]]; then
    uuid="$(dconf read /org/gnome/Ptyxis/default-profile-uuid | tr -d "'")"
    # Profiles but none marked default: Ptyxis uses the first.
    [[ -n "$uuid" ]] || uuid="$(dconf read /org/gnome/Ptyxis/profile-uuids | sed -n "s/^\['\([0-9a-f]\{32\}\)'.*/\1/p")"
    if [[ -z "$uuid" ]]; then
      uuid="$(tr -d '-' < /proc/sys/kernel/random/uuid)"
      run dconf write /org/gnome/Ptyxis/profile-uuids "['$uuid']"
      run dconf write /org/gnome/Ptyxis/default-profile-uuid "'$uuid'"
    fi
    run dconf write "/org/gnome/Ptyxis/Profiles/$uuid/palette" "$palette"
  fi
  did "restored"
}

# 7. Wallpaper -----------------------------------------------------------------------
# From setup/wallpaper/: tropic_island_night.jpg from the Catppuccin wallpaper collection
# (github.com/zhichaoh/catppuccin-wallpapers, MIT: licenses/wallpaper.txt). Copied to
# ~/Pictures/Wallpapers/current, so the desktop keeps it even if the dotfiles folder moves.
WALLPAPER_SAVED="$SETUP/wallpaper/${WALLPAPER##*/}"
set_wallpaper() {
  need desktop || return 0
  if ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  [[ "${DEFER_DESKTOP:-0}" == 1 ]] && { held_back; return 0; }
  local wall="$WALLPAPER" uri
  cmp -s "$WALLPAPER_SAVED" "$wall" || copy_into "$(dirname "$wall")" "$WALLPAPER_SAVED"
  uri="file://$wall"
  run gsettings set org.gnome.desktop.background picture-uri "$uri"
  run gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
  run gsettings set org.gnome.desktop.screensaver picture-uri "$uri"   # lock screen
  did "set"
}

# 8. App settings -------------------------------------------------------------------
# Apps that start at login, default apps, qBittorrent (saved by `dot save` in setup/apps/).
# Existing files that differ are kept as <name>.orig (the first time) or <name>.prev.
put_file() { # put_file <saved file> <destination>: copy, turning @HOME@ into this home folder
  local src="$1" dst="$2"
  if [[ -f "$dst" ]] && cmp -s <(fill_home "$src") "$dst"; then return 0; fi
  # The first time, yours is kept as .orig: your file from before the dotfiles, which
  # later runs never replace (apps like qBittorrent rewrite their settings, so they
  # differ again each run). After that, the file being replaced is kept as .prev.
  local keep="$dst.orig"; [[ -e "$keep" ]] && keep="$dst.prev"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "    would write ${dst/#$HOME/\~}$([[ -f "$dst" ]] && echo " (yours kept as .${keep##*.})")"; return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then mv "$dst" "$keep"; fi
  fill_home "$src" > "$dst"
  echo "    ${dst/#$HOME/\~}"
}

# monitors_for_here <saved monitors.xml>: print it with each screen's serial number filled
# in from the screens connected now (dot save leaves the serials out): the screen on the
# same connector with the same maker and model, or else the only connected screen of that
# maker and model. Fails if a screen it names isn't connected (or two identical screens
# can't be told apart), so the display settings saved on one computer are never used with
# another screen.
monitors_for_here() {
  local live
  have gdbus || return 1
  live="$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
    --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null)" || return 1
  python3 -I - "$1" "$live" <<'PY'
import re, sys
saved, live = open(sys.argv[1]).read(), sys.argv[2]
# Connected screens, from GNOME: (('eDP-1', 'maker', 'model', 'serial'), [modes...
screens = re.findall(r"\(\('([^']*)', '([^']*)', '([^']*)', '([^']*)'\), \[", live)
def tag(spec, name):
    found = re.search(r"<%s>([^<]*)</%s>" % (name, name), spec)
    return found.group(1) if found else None
def fill(m):
    spec = m.group(0)
    conn, vendor, product = tag(spec, "connector"), tag(spec, "vendor"), tag(spec, "product")
    same_model = [s for c, v, p, s in screens if (v, p) == (vendor, product)]
    on_connector = [s for c, v, p, s in screens if (c, v, p) == (conn, vendor, product)]
    # Two identical screens: only the connector tells them apart (else both would get
    # one serial, and GNOME would ignore the settings).
    serials = on_connector or (same_model if len(same_model) == 1 else [])
    if not serials:
        sys.exit(1)
    return spec.replace("<serial>@SERIAL@</serial>", "<serial>%s</serial>" % serials[0])
print(re.sub(r"<monitorspec>.*?</monitorspec>", fill, saved, flags=re.S), end="")
PY
}

restore_app_settings() {
  local saved="$SETUP/apps" f
  [[ -d "$saved" ]] || { skip "no saved app settings"; return 0; }
  for f in "$saved"/autostart/*.desktop; do   # named after the app's Flatpak ID
    [[ -f "$f" ]] && chosen "flatpak:$(basename "$f" .desktop)" && put_file "$f" "$HOME/.config/autostart/$(basename "$f")"
  done
  if [[ -f "$saved/mimeapps.list" ]] && chosen desktop; then put_file "$saved/mimeapps.list" "$HOME/.config/mimeapps.list"; fi
  # Display settings (scale, resolution): only when the same screen is connected
  if [[ -f "$saved/monitors.xml" ]] && chosen desktop; then
    f="$(mktemp)"
    if monitors_for_here "$saved/monitors.xml" > "$f"; then
      put_file "$f" "$HOME/.config/monitors.xml"
    else
      note "saved display settings are for another screen (or no desktop is running); left alone"
    fi
    rm -f "$f"
  fi
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
  # Brave Origin's own settings (scripts/brave-settings.py: an allowlist, merged into its
  # profile). Brave rewrites its settings file while open and on closing, so only when closed.
  if [[ -f "$saved/brave-settings.json" ]] && chosen app:brave-origin; then
    if pgrep -f '^/opt/brave.com/brave-origin/brave' >/dev/null; then
      skip "Brave Origin is open; close it and run install.sh again to put back its settings"
    elif [[ "$DRY_RUN" == 1 ]]; then
      echo "    would put back Brave Origin's saved settings in ${BRAVE_PREFS/#$HOME/\~}"
    else
      for f in "$BRAVE_PREFS" "$BRAVE_LOCAL_STATE"; do   # (the second: content filtering)
        if [[ -f "$f" && ! -f "$f.orig" ]]; then cp -p "$f" "$f.orig"; fi
      done
      python3 -I "$DOTFILES/scripts/brave-settings.py" restore "$saved/brave-settings.json" "$BRAVE_PREFS" "$SETUP/wallpaper" \
        && did "Brave Origin's settings put back (from its next start)"
    fi
  fi
  note "apps that start at login, and display settings, apply from your next login"
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
# Secret check before commits (in ~/code/github/dotfiles and the vault), and a weekly reminder
# (Sunday evening, or the next login) when settings changed since the last dot save or
# changes aren't committed. The reminder only notifies; it never commits.
# The reminder's unit runs ~/code/github/dotfiles/bin/check.sh. Dotfiles kept somewhere else (DOTFILES_DIR
# in bootstrap.sh) get a drop-in next to it that points it at the real folder.
reminder_folder() {
  if [[ "$DOTFILES" == "$DEFAULT_DOTFILES" ]]; then
    if [[ -f "$REMINDER_DROPIN" ]]; then run rm -f "$REMINDER_DROPIN"; fi
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then echo "    would point the weekly reminder at ${DOTFILES/#$HOME/\~}"; return 0; fi
  mkdir -p "$(dirname "$REMINDER_DROPIN")"
  # (In unit files % starts a specifier, so a literal one is written %%.)
  printf '# Written by install.sh: the dotfiles are in %s, not ~/code/github/dotfiles.\n[Service]\nExecStart=\nExecStart="%s/bin/check.sh" --notify\n' \
    "$DOTFILES" "${DOTFILES//%/%%}" > "$REMINDER_DROPIN"
  did "weekly reminder runs ${DOTFILES/#$HOME/\~}/bin/check.sh"
}

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
    reminder_folder
    # A link to the timer from before the repo's folders moved: enable makes a new one.
    local wants="$HOME/.config/systemd/user/timers.target.wants/dotfiles-reminder.timer"
    if [[ -L "$wants" && ! -e "$wants" ]]; then run rm "$wants"; fi
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
  "Files it replaces are kept as <name>.orig (the first time) or <name>.prev."
# -y / --yes (used by fresh-install.sh), or Yes to everything chosen earlier, skips this.
yes_flag "$@"
[[ "$DRY_RUN" == 1 ]] && note "Dry run: shows what it would change; downloads are made and checked, nothing is installed."
ask_or_quit "Continue?"
[[ "$DRY_RUN" == 1 ]] || git_identity
added_init   # before anything is installed: what was already here isn't counted as added

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
  note "Run ~/code/github/dotfiles/bin/install-apps.sh (apps, NVIDIA driver, weekly updates), then this again for VS Code's extensions and Obsidian"
  note "Log out and back in (starts the GNOME extensions), then open a new terminal"
  note "Sign in to your apps (Steam, browsers, Discord, Backups/Google Drive)"
fi
exit "$ok"
