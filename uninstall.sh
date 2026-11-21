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
# brings it back as it was. The NVIDIA driver and Backups always stay. ~/dotfiles stays.
#
#   ~/dotfiles/uninstall.sh                 asks first
#   ~/dotfiles/uninstall.sh --apps          also the apps (a checklist)
#   ~/dotfiles/uninstall.sh --apps --yes    everything, without asking
#   DRY_RUN=1 ~/dotfiles/uninstall.sh --apps --yes   only shows what it would do

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"   # VAULT, WALLPAPER, DCONF_FILES, run, apt_get
# shellcheck source=install-apps.sh
source "$DOTFILES/install-apps.sh"   # only loads APPS and APP_PARTS: the apps and what each adds

# 1. The weekly reminder runs from a linked unit file, so switch it off before unlinking.
reminder_off() {
  if has_user_systemd; then
    systemctl --user disable --now dotfiles-reminder.timer >/dev/null 2>&1 || true
    echo "    weekly reminder off"
  else
    skip "no systemd user session"
  fi
}

# 2. Remove the links into ~/dotfiles (only those: a file of yours with the same name
#    stays), then put back what was there before.
unlink_configs() {
  local f src target n=0 links=0
  while IFS= read -r -d '' f; do
    src="$DOTFILES/$f" target="$HOME/${f#*/}"
    if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$src")" ]]; then
      rm "$target"; links=$((links + 1))
      rmdir --ignore-fail-on-non-empty "$(dirname "$target")" 2>/dev/null || true
    fi
    [[ -e "$target" || -L "$target" ]] && continue
    if [[ -e "$target.orig" ]]; then
      mv "$target.orig" "$target"; echo "    put back your ${target/#$HOME/\~}"; n=$((n + 1))
    elif [[ -f "/etc/skel/${f#*/}" ]]; then
      cp "/etc/skel/${f#*/}" "$target"; echo "    ${target/#$HOME/\~}: Ubuntu's default"; n=$((n + 1))
    fi
  done < <(config_files "${PACKAGES[@]}")
  echo "    $links links removed, $n of your own files put back"
}

# 3. ~/.gitconfig was a link that included your name and email from
#    ~/.config/git/user.gitconfig. Keep them, so your commits still have a name.
keep_git_identity() {
  local f="$HOME/.config/git/user.gitconfig" name email
  [[ -f "$f" ]] || { skip "no saved git name and email"; return 0; }
  name="$(git config --file "$f" user.name || true)"; email="$(git config --file "$f" user.email || true)"
  if [[ -z "$(git config --global user.name || true)" && -n "$name" ]]; then
    git config --global user.name "$name"
    git config --global user.email "$email"
    echo "    git name and email kept in ~/.gitconfig: $name <$email>"
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
    [[ -n "$p" ]] && dconf reset "$p" && n=$((n + 1))
  done <<< "$paths"
  if have gsettings; then
    gsettings reset org.gnome.shell favorite-apps
    gsettings reset org.gnome.shell enabled-extensions
    gsettings reset org.gnome.shell disabled-extensions
    gsettings reset org.gnome.desktop.background picture-uri
    gsettings reset org.gnome.desktop.background picture-uri-dark
    gsettings reset org.gnome.desktop.screensaver picture-uri
  fi
  echo "    $n settings back to Ubuntu's defaults, plus the dock, extensions and wallpaper"
}

# 5. The extensions install.sh downloaded (Ubuntu's own ones stay).
remove_extensions() {
  have gnome-extensions || { skip "gnome-extensions isn't installed"; return 0; }
  local uuid n=0
  while read -r uuid; do
    [[ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]] || continue
    gnome-extensions uninstall "$uuid" 2>/dev/null || rm -rf "$HOME/.local/share/gnome-shell/extensions/$uuid"
    echo "    $uuid"; n=$((n + 1))
  done < <(list_of gnome-extensions.txt)
  (( n )) || echo "    none installed"
}

# 6. Fonts and wallpaper install.sh downloaded.
remove_fonts_wallpaper() {
  local d removed=0
  for d in "$MONO_FONT_DIR" "$NERD_FONT_DIR"; do
    [[ -d "$d" ]] && rm -rf "$d" && echo "    ${d/#$HOME/\~}" && removed=1
  done
  if (( removed )) && have fc-cache; then fc-cache -f >/dev/null 2>&1 || true; fi   # a warning here is harmless
  if [[ -f "$WALLPAPER" ]]; then
    rm -f "$WALLPAPER"; rmdir "$(dirname "$WALLPAPER")" 2>/dev/null || true
    echo "    ${WALLPAPER/#$HOME/\~}"
  fi
  return 0
}

# 7. Copies install.sh made (put_file): the font settings in each Flatpak app, and apps
#    that start at login. Removed only if unchanged; your earlier file (.orig) comes back.
remove_copies() {
  local conf="$DOTFILES/fontconfig/.config/fontconfig/fonts.conf" f n=0
  for f in "$HOME"/.var/app/*/config/fontconfig/fonts.conf "$HOME"/.config/autostart/*.desktop; do
    [[ -f "$f" ]] || continue
    local saved="$conf"
    [[ "$f" == */autostart/* ]] && saved="$SETUP/apps/autostart/$(basename "$f")"
    [[ -f "$saved" ]] && cmp -s <(fill_home "$saved") "$f" || continue
    rm -f "$f"; n=$((n + 1))
    [[ -f "$f.orig" ]] && mv "$f.orig" "$f"
  done
  for f in "$HOME/.config/mimeapps.list" "$HOME/.config/qBittorrent/qBittorrent.conf"; do
    [[ -f "$f.orig" ]] && mv "$f.orig" "$f" && echo "    put back your ${f/#$HOME/\~}"
  done
  echo "    $n copies removed"
}

# 8. Secret check (git hooks) and the website's saved choices.
safety_off() {
  local d
  for d in "$DOTFILES" "$VAULT"; do
    [[ -d "$d/.git" ]] || continue
    if [[ "$(git -C "$d" config core.hooksPath || true)" == "$DOTFILES/.githooks" ]]; then
      git -C "$d" config --unset core.hooksPath && echo "    secret check off: ${d/#$HOME/\~}"
    fi
  done
  if [[ -d "$HOME/.config/dotfiles" ]]; then
    rm -rf "$HOME/.config/dotfiles"; echo "    saved choices deleted (~/.config/dotfiles)"
  fi
  return 0
}

# --- --apps: the apps and system parts too --------------------------------------------
installed_of() { local p; for p in "$@"; do installed "$p" && echo "$p"; done; return 0; }

# app_items: one line per thing that can be removed, "label|kind|what|files". kind is apt
# (what = packages), flatpak (an app ID), jobs, firewall or snapfirefox. files are deleted
# with it (the app's update source and key); a ppa: entry is removed with add-apt-repository.
app_items() {
  local entry choice name p pkgs desk tools
  # Apps from their makers (APPS and APP_PARTS in install-apps.sh), if one of their packages is installed
  for entry in "${APPS[@]}"; do
    IFS='|' read -r choice name _ <<< "$entry"
    [[ -n "${APP_PARTS[$choice]:-}" ]] || continue
    pkgs="${APP_PARTS[$choice]%%|*}"
    # shellcheck disable=SC2086  # one word per package
    [[ -n "$(installed_of $pkgs)" ]] && echo "${name%% (*}|apt|${APP_PARTS[$choice]}"
  done
  # Ubuntu apps from setup/apt-packages.txt, except ones Ubuntu's own desktop includes
  # (like Backups): those were there before.
  desk="$(apt-cache depends ubuntu-desktop ubuntu-desktop-minimal 2>/dev/null | awk '/(Depends|Recommends):/ {print $2}')"
  pkgs=""
  for p in $(list_of apt-packages.txt); do
    installed "$p" && ! grep -qxF "$p" <<< "$desk" && pkgs+="$p "
  done
  [[ -n "$pkgs" ]] && echo "Ubuntu apps: ${pkgs% }|apt|${pkgs% }|"
  # Terminal tools, except the general ones other things use (git, curl, gum, gh, stow, flatpak)
  tools=""
  for p in "${TOOLS[@]}"; do
    case "$p" in git|curl|gum|gh|stow|flatpak) continue ;; esac
    installed "$p" && tools+="$p "
  done
  [[ -n "$tools" ]] && echo "Terminal tools: ${tools% }|apt|${tools% }|"
  if have flatpak; then
    local id name
    while IFS=$'\t' read -r id name; do
      grep -qxF "$id" "$SETUP/flatpaks.txt" && echo "$name (Flatpak)|flatpak|$id|"
    done < <(flatpak list --app --columns=application,name 2>/dev/null)
  fi
  [[ -f /etc/cron.weekly/system-update || -f /etc/cron.monthly/system-cleanup ]] \
    && echo "Weekly updates and monthly clean-up|jobs||/etc/cron.weekly/system-update /etc/cron.monthly/system-cleanup"
  grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null && echo "Firewall (switch it off)|firewall||"
  if have snap && ! snap list firefox >/dev/null 2>&1; then echo "Ubuntu's Snap Firefox (put it back)|snapfirefox||"; fi
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
  local pkgs=() files=() what f line
  while IFS='|' read -r what f; do
    mapfile -t -O "${#pkgs[@]}" pkgs < <(installed_of $what)
    for line in $f; do files+=("$line"); done
  done < <(chosen_of apt)
  (( ${#pkgs[@]} )) || { skip "none chosen"; return 0; }
  echo "    ${pkgs[*]}"
  apt_get_as "Removing ${#pkgs[@]} packages" remove -y "${pkgs[@]}"
  # Their update sources and keys, so apt stops checking them
  for f in "${files[@]}"; do
    if [[ "$DRY_RUN" == 1 ]]; then
      [[ "$f" == ppa:* ]] && run sudo add-apt-repository -y --remove "$f"
      [[ -e "$f" ]] && run sudo rm -f "$f"
    elif [[ "$f" == ppa:* ]]; then
      sudo add-apt-repository -y --remove "$f" >/dev/null 2>&1 && echo "    removed $f" || true
    elif [[ -e "$f" ]]; then
      sudo rm -f "$f" && echo "    removed $f"
    fi
  done
  apt_get_as "Removing what only they needed" autoremove -y
}

remove_flatpak_apps() {
  local ids=() what
  while IFS='|' read -r what _; do ids+=("$what"); done < <(chosen_of flatpak)
  (( ${#ids[@]} )) || { skip "none chosen"; return 0; }
  echo "    ${ids[*]}"
  if [[ "$DRY_RUN" == 1 ]]; then run flatpak uninstall -y --noninteractive "${ids[@]}"
  else quiet "Removing ${#ids[@]} Flatpak apps" flatpak uninstall -y --noninteractive "${ids[@]}"
       quiet "Removing runtimes nothing uses" flatpak uninstall -y --noninteractive --unused; fi
}

remove_system_parts() {
  local any=0 what f
  while IFS='|' read -r what f; do
    for what in $f; do
      [[ -e "$what" ]] || continue
      if [[ "$DRY_RUN" == 1 ]]; then run sudo rm -f "$what"; else sudo rm -f "$what" && echo "    removed $what"; fi
    done; any=1
  done < <(chosen_of jobs)
  if [[ -n "$(chosen_of firewall)" ]]; then
    if [[ "$DRY_RUN" == 1 ]]; then run sudo ufw disable; else sudo ufw disable >/dev/null && echo "    firewall off"; fi
    any=1
  fi
  if [[ -n "$(chosen_of snapfirefox)" ]]; then
    if [[ "$DRY_RUN" == 1 ]]; then run sudo snap install firefox
    else quiet "Installing Ubuntu's Snap Firefox" sudo snap install firefox; fi
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
           "System jobs, firewall, Snap Firefox|remove_system_parts")
  fi
fi
if [[ "$DRY_RUN" == 1 ]]; then   # the user-level part has no dry run; show only the apps part
  (( ${#steps[@]} )) && run_steps "${steps[@]}"
  exit 0
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
printf '\n%sStill to do%s\n' "$C_B" "$C_N"
note "Log out and back in, so GNOME drops the removed extensions and fonts"
if (( ! APPS_TOO )); then
  note "Apps, Flatpaks and system jobs are still installed. To remove them too: dot uninstall --apps"
else
  note "Kept on purpose: the NVIDIA driver (removing it can leave you without a screen) and Backups"
fi
note "VS Code theme, if VS Code stays: code --uninstall-extension \$(cat ~/dotfiles/setup/vscode-extensions.txt)"
note "The dotfiles folder: rm -rf ~/dotfiles"
exit "$ok"
