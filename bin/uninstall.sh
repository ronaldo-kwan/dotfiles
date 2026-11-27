#!/usr/bin/env bash
# uninstall.sh (dot uninstall): undo what install.sh did, for your user only, so you can
# go back to Ubuntu's own setup after trying these dotfiles. No sudo needed.
#
#   - config links removed; your own files from before (<name>.orig) put back
#   - desktop look, shortcuts and settings back to Ubuntu's defaults
#   - the GNOME extensions it installed removed; the fonts and wallpaper it added deleted
#   - weekly reminder off, secret check off, saved website choices deleted
#
# Apps, Flatpaks and the system jobs stay unless you add --apps (they need sudo, and you
# may have had some before): then it lists them, you untick any to keep, and it removes
# the rest after one password. Apps' own settings and data stay, so reinstalling one
# brings it back as it was. The NVIDIA driver and Backups always stay. ~/code/github/dotfiles stays.
#
#   ~/code/github/dotfiles/bin/uninstall.sh                 asks first
#   ~/code/github/dotfiles/bin/uninstall.sh --apps          also the apps (a checklist)
#   ~/code/github/dotfiles/bin/uninstall.sh --apps --yes    everything, without asking
#   DRY_RUN=1 ~/code/github/dotfiles/bin/uninstall.sh --apps --yes   only shows what it would do (all of it)

set -uo pipefail
# shellcheck source=bin/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"   # VAULT, WALLPAPER, DCONF_FILES, run, apt_get
# shellcheck source=bin/install-apps.sh
source "$DOTFILES/bin/install-apps.sh"   # only loads APPS and APP_PARTS: the apps and what each adds

# Each step below changes things only through run, copy and did (lib.sh), so a dry run
# (DRY_RUN=1) shows the same steps as "would run: ..." lines and changes nothing.

# 1. The weekly reminder runs from a linked unit file, so switch it off before unlinking.
reminder_off() {
  if has_user_systemd; then
    run_quiet systemctl --user disable --now dotfiles-reminder.timer || true
    did "weekly reminder off"
    if [[ -f "$REMINDER_DROPIN" ]]; then   # install.sh's pointer to a dotfiles folder elsewhere
      run rm -f "$REMINDER_DROPIN"
      [[ "$DRY_RUN" == 1 ]] || rmdir "$(dirname "$REMINDER_DROPIN")" 2>/dev/null || true
    fi
  else
    skip "no systemd user session"
  fi
}

# 2. Remove the links into ~/code/github/dotfiles (only those: a file of yours with the same name
#    stays), then put back what was there before.
unlink_configs() {
  local f src target n=0 links=0 gone
  while IFS= read -r -d '' f; do
    src="$STOW_DIR/$f" target="$HOME/${f#*/}" gone=0
    if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$src")" ]]; then
      run rm "$target"; links=$((links + 1)) gone=1
      [[ "$DRY_RUN" == 1 ]] || rmdir --ignore-fail-on-non-empty "$(dirname "$target")" 2>/dev/null || true
    fi
    (( gone )) || [[ ! -e "$target" && ! -L "$target" ]] || continue
    if [[ -e "$target.orig" ]]; then
      run mv "$target.orig" "$target"; did "put back your ${target/#$HOME/\~}"; n=$((n + 1))
    elif [[ -f "/etc/skel/${f#*/}" ]]; then
      run cp "/etc/skel/${f#*/}" "$target"; did "${target/#$HOME/\~}: Ubuntu's default"; n=$((n + 1))
    fi
  done < <(config_files "${PACKAGES[@]}")
  did "$links links removed, $n of your own files put back"
  # bat's theme cache still holds the Catppuccin theme: back to bat's own themes.
  if have batcat && bat_theme_ok; then run_quiet batcat cache --clear && did "bat: back to its own themes"; fi
}

# 3. ~/.gitconfig was a link that included your name and email from
#    ~/.config/git/user.gitconfig. Keep them, so your commits still have a name.
keep_git_identity() {
  local f="$HOME/.config/git/user.gitconfig" name email
  [[ -f "$f" ]] || { skip "no saved git name and email"; return 0; }
  name="$(git config --file "$f" user.name || true)"; email="$(git config --file "$f" user.email || true)"
  if [[ -z "$(git config --global user.name || true)" && -n "$name" ]]; then
    run git config --global user.name "$name"
    run git config --global user.email "$email"
    did "git name and email kept in ~/.gitconfig: $name <$email>"
  else
    echo "    git name and email already set: $(git config --global user.name)"
  fi
}

# 4. Every setting install.sh loaded goes back to Ubuntu's default. Backups' settings
#    are left alone, so automatic backups keep running.
reset_desktop() {
  have dconf || { skip "dconf isn't installed (no desktop)"; return 0; }
  local paths
  paths="$(python3 -I - "$SETUP" "${DCONF_FILES[@]}" <<'EOF'
import sys, re, pathlib
setup = pathlib.Path(sys.argv[1])
files = dict(a.split("|", 1) for a in sys.argv[2:])   # file in setup/ -> where in dconf it goes
for name, prefix in files.items():
    f = setup / name
    if not f.exists():
        continue
    section = None
    for line in f.read_text().splitlines():
        if m := re.match(r"\[(.*)\]$", line.strip()):
            section = m.group(1).strip("/")
        elif section is not None and (m := re.match(r"([A-Za-z0-9-]+)=", line)):
            path = (prefix + section + "/" + m.group(1)).replace("//", "/")
            if "deja-dup" not in path:
                print(path)
EOF
)"
  local p n=0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    n=$((n + 1))
    [[ "$DRY_RUN" == 1 ]] || dconf reset "$p"   # (a dry run lists the count, not each key)
  done <<< "$paths"
  [[ "$DRY_RUN" == 1 ]] && echo "    would reset $n settings from setup/*.dconf to Ubuntu's defaults"
  if have gsettings; then
    run gsettings reset org.gnome.shell favorite-apps
    run gsettings reset org.gnome.shell enabled-extensions
    run gsettings reset org.gnome.shell disabled-extensions
    run gsettings reset org.gnome.desktop.background picture-uri
    run gsettings reset org.gnome.desktop.background picture-uri-dark
    run gsettings reset org.gnome.desktop.screensaver picture-uri
  fi
  did "$n settings back to Ubuntu's defaults, plus the dock, extensions and wallpaper"
}

# 5. The extensions install.sh downloaded (Ubuntu's own ones, and ones you had before, stay).
remove_extensions() {
  have gnome-extensions || { skip "gnome-extensions isn't installed"; return 0; }
  local uuid n=0 kept=()
  while read -r uuid; do
    [[ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]] || continue
    was_added "extension:$uuid" || { kept+=("$uuid"); continue; }
    run gnome-extensions uninstall "$uuid" 2>/dev/null || rm -rf "$HOME/.local/share/gnome-shell/extensions/$uuid"
    did "$uuid"; n=$((n + 1))
  done < <(list_of gnome-extensions.txt)
  (( n )) || echo "    none installed"
  (( ${#kept[@]} == 0 )) || note "kept (you had them before the dotfiles): ${kept[*]}"
}

# 6. Fonts and wallpaper install.sh downloaded.
remove_fonts_wallpaper() {
  local d removed=0
  for d in "$MONO_FONT_DIR" "$NERD_FONT_DIR"; do
    [[ -d "$d" ]] || continue
    run rm -rf "$d" && did "${d/#$HOME/\~}" && removed=1
  done
  if (( removed )) && have fc-cache; then run_quiet fc-cache -f || true; fi   # a warning here is harmless
  if [[ -f "$WALLPAPER" ]]; then
    run rm -f "$WALLPAPER"
    [[ "$DRY_RUN" == 1 ]] || rmdir "$(dirname "$WALLPAPER")" 2>/dev/null || true
    did "${WALLPAPER/#$HOME/\~}"
  fi
  return 0
}

# 7. Copies install.sh made (put_file): the font settings in each Flatpak app, and apps
#    that start at login. Removed only if unchanged; your earlier file (.orig) comes back.
remove_copies() {
  local conf="$STOW_DIR/fontconfig/.config/fontconfig/fonts.conf" f n=0
  for f in "$HOME"/.var/app/*/config/fontconfig/fonts.conf "$HOME"/.config/autostart/*.desktop; do
    [[ -f "$f" ]] || continue
    local saved="$conf"
    [[ "$f" == */autostart/* ]] && saved="$SETUP/apps/autostart/$(basename "$f")"
    { [[ -f "$saved" ]] && cmp -s <(fill_home "$saved") "$f"; } || continue
    run rm -f "$f"; n=$((n + 1))
    if [[ -f "$f.orig" ]]; then run mv "$f.orig" "$f"; fi
  done
  for f in "$HOME/.config/mimeapps.list" "$HOME/.config/qBittorrent/qBittorrent.conf" "$HOME/.config/monitors.xml"; do
    [[ -f "$f.orig" ]] || continue
    run mv "$f.orig" "$f" && did "put back your ${f/#$HOME/\~}"
  done
  did "$n copies removed"
}

# 8. Secret check (git hooks) and the website's saved choices.
safety_off() {
  local d
  for d in "$DOTFILES" "$VAULT"; do
    [[ -d "$d/.git" ]] || continue
    if [[ "$(git -C "$d" config core.hooksPath || true)" == "$DOTFILES/.githooks" ]]; then
      run git -C "$d" config --unset core.hooksPath && did "secret check off: ${d/#$HOME/\~}"
    fi
  done
  if [[ -d "$HOME/.config/dotfiles" ]]; then
    run rm -rf "$HOME/.config/dotfiles"; did "saved choices deleted (~/.config/dotfiles)"
  fi
  return 0
}

# --- --apps: the apps and system parts too --------------------------------------------
installed_of() { local p; for p in "$@"; do installed "$p" && echo "$p"; done; return 0; }

# app_items: one line per thing that can be removed, "label|kind|what|files". kind is apt
# (what = packages), flatpak (an app ID), jobs, loginscreen, firewall or snapfirefox. files are deleted
# with it (the app's update source and key); a ppa: entry is removed with add-apt-repository.
# Only what the dotfiles added (was_added, lib.sh): an app, the firewall or the Snap Firefox
# you had before stays out of the list. Computers set up before that was recorded list all.
app_items() {
  local entry choice name p pkgs desk tools
  # Apps from their makers (APPS and APP_PARTS in install-apps.sh), if one of their packages is installed
  for entry in "${APPS[@]}"; do
    IFS='|' read -r choice name _ <<< "$entry"
    { [[ -n "${APP_PARTS[$choice]:-}" ]] && was_added "$choice"; } || continue
    pkgs="${APP_PARTS[$choice]%%|*}"
    # shellcheck disable=SC2086  # one word per package
    [[ -n "$(installed_of $pkgs)" ]] && echo "${name%% (*}|apt|${APP_PARTS[$choice]}"
  done
  # Ubuntu apps from setup/apt-packages.txt, except ones Ubuntu's own desktop includes
  # (like Backups): those were there before.
  desk="$(apt-cache depends ubuntu-desktop ubuntu-desktop-minimal 2>/dev/null | awk '/(Depends|Recommends):/ {print $2}')"
  pkgs=""
  for p in $(list_of apt-packages.txt); do
    installed "$p" && ! grep -qxF "$p" <<< "$desk" && was_added "pkg:$p" && pkgs+="$p "
  done
  [[ -n "$pkgs" ]] && echo "Ubuntu apps: ${pkgs% }|apt|${pkgs% }|"
  # Terminal tools, except the general ones other things use (git, curl, gum, gh, stow, flatpak)
  tools=""
  for p in "${TOOLS[@]}"; do
    case "$p" in git|curl|gum|gh|stow|flatpak) continue ;; esac
    installed "$p" && was_added "pkg:$p" && tools+="$p "
  done
  [[ -n "$tools" ]] && echo "Terminal tools: ${tools% }|apt|${tools% }|"
  if have flatpak; then
    local id name
    while IFS=$'\t' read -r id name; do
      grep -qxF "$id" "$SETUP/flatpaks.txt" && was_added "flatpak:$id" && echo "$name (Flatpak)|flatpak|$id|"
    done < <(flatpak list --app --columns=application,name 2>/dev/null)
  fi
  [[ -f /etc/cron.weekly/system-update || -f /etc/cron.monthly/system-cleanup ]] \
    && echo "Weekly updates and monthly clean-up|jobs||/etc/cron.weekly/system-update /etc/cron.monthly/system-cleanup"
  # The login screen's look (install-apps.sh): its settings, background, and our profile only
  if [[ -f "$GDM_SETTINGS" ]]; then
    local files="$GDM_SETTINGS $LOGIN_BG"
    head -1 "$GDM_PROFILE" 2>/dev/null | grep -q '^# Written by ~/dotfiles' && files+=" $GDM_PROFILE"
    echo "The login screen's look (back to Ubuntu's)|loginscreen||$files"
  fi
  grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null && was_added firewall && echo "Firewall (switch it off)|firewall||"
  if have snap && was_added snapfirefox && ! snap list firefox >/dev/null 2>&1; then echo "Ubuntu's Snap Firefox (put it back)|snapfirefox||"; fi
  return 0
}

# pick_apps: fills REMOVE with the chosen app_items lines (all of them with --yes).
REMOVE=()
pick_apps() {
  local items=() line i picked
  mapfile -t items < <(app_items)
  (( ${#items[@]} )) || { note "no apps or system parts from the dotfiles found"; return 0; }
  if [[ "$YES_ALL" == 1 ]]; then REMOVE=("${items[@]}"); return 0; fi
  if ui_gum; then
    local opts=()
    for i in "${!items[@]}"; do opts+=("${items[i]%%|*}|$i"); done
    echo
    picked="$(gum choose --no-limit --selected='*' --label-delimiter='|' --height $(( ${#opts[@]} + 4 )) \
      --header $'Remove these too? Space unticks what you want to keep, Enter removes the rest.\n(Their settings and data stay. The NVIDIA driver and Backups stay.)' \
      "${opts[@]}")" || { echo "Nothing changed."; exit 0; }
    for i in $picked; do REMOVE+=("${items[i]}"); done
  else
    printf '\n  %sRemove these too?%s %s(their settings and data stay)%s\n' "$C_B" "$C_N" "$C_DIM" "$C_N"
    for line in "${items[@]}"; do ask "Remove ${line%%|*}?" && REMOVE+=("$line"); done
  fi
  return 0
}
chosen_of() { # chosen_of <kind>: the "what" and "files" fields of the chosen items of that kind
  local line kind what files
  for line in "${REMOVE[@]}"; do
    IFS='|' read -r _ kind what files <<< "$line"
    [[ "$kind" == "$1" ]] && echo "$what|$files"
  done
  return 0
}

remove_apt_apps() {
  local pkgs=() files=() names=() what f line
  while IFS='|' read -r what f; do
    read -ra names <<< "$what"   # what: the packages, space-separated
    mapfile -t -O "${#pkgs[@]}" pkgs < <(installed_of "${names[@]}")
    for line in $f; do files+=("$line"); done
  done < <(chosen_of apt)
  (( ${#pkgs[@]} )) || { skip "none chosen"; return 0; }
  echo "    ${pkgs[*]}"
  apt_get_as "Removing ${#pkgs[@]} packages" remove -y "${pkgs[@]}"
  # Their update sources and keys, so apt stops checking them
  for f in "${files[@]}"; do
    if [[ "$f" == ppa:* ]]; then
      run_quiet sudo add-apt-repository -y --remove "$f" && did "removed $f" || true
    elif [[ -e "$f" ]]; then
      run sudo rm -f "$f" && did "removed $f"
    fi
  done
  apt_get_as "Removing what only they needed" autoremove -y
}

remove_flatpak_apps() {
  local ids=() what
  while IFS='|' read -r what _; do ids+=("$what"); done < <(chosen_of flatpak)
  (( ${#ids[@]} )) || { skip "none chosen"; return 0; }
  echo "    ${ids[*]}"
  quiet "Removing ${#ids[@]} Flatpak apps" flatpak uninstall -y --noninteractive "${ids[@]}"
  quiet "Removing runtimes nothing uses" flatpak uninstall -y --noninteractive --unused
}

remove_system_parts() {
  local any=0 what f
  while IFS='|' read -r what f; do
    for what in $f; do
      [[ -e "$what" ]] || continue
      run sudo rm -f "$what" && did "removed $what"
    done; any=1
  done < <(chosen_of jobs)
  while IFS='|' read -r what f; do
    for what in $f; do
      [[ -e "$what" ]] || continue
      run sudo rm -f "$what" && did "removed $what"
    done
    run sudo dconf update && did "login screen back to Ubuntu's look (from the next login screen)"; any=1
  done < <(chosen_of loginscreen)
  if [[ -n "$(chosen_of firewall)" ]]; then
    run_quiet sudo ufw disable && did "firewall off"
    any=1
  fi
  if [[ -n "$(chosen_of snapfirefox)" ]]; then
    quiet "Installing Ubuntu's Snap Firefox" sudo snap install firefox
    any=1
  fi
  (( any )) || skip "none chosen"
  return 0
}

APPS_TOO=0
for a in "$@"; do [[ "$a" == --apps ]] && APPS_TOO=1; done

header "Undo the dotfiles" \
  "Removes the config links (your own files from before come back), resets the" \
  "desktop look, shortcuts and settings to Ubuntu's, removes the extensions, fonts and" \
  "wallpaper it added, and switches off the reminder and the secret check." \
  "With --apps it also removes the apps, Flatpaks and system jobs you pick."
yes_flag "$@"
[[ "$DRY_RUN" == 1 ]] && note "Dry run: shows what it would do, changes nothing."
ask_or_quit "Undo the dotfiles for $(id -un)?"
steps=()
if (( APPS_TOO )); then
  pick_apps
  if (( ${#REMOVE[@]} )); then
    [[ "$DRY_RUN" == 1 ]] || keep_sudo || exit 1
    steps=("Apps removed|remove_apt_apps" "Flatpak apps removed|remove_flatpak_apps"
           "System jobs, login screen, firewall, Snap Firefox|remove_system_parts")
  fi
fi
run_steps \
  "Weekly reminder off|reminder_off" \
  "Config links removed, your own files back|unlink_configs" \
  "Git name and email kept|keep_git_identity" \
  "Desktop look, shortcuts and settings back to Ubuntu's|reset_desktop" \
  "GNOME extensions it installed|remove_extensions" \
  "Fonts and wallpaper it downloaded|remove_fonts_wallpaper" \
  "Copies in Flatpak apps and login apps|remove_copies" \
  "Secret check off, saved choices deleted|safety_off" \
  ${steps[@]+"${steps[@]}"}

summary; ok=$?
[[ "$DRY_RUN" == 1 ]] && exit "$ok"
# Everything the dotfiles added was offered: what you kept is yours now, so a later
# uninstall doesn't offer it again (and a later install records afresh).
if (( APPS_TOO )) && [[ -f "$ADDED_FILE" ]]; then
  printf '# What the dotfiles added to this computer (dot uninstall removes only these).\n# Emptied by dot uninstall --apps on %s: what you kept is yours.\n' "$(date +%F)" > "$ADDED_FILE"
fi
printf '\n%sStill to do%s\n' "$C_B" "$C_N"
note "Log out and back in, so GNOME drops the removed extensions and fonts"
if (( ! APPS_TOO )); then
  note "Apps, Flatpaks and system jobs are still installed. To remove them too: dot uninstall --apps"
else
  note "Kept on purpose: the NVIDIA driver (removing it can leave you without a screen) and Backups"
fi
note "VS Code theme, if VS Code stays: code --uninstall-extension \$(cat ~/code/github/dotfiles/setup/vscode-extensions.txt)"
note "The dotfiles folder: rm -rf ~/code/github/dotfiles"
exit "$ok"
