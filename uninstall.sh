#!/usr/bin/env bash
# uninstall.sh (dot uninstall): undo what install.sh did, for your user only, so you can
# go back to Ubuntu's own setup after trying these dotfiles. No sudo needed.
#
#   - config links removed; your own files from before (<name>.orig) put back
#   - desktop look, shortcuts and settings back to Ubuntu's defaults
#   - the GNOME extensions it installed removed; the fonts and wallpaper it added deleted
#   - weekly reminder off, secret check off, saved website choices deleted
#
# It doesn't remove apps, Flatpaks or the system jobs (they need sudo and you may want
# them): it prints the commands for those at the end. ~/dotfiles itself stays too.
#
#   ~/dotfiles/uninstall.sh          asks first
#   ~/dotfiles/uninstall.sh --yes    doesn't ask

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
SETUP="$DOTFILES/setup"
VAULT="$HOME/Documents/Obsidian Vault"
WALLPAPER="$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night.jpg"

# 1. The weekly reminder runs from a linked unit file, so switch it off before unlinking.
reminder_off() {
  if have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user disable --now dotfiles-reminder.timer >/dev/null 2>&1 || true
    echo "    weekly reminder off"
  else
    skip "no systemd user session"
  fi
}

# 2. Remove the links into ~/dotfiles (only those: a file of yours with the same name
#    stays), then put back what was there before.
unlink_configs() {
  local pkg src target n=0 links=0
  for pkg in "${PACKAGES[@]}"; do
    while IFS= read -r -d '' src; do
      target="$HOME/${src#"$DOTFILES/$pkg/"}"
      if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$src")" ]]; then
        rm "$target"; links=$((links + 1))
        rmdir --ignore-fail-on-non-empty "$(dirname "$target")" 2>/dev/null || true
      fi
      [[ -e "$target" || -L "$target" ]] && continue
      if [[ -e "$target.orig" ]]; then
        mv "$target.orig" "$target"; echo "    put back your ${target/#$HOME/\~}"; n=$((n + 1))
      elif [[ -f "/etc/skel/${target#"$HOME/"}" ]]; then
        cp "/etc/skel/${target#"$HOME/"}" "$target"; echo "    ${target/#$HOME/\~}: Ubuntu's default"; n=$((n + 1))
      fi
    done < <(find "$DOTFILES/$pkg" -type f -print0)
  done
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
  paths="$(python3 -I - "$SETUP" <<'EOF'
import sys, re, pathlib
setup = pathlib.Path(sys.argv[1])
files = {"gnome-desktop.dconf": "/org/gnome/", "gnome-shortcuts.dconf": "/org/gnome/settings-daemon/plugins/media-keys/",
         "gnome-extension-settings.dconf": "/org/gnome/shell/extensions/", "desktop-settings.dconf": "/"}
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
    [[ -z "$uuid" || "$uuid" == \#* ]] && continue
    [[ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]] || continue
    gnome-extensions uninstall "$uuid" 2>/dev/null || rm -rf "$HOME/.local/share/gnome-shell/extensions/$uuid"
    echo "    $uuid"; n=$((n + 1))
  done < "$SETUP/gnome-extensions.txt"
  (( n )) || echo "    none installed"
}

# 6. Fonts and wallpaper install.sh downloaded.
remove_fonts_wallpaper() {
  local d removed=0
  for d in "$HOME/.local/share/fonts/RobotoMono" "$HOME/.local/share/fonts/RobotoMonoNerdFont"; do
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
    [[ -f "$saved" ]] && cmp -s <(sed "s|@HOME@|$HOME|g" "$saved") "$f" || continue
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

header "Undo the dotfiles" \
  "Removes the config links (your own files from before come back), resets the" \
  "desktop look, shortcuts and settings to Ubuntu's, removes the extensions, fonts and" \
  "wallpaper it added, and switches off the reminder and the secret check." \
  "Apps, Flatpaks, system jobs and ~/dotfiles stay; it shows how to remove them."
yes_flag "$@"
ask "Undo the dotfiles for $(id -un)?" || { echo "Nothing changed."; exit 0; }

run_steps \
  "Weekly reminder off|reminder_off" \
  "Config links removed, your own files back|unlink_configs" \
  "Git name and email kept|keep_git_identity" \
  "Desktop look, shortcuts and settings back to Ubuntu's|reset_desktop" \
  "GNOME extensions it installed|remove_extensions" \
  "Fonts and wallpaper it downloaded|remove_fonts_wallpaper" \
  "Copies in Flatpak apps and login apps|remove_copies" \
  "Secret check off, saved choices deleted|safety_off"

summary; ok=$?
printf '\n%sStill there, if you want them gone too%s\n' "$C_B" "$C_N"
note "Log out and back in, so GNOME drops the removed extensions and fonts"
note "Flatpak apps:  flatpak uninstall \$(cat ~/dotfiles/setup/flatpaks.txt)"
note "VS Code theme: code --uninstall-extension \$(cat ~/dotfiles/setup/vscode-extensions.txt)"
note "Apps from install-apps.sh: see ~/dotfiles/docs/apps.md for each package; sudo apt remove <package>"
note "Weekly updates and monthly clean-up: sudo rm /etc/cron.weekly/system-update /etc/cron.monthly/system-cleanup"
note "Firewall: sudo ufw disable"
note "The dotfiles folder: rm -rf ~/dotfiles"
exit "$ok"
