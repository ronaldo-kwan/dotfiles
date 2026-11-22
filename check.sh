#!/usr/bin/env bash
# Health check: is this computer still set up the way ~/dotfiles describes?
# It changes nothing unless you say yes to a fix, and never commits by itself.
#
#   dot check            full check (links, tools, apps, firewall, Flatpaks, extensions,
#                        signing, backups, scheduled jobs, Obsidian, unsaved changes);
#                        if anything is wrong, asks whether to fix it, then offers each
#                        fix in order (asks before each one; Enter = yes)
#   dot check --fix      the same, without the first question
#   check.sh --notify    only "anything to save? backups off?", as a desktop
#                        notification (used by the weekly reminder)
#
# Exits with 1 if anything needs attention.

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # have, installed, TOOLS, PACKAGES, VAULT, DOTFILES, SETUP
# shellcheck source=install-apps.sh
source "$DOTFILES/install-apps.sh"   # only loads APPS, APP_PACKAGES and the check_* functions

MODE=full
case "${1:-}" in --notify) MODE=notify ;; --fix) MODE=fix ;; esac
PROBLEMS=0
FIXES=" "          # fix keys collected by bad(), in no particular order
MISSING_TOOLS=()
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_N" "$*"; }
# bad "message" [fix]: a ✘ line; the fix (a key below) is shown and collected for the fixes.
bad() {
  local hint=''
  [[ -n "${2:-}" ]] && { hint="$(fix_hint "$2")"; FIXES+="$2 "; }
  printf '  %s✘%s %s%s\n' "$C_ERR" "$C_N" "$1" "${hint:+ $C_DIM→ $hint$C_N}"
  PROBLEMS=$((PROBLEMS + 1))
}
fix_hint() {
  case "$1" in
    tools)   echo "sudo apt install ${MISSING_TOOLS[*]}" ;;
    apps)    echo "dot apps" ;;
    install) echo "dot install" ;;
    ssh)     echo "dot ssh" ;;
    addapt)  echo "add them to setup/apt-packages.txt (or as -name to keep them off new computers)" ;;
    addother) echo "add each to install-apps.sh with its source, like ChatGPT (docs/apps.md); or write -name in setup/apt-packages.txt to keep it off new computers" ;;
    backups) echo "open Backups, turn on Back Up Automatically, then dot push" ;;
    save)    echo "dot push" ;;
    push)    echo "dot push" ;;
    pull)    echo "dot pull" ;;
    restart) echo "restart; with Secure Boot, enrol the key on the blue MOK screen" ;;
    nvidiakernel)
      if [[ -n "$NV_READY" ]]; then echo "Ubuntu has it now: sudo apt update && sudo apt full-upgrade, then restart"
      else echo "Ubuntu hasn't published it yet; meanwhile start ${NV_OLD:-the previous kernel} (boot menu: Advanced options for Ubuntu), later run sudo apt update && sudo apt full-upgrade"; fi ;;
    ghkeys)  echo "gh auth refresh -h github.com --remove-scopes $GH_KEY_SCOPES" ;;
    record)  echo "the fixes ask which ones the dotfiles installed" ;;
  esac
}
# Backups (Déjà Dup): is "Back Up Automatically" on?
backups_state() { # prints on/off, or nothing if Backups isn't installed
  gsettings list-keys org.gnome.DejaDup >/dev/null 2>&1 || return 0
  [[ "$(gsettings get org.gnome.DejaDup periodic)" == true ]] && echo on || echo off
}
info() { printf '  %s–%s %s\n' "$C_DIM" "$C_N" "$*"; }
section() { printf '\n%s%s%s%s\n' "$C_ACC" "$C_B" "$*" "$C_N"; }
# list_missing <description> <items...>: ok if nothing given, else one ✘ line
list_missing() { # list_missing <description> <fix> <items...>
  local what="$1" fix="$2"; shift 2
  if (( $# == 0 )); then ok "$what"; else bad "$what: missing $*" "$fix"; fi
}

# --- Snapshots and unsaved changes (both modes) ------------------------------------
# Added by Ubuntu itself (language support adds dictionaries for your languages).
UBUNTU_AUTO_PACKAGES=('language-pack-*' 'hunspell-*' 'hyphen-*' 'mythes-*' wbritish wamerican)

# unsaved_apt_packages: Ubuntu packages you installed yourself (apt, App Center, a .deb)
# that are still installed but in none of the dotfiles lists, so a new computer
# wouldn't get them. Read from apt's history; Ubuntu's installer is left out.
# A line "-name" in setup/apt-packages.txt marks one as "on purpose, not for new computers".
unsaved_apt_packages() {
  local known manual
  known="$( { printf '%s\n' "${TOOLS[@]}" "${APP_PACKAGES[@]}" "${UBUNTU_AUTO_PACKAGES[@]}"
              sed 's/#.*//' "$SETUP/apt-packages.txt" | awk 'NF{sub(/^-/, "", $1); print $1}'; } )"
  manual="$(apt-mark showmanual 2>/dev/null)"
  { cat /var/log/apt/history.log 2>/dev/null; zcat /var/log/apt/history.log.*.gz 2>/dev/null; } | awk '
    /^Commandline:/ { mine = !/force-unsafe-io|pkgDepCache::AutoInstall|unattended-upgrade/; next }
    /^Install:/ && mine {
      sub(/^Install: /, ""); n = split($0, parts, /\), /)
      for (i = 1; i <= n; i++) if (parts[i] !~ /automatic/) { split(parts[i], w, /[: ]/); print w[1] }
    }' | sort -u | while read -r p; do
      grep -qxF "$p" <<< "$manual" || continue                 # removed, or only a dependency
      local k hit=0
      # shellcheck disable=SC2053  # $k may be a pattern like nvidia-driver-*
      while read -r k; do [[ -n "$k" && "$p" == $k ]] && { hit=1; break; }; done <<< "$known"
      (( hit )) || echo "$p"
    done
  return 0
}

# from_ubuntu <package>: can Ubuntu's own archive install it? Apps that only come from
# their maker's source, a PPA or a downloaded .deb can't go in setup/apt-packages.txt: a
# new computer doesn't have that source. (Ubuntu's sources are the ones apt labels
# o=Ubuntu, so any mirror works.)
UBUNTU_SOURCES=""
from_ubuntu() {
  [[ -n "$UBUNTU_SOURCES" ]] || UBUNTU_SOURCES="$(apt-cache policy 2>/dev/null | awk '
    $2 ~ /^(https?|ftp|file|cdrom|mirror\+[a-z]+):/ { src = $2 " " $3 }
    /^ +release .*o=Ubuntu,/ { print src }')"
  local s
  while read -r s; do
    [[ -n "$s" ]] && grep -qxF "$s" <<< "$UBUNTU_SOURCES" && return 0
  done < <(apt-cache madison "$1" 2>/dev/null | awk -F'|' '{ split($3, a, " "); print a[1] " " a[2] }')
  return 1
}

# Apps you installed that aren't saved: unsaved (from Ubuntu, for setup/apt-packages.txt)
# and unsaved_other (only from a maker's source, a PPA or a .deb: for install-apps.sh).
find_unsaved() {
  local p; unsaved=(); unsaved_other=()
  while read -r p; do
    [[ -n "$p" ]] || continue
    if from_ubuntu "$p"; then unsaved+=("$p"); else unsaved_other+=("$p"); fi
  done < <(unsaved_apt_packages)
}
# Writes fresh snapshots into a temporary copy of setup/ and compares.
stale_snapshots() {
  local tmp; tmp="$(mktemp -d)"
  cp -r "$SETUP" "$tmp/setup"
  bash "$DOTFILES/scripts/snapshot.sh" "$tmp/setup" >/dev/null 2>&1
  diff -rq "$SETUP" "$tmp/setup" 2>/dev/null | sed -E "s|^Files $SETUP/([^ ]+) and .*|\1|; s|^Only in $tmp/setup/?([^:]*): (.*)|\1/\2 (new)|; s|^Only in $SETUP/?([^:]*): (.*)|\1/\2 (gone)|; s|^/||"
  rm -rf "$tmp"
}
# Backups install.sh made when it replaced a file: <name>.orig (yours from before the
# dotfiles), <name>.orig.<date> and <name>.prev (replaced later). Not a problem, just
# listed so they don't pile up unseen. dot uninstall puts the .orig ones back.
dotfiles_backups() {   # prints each backup's path
  local f b
  while IFS= read -r -d '' f; do
    for b in "$HOME/${f#*/}".orig "$HOME/${f#*/}".orig.*; do [[ -e "$b" ]] && echo "$b"; done
  done < <(config_files "${PACKAGES[@]}")
  for b in "$HOME"/.config/{mimeapps.list,monitors.xml}.{orig,prev} \
           "$HOME"/.config/qBittorrent/qBittorrent.conf.{orig,prev} "$HOME"/.config/qBittorrent/themes/*.{orig,prev} \
           "$HOME"/.config/autostart/*.desktop.{orig,prev} "$HOME"/.var/app/*/config/fontconfig/fonts.conf.{orig,prev}; do
    [[ -e "$b" ]] && echo "$b"
  done
  return 0
}
BACKUPS_PILED_UP=5   # the weekly reminder mentions backups from this many on

if [[ "$MODE" == notify ]]; then
  msgs=()
  mapfile -t stale < <(stale_snapshots)
  (( ${#stale[@]} )) && msgs+=("Settings changed since your last save (${#stale[@]} files). Run: dot push")
  find_unsaved
  (( ${#unsaved[@]} )) && msgs+=("Ubuntu apps not in apt-packages.txt: ${unsaved[*]}")
  (( ${#unsaved_other[@]} )) && msgs+=("Apps from other sources not saved: ${unsaved_other[*]} (add to install-apps.sh, or -name)")
  [[ "$(backups_state)" == off ]] && msgs+=("Automatic backups are off. Open Backups and turn on Back Up Automatically.")
  # Once, until answered: dot uninstall --apps can't tell your apps from the dotfiles' ones.
  added_is_legacy && msgs+=("dot uninstall can't tell which apps you had before the dotfiles. Run: dot check")
  # Only once they've piled up: a few backups (your .orig from before) are expected.
  mapfile -t backups < <(dotfiles_backups)
  (( ${#backups[@]} >= BACKUPS_PILED_UP )) && msgs+=("${#backups[@]} backups of files the dotfiles replaced (.orig, .prev). See them: dot check")
  for d in "$DOTFILES" "$VAULT"; do
    [[ -d "$d/.git" ]] || continue
    s="$(repo_state "$d")"
    [[ -n "$s" ]] && msgs+=("${d/#$HOME/\~} has $s changes.")
    n="$(repo_behind "$d")"
    (( n > 0 )) && msgs+=("GitHub has $n new commit$( ((n > 1)) && echo s) for ${d/#$HOME/\~}. Run: dot pull")
  done
  if (( ${#msgs[@]} )); then
    body="$(printf '%s\n' "${msgs[@]}")
Nothing was committed. Details: dot check"
    if have notify-send; then
      notify-send -i emblem-synchronizing "Dotfiles: things to do" "$body"
    fi
    printf '%s\n' "$body"
    exit 1
  fi
  echo "Snapshots up to date, nothing unsaved."
  exit 0
fi

# --- Full check -------------------------------------------------------------------------
if [[ "$MODE" == fix ]]; then
  header "Health check and fix" "Checks this computer against ~/dotfiles, then offers to fix what's wrong."
else
  header "Health check" "Is this computer still set up the way ~/dotfiles says? Asks before fixing anything."
fi
section "Config links (stow)"
broken=()
mapfile -t pkgs < <(chosen_packages)
while IFS= read -r -d '' f; do
  # shellcheck disable=SC2088  # "~/" is only shown, not used as a path
  [[ "$(readlink -f "$HOME/${f#*/}")" == "$(readlink -f "$DOTFILES/$f")" ]] || broken+=("~/${f#*/}")
done < <(config_files "${pkgs[@]}")
list_missing "all config files linked (${pkgs[*]})" install "${broken[@]}"
mapfile -t backups < <(dotfiles_backups)
if (( ${#backups[@]} )); then
  info "${#backups[@]} backup(s) of files the dotfiles replaced; look through them and delete what you don't need:"
  for b in "${backups[@]:0:10}"; do printf '      %s\n' "${b/#$HOME/\~}"; done
  (( ${#backups[@]} > 10 )) && printf '      … and %s more\n' $(( ${#backups[@]} - 10 ))
fi

section "Terminal tools"
for t in "${TOOLS[@]}"; do installed "$t" || MISSING_TOOLS+=("$t"); done
list_missing "${#TOOLS[@]} tools installed" tools "${MISSING_TOOLS[@]}"
# The fonts install.sh downloads: installed, and the pinned version (lib.sh)?
if ! chosen terminal; then info "RobotoMono Nerd Font: not chosen"
elif nerd_font_current; then ok "RobotoMono Nerd Font $NERD_FONT_VERSION"
elif has_nerd_font; then bad "RobotoMono Nerd Font: not the pinned version ($NERD_FONT_VERSION)" install
else bad "RobotoMono Nerd Font not installed" install; fi
if ! chosen desktop; then info "Roboto Mono: not chosen"
elif roboto_mono_current; then ok "Roboto Mono"
elif has_roboto_mono; then bad "Roboto Mono: not the pinned version" install
else bad "Roboto Mono not installed" install; fi
if chosen terminal && have batcat; then
  if bat_theme_ok; then ok "bat: Catppuccin Mocha theme"; else bad "bat doesn't know its Catppuccin theme yet" install; fi
fi

section "Apps and system jobs (install-apps.sh)"
for entry in "${APPS[@]}"; do
  IFS='|' read -r choice name check _ <<< "$entry"
  if ! entry_chosen "$choice"; then info "$name: not chosen"; continue; fi
  out="$(is_done "$check" 2>&1; echo "rc=$?")"; rc="${out##*rc=}"
  out="$(printf '%s' "${out%rc=*}" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')"
  if (( rc != 0 )); then bad "$name${out:+: $out}" apps
  elif [[ -n "$out" ]]; then info "$name: $out"   # "not needed", or a hint
  else ok "$name"
  fi
done
# The NVIDIA driver: running? If not, is it because this kernel has no NVIDIA module?
# (Ubuntu sometimes installs a new kernel days before the NVIDIA module for it.)
nvidia_module_for() { modinfo -k "$1" nvidia >/dev/null 2>&1; }   # <kernel>: does it have one?
if has_nvidia && have nvidia-smi; then
  if nvidia-smi >/dev/null 2>&1; then ok "NVIDIA driver running (nvidia-smi)"
  elif ! nvidia_module_for "$(uname -r)"; then
    NV_KERNEL="$(uname -r)" NV_OLD="" NV_READY=""
    # The newest other installed kernel that has a module: start that one meanwhile.
    while read -r k; do
      [[ "$k" != "$NV_KERNEL" ]] && nvidia_module_for "$k" && { NV_OLD="$k"; break; }
    done < <(ls /boot | sed -n 's/^vmlinuz-//p' | sort -rV)
    # Has Ubuntu published the module for this kernel yet? (the installed driver series,
    # e.g. linux-modules-nvidia-595-open-, with this kernel's version)
    NV_PKG="$(dpkg-query -W -f='${Package}\n' 'linux-modules-nvidia-*' 2>/dev/null \
      | sed -n "s/-${NV_OLD:-none}\$//p" | head -1)"
    if [[ -n "$NV_PKG" ]] && apt-cache policy "$NV_PKG-$NV_KERNEL" 2>/dev/null | grep -q 'Candidate: [0-9]'; then
      NV_READY=1
    fi
    bad "no NVIDIA driver module for this kernel ($NV_KERNEL) yet, so the NVIDIA card isn't used" nvidiakernel
  else
    bad "NVIDIA driver installed but not running" restart
  fi
fi

section "Flatpaks and extensions"
if have flatpak; then
  missing=() n=0
  while read -r a; do
    n=$((n + 1)); flatpak info "$a" >/dev/null 2>&1 || missing+=("$a")
  done < <(chosen_from flatpaks.txt flatpak:)
  (( n )) && list_missing "$n Flatpak apps" install "${missing[@]}"
elif chosen_any flatpak:; then MISSING_TOOLS+=(flatpak); bad "flatpak isn't installed" tools
else info "Flatpak apps: not chosen"; fi
if have gnome-extensions && chosen desktop; then
  enabled="$(gnome-extensions list --enabled 2>/dev/null)"
  missing=(); while read -r u; do grep -qxF "$u" <<< "$enabled" || missing+=("$u"); done < <(list_of gnome-extensions.txt)
  list_missing "GNOME extensions enabled" install "${missing[@]}"
fi
if have code && chosen app:code; then
  have_ext="$(code --list-extensions 2>/dev/null)"
  missing=(); while read -r e; do grep -qixF "$e" <<< "$have_ext" || missing+=("$e"); done < <(list_of vscode-extensions.txt)
  list_missing "VS Code extensions" install "${missing[@]}"
fi

section "Obsidian, safety, backups and reminder"
if ! chosen notes; then info "Obsidian vault: not chosen"
elif [[ -d "$VAULT/.git" ]]; then ok "Obsidian vault: ${VAULT/#$HOME/\~}"
else bad "Obsidian vault not cloned" install; fi
for d in "$DOTFILES" "$VAULT"; do
  [[ -d "$d/.git" ]] && chosen safety || continue
  hp="$(git -C "$d" config core.hooksPath)"
  [[ -n "$hp" && -x "$(cd "$d" && readlink -f "$hp")/pre-commit" ]] \
    && ok "secret check before commits: ${d/#$HOME/\~}" \
    || bad "secret check not switched on for ${d/#$HOME/\~}" install
done
if [[ -n "$(git config --get user.email 2>/dev/null)" ]]; then ok "git name and email set ($(git config --get user.name))"
else bad "git doesn't know your name and email" install; fi
if ! chosen safety; then :
elif [[ -f "$HOME/.config/git/signing.gitconfig" && -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  ok "commits signed with this computer's SSH key"
else bad "commits aren't signed" ssh; fi
if have gh && gh auth status >/dev/null 2>&1; then
  if gh_key_admin; then bad "the GitHub CLI can still add SSH keys to your account" ghkeys
  else ok "the GitHub CLI can't add SSH keys to your account"; fi
fi
case "$(backups_state)" in
  on)  ok "automatic backups (every $(gsettings get org.gnome.DejaDup periodic-period) days)" ;;
  off) bad "automatic backups are off" backups ;;
esac
if have systemctl && chosen safety; then
  systemctl --user is-enabled dotfiles-reminder.timer >/dev/null 2>&1 \
    && ok "weekly reminder to save settings (dotfiles-reminder.timer)" \
    || bad "weekly reminder not switched on" install
fi

# Set up before install.sh kept a record of what it added: dot uninstall --apps can't tell
# your own apps from the dotfiles' ones, so it would offer to remove them all.
if added_is_legacy; then
  bad "dot uninstall can't tell which apps you had before the dotfiles (set up before it kept track)" record
fi

section "Saved settings"
find_unsaved
if (( ${#unsaved_other[@]} )); then
  bad "Apps from their makers' own sources that a new computer wouldn't get: ${unsaved_other[*]}" addother
fi
if (( ${#unsaved[@]} )); then
  bad "Ubuntu apps you installed that a new computer wouldn't get: ${unsaved[*]}" addapt
else ok "every Ubuntu app you installed is in setup/apt-packages.txt"; fi
mapfile -t stale < <(stale_snapshots)
if (( ${#stale[@]} )); then
  bad "snapshots out of date: $(printf '%s, ' "${stale[@]}" | sed 's/, $//')" save
else ok "snapshots match this computer"; fi
for d in "$DOTFILES" "$VAULT"; do
  [[ -d "$d/.git" ]] || continue
  s="$(repo_state "$d")"
  [[ -z "$s" ]] && ok "${d/#$HOME/\~}: everything committed and pushed" \
    || bad "${d/#$HOME/\~}: $s changes" push
  n="$(repo_behind "$d")"
  if (( n > 0 )); then bad "${d/#$HOME/\~}: GitHub has $n new commit$( ((n > 1)) && echo s) from another computer" pull
  else ok "${d/#$HOME/\~}: nothing new on GitHub"; fi
done

echo
if (( PROBLEMS == 0 )); then
  printf '%s%s✔ All good.%s\n' "$C_OK" "$C_B" "$C_N"; exit 0
fi
things="things need"; (( PROBLEMS == 1 )) && things="thing needs"
printf '%s%s✘ %s %s attention.%s\n' "$C_ERR" "$C_B" "$PROBLEMS" "$things" "$C_N"
# Asks only with someone at the keyboard (the reminder and GitHub's checks just get exit 1),
# and not after "yes to everything" in a script that ran this one (post-upgrade.sh --yes).
if [[ "$MODE" != fix ]]; then
  if [[ ! -t 0 || ! -t 1 || "$YES_ALL" == 1 ]] || ! ask "Fix them one by one (asks before each)?"; then
    printf '  %sFix them later: dot check%s\n' "$C_DIM" "$C_N"; exit 1
  fi
fi

# --- Fix ---------------------------------------------------------------------------------
# In this order: tools before scripts that need them, apps before install.sh (VS Code
# extensions, Obsidian), and saving to GitHub last, after anything that changed files.
has_fix() { [[ "$FIXES" == *" $1 "* ]]; }
# fix_step "title" "question" command...: one fix as its own step; answering n skips it.
fix_step() {
  local title="$1" q="$2"; shift 2
  step_begin "$title"
  if ! ask "$q"; then step_end skip "you chose not to"; return; fi
  # Not `( set -e; ... ) && ...`: after && bash ignores set -e inside the ( ), so a fix
  # that failed halfway would carry on and could still show ✔. Like run_step in lib.sh.
  ( set -e; "$@" )
  local rc=$?
  if (( rc == 0 )); then step_end ok; else step_end fail "exit code $rc"; fi
}
add_unsaved() {
  { printf '\n# Added by dot check on %s\n' "$(date +%F)"; printf '%s\n' "${unsaved[@]}"; } >> "$SETUP/apt-packages.txt"
  note "added: ${unsaved[*]} (edit setup/apt-packages.txt to add comments, or -name to keep one off new computers)"
}
# adopt_record: you say which apps, packages, extensions and changes the dotfiles made, so
# dot uninstall --apps offers only those (the record replaces "legacy").
adopt_record() {
  local items=() keep=() picked i opts=()
  mapfile -t items < <(added_candidates)
  if (( ${#items[@]} == 0 )); then added_write; note "nothing from the dotfiles found; recorded as none"; return 0; fi
  if ui_gum; then
    for i in "${!items[@]}"; do opts+=("${items[i]#*|}|$i"); done
    picked="$(gum choose --no-limit --selected='*' --label-delimiter='|' --height $(( ${#opts[@]} + 4 )) \
      --header $'Which of these did the dotfiles install or change? Space unticks what you had before them.\n(dot uninstall --apps then offers only the ticked ones.)' \
      "${opts[@]}")" || return 1
    for i in $picked; do keep+=("${items[i]%%|*}"); done
  else
    note "For each: Enter = the dotfiles added it, n = you had it before them"
    for i in "${!items[@]}"; do
      ask "Did the dotfiles add ${items[i]#*|}?" && keep+=("${items[i]%%|*}")
    done
  fi
  added_write ${keep[@]+"${keep[@]}"}
  note "recorded ${#keep[@]} of ${#items[@]}: dot uninstall --apps offers only those"
}
open_backups() {
  setsid deja-dup >/dev/null 2>&1 < /dev/null &
  note "Backups is opening: connect Google Drive if asked, turn on Back Up Automatically, then run dot push"
}
export UI_DEPTH="$UI_NESTED"   # the scripts below get their full look

# Pull first, so everything below works on the latest version.
has_fix pull    && fix_step "Changes from GitHub" "Run dot pull?" "$DOTFILES/dot" pull
has_fix tools   && fix_step "Terminal tools" "Install ${MISSING_TOOLS[*]}?" \
                     apt_get install -y "${MISSING_TOOLS[@]}"
has_fix apps    && fix_step "Apps, firewall, scheduled jobs" "Run dot apps?" "$DOTFILES/install-apps.sh"
has_fix install && fix_step "Links, extensions, settings, safety checks" "Run dot install?" "$DOTFILES/install.sh" --yes
has_fix ssh     && fix_step "SSH key and signed commits" "Run dot ssh?" "$DOTFILES/scripts/ssh-setup.sh"
has_fix addapt  && fix_step "Ubuntu apps not saved" "Add ${unsaved[*]} to setup/apt-packages.txt?" add_unsaved
# Apps from other sources can't go in apt-packages.txt (a new computer lacks their source).
has_fix addother && warn "Not added: ${unsaved_other[*]} only come from their makers' own sources. Add each to install-apps.sh with its source (docs/apps.md), or write -name in setup/apt-packages.txt."
has_fix record  && fix_step "What the dotfiles added" "Say which apps the dotfiles installed (so uninstall keeps yours)?" adopt_record
has_fix backups && fix_step "Automatic backups" "Open Backups to turn them on?" open_backups
has_fix ghkeys  && fix_step "GitHub CLI permissions" "Remove its permission to add SSH keys (approve in the browser)?" \
                     gh auth refresh -h github.com --remove-scopes "$GH_KEY_SCOPES"
has_fix restart && warn "The NVIDIA driver needs a restart (and with Secure Boot, the blue MOK screen)."
has_fix nvidiakernel && warn "NVIDIA: $(fix_hint nvidiakernel)"
# Save last, after anything above that changed files. dot push refreshes the snapshots
# and saves your notes too.
if has_fix save || [[ -n "$(repo_state "$DOTFILES")" ]] || [[ -d "$VAULT/.git" && -n "$(repo_state "$VAULT")" ]]; then
  fix_step "Save to GitHub" "Refresh the snapshots and save to GitHub (dot push)?" "$DOTFILES/dot" push --yes
fi
summary
printf '\n  %sCheck again: dot check%s\n' "$C_DIM" "$C_N"
