#!/usr/bin/env bash
# Health check: is this computer still set up the way ~/dotfiles describes?
# On its own it changes nothing and never commits. Also: dot check / dotcheck.
#
#   dot check            full check (links, tools, apps, firewall, Flatpaks, extensions,
#                        signing, backups, scheduled jobs, Obsidian, unsaved changes)
#   dot check --fix      the same, then offers to fix each problem it found, in order
#                        (asks before each fix; Enter = yes)
#   check.sh --notify    only "anything to save? backups off?", as a desktop
#                        notification (used by the weekly reminder)
#
# Exits with 1 if anything needs attention.

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # have, installed, TOOLS, PACKAGES, DOTFILES, SETUP

MODE=full
case "${1:-}" in --notify) MODE=notify ;; --fix) MODE=fix ;; esac
VAULT="$HOME/Documents/Obsidian Vault"
PROBLEMS=0
FIXES=" "          # fix keys collected by bad(), in no particular order
MISSING_TOOLS=()
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_N" "$*"; }
# bad "message" [fix]: a ✘ line; the fix (a key below) is shown and collected for --fix.
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
    backups) echo "open Backups, turn on Back Up Automatically, then dot save" ;;
    save)    echo "dot save" ;;
    push)    echo "dot push" ;;
    pull)    echo "dot pull" ;;
    notes)   echo "dot notes" ;;
    restart) echo "restart; with Secure Boot, enrol the key on the blue MOK screen" ;;
    ghkeys)  echo "gh auth refresh -h github.com --remove-scopes $GH_KEY_SCOPES" ;;
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
if [[ "$MODE" == notify ]]; then
  msgs=()
  mapfile -t stale < <(stale_snapshots)
  (( ${#stale[@]} )) && msgs+=("Settings changed since your last save (${#stale[@]} files). Run: dot save")
  find_unsaved
  (( ${#unsaved[@]} )) && msgs+=("Ubuntu apps not in apt-packages.txt: ${unsaved[*]}")
  (( ${#unsaved_other[@]} )) && msgs+=("Apps from other sources not saved: ${unsaved_other[*]} (add to install-apps.sh, or -name)")
  [[ "$(backups_state)" == off ]] && msgs+=("Automatic backups are off. Open Backups and turn on Back Up Automatically.")
  for d in "$DOTFILES" "$VAULT"; do
    [[ -d "$d/.git" ]] || continue
    s="$(repo_state "$d" | paste -sd' ' | sed 's/ / and /')"
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
  header "Health check" "Is this computer still set up the way ~/dotfiles says? Changes nothing."
fi
section "Config links (stow)"
broken=()
mapfile -t pkgs < <(chosen_packages)
for pkg in "${pkgs[@]}"; do
  while IFS= read -r -d '' src; do
    rel="${src#"$DOTFILES/$pkg/"}"
    # shellcheck disable=SC2088  # "~/" is only shown, not used as a path
    [[ "$(readlink -f "$HOME/$rel")" == "$(readlink -f "$src")" ]] || broken+=("~/$rel")
  done < <(find "$DOTFILES/$pkg" -type f -print0)
done
list_missing "all config files linked (${pkgs[*]})" install "${broken[@]}"

section "Terminal tools"
for t in "${TOOLS[@]}"; do installed "$t" || MISSING_TOOLS+=("$t"); done
list_missing "${#TOOLS[@]} tools installed" tools "${MISSING_TOOLS[@]}"
if ! chosen terminal; then info "RobotoMono Nerd Font: not chosen"
elif has_nerd_font; then ok "RobotoMono Nerd Font"; else bad "RobotoMono Nerd Font not installed" install; fi
if ! chosen desktop; then info "Roboto Mono: not chosen"
elif has_roboto_mono; then ok "Roboto Mono"; else bad "Roboto Mono not installed" install; fi

section "Apps and system jobs (install-apps.sh)"
# shellcheck source=install-apps.sh
source "$DOTFILES/install-apps.sh"   # only loads APPS and the check_* functions
for entry in "${APPS[@]}"; do
  IFS='|' read -r name check fn _ <<< "$entry"
  if ! entry_chosen "$fn"; then info "$name: not chosen"; continue; fi
  out="$(is_done "$check" 2>&1; echo "rc=$?")"; rc="${out##*rc=}"
  out="$(printf '%s' "${out%rc=*}" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')"
  if (( rc != 0 )); then bad "$name${out:+: $out}" apps
  elif [[ -n "$out" ]]; then info "$name: $out"   # "not needed", or a hint
  else ok "$name"
  fi
done
if has_nvidia && have nvidia-smi; then
  nvidia-smi >/dev/null 2>&1 && ok "NVIDIA driver running (nvidia-smi)" \
    || bad "NVIDIA driver installed but not running" restart
fi

section "Flatpaks and extensions"
if have flatpak; then
  missing=() n=0
  while read -r a; do
    [[ -z "$a" ]] || ! chosen "flatpak:$a" && continue
    n=$((n + 1)); flatpak info "$a" >/dev/null 2>&1 || missing+=("$a")
  done < "$SETUP/flatpaks.txt"
  (( n )) && list_missing "$n Flatpak apps" install "${missing[@]}"
elif chosen_any flatpak:; then MISSING_TOOLS+=(flatpak); bad "flatpak isn't installed" tools
else info "Flatpak apps: not chosen"; fi
if have gnome-extensions && chosen desktop; then
  enabled="$(gnome-extensions list --enabled 2>/dev/null)"
  missing=(); while read -r u; do [[ -z "$u" || "$u" == \#* ]] || grep -qxF "$u" <<< "$enabled" || missing+=("$u"); done < "$SETUP/gnome-extensions.txt"
  list_missing "GNOME extensions enabled" install "${missing[@]}"
fi
if have code && chosen app:code; then
  have_ext="$(code --list-extensions 2>/dev/null)"
  missing=(); while read -r e; do [[ -z "$e" ]] || grep -qixF "$e" <<< "$have_ext" || missing+=("$e"); done < "$SETUP/vscode-extensions.txt"
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
  s="$(repo_state "$d" | paste -sd' ' | sed 's/ / and /')"
  [[ -z "$s" ]] && ok "${d/#$HOME/\~}: everything committed and pushed" \
    || bad "${d/#$HOME/\~}: $s changes" "$([[ "$d" == "$DOTFILES" ]] && echo push || echo notes)"
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
if [[ "$MODE" != fix ]]; then
  printf '  %sFix them one by one: dot check --fix%s\n' "$C_DIM" "$C_N"; exit 1
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
  ( set -e; "$@" ) && step_end ok || step_end fail
}
add_unsaved() {
  { printf '\n# Added by dot check --fix on %s\n' "$(date +%F)"; printf '%s\n' "${unsaved[@]}"; } >> "$SETUP/apt-packages.txt"
  note "added: ${unsaved[*]} (edit setup/apt-packages.txt to add comments, or -name to keep one off new computers)"
}
open_backups() {
  setsid deja-dup >/dev/null 2>&1 < /dev/null &
  note "Backups is opening: connect Google Drive if asked, turn on Back Up Automatically, then run dot save"
}
export UI_DEPTH="$UI_NESTED"   # the scripts below get their full look

# Pull first, so everything below works on the latest version.
has_fix pull    && fix_step "Changes from GitHub" "Run dot pull?" "$DOTFILES/dot" pull
has_fix tools   && fix_step "Terminal tools" "Install ${MISSING_TOOLS[*]}?" \
                     sudo apt-get install -y "${MISSING_TOOLS[@]}"
has_fix apps    && fix_step "Apps, firewall, scheduled jobs" "Run dot apps?" "$DOTFILES/install-apps.sh"
has_fix install && fix_step "Links, extensions, settings, safety checks" "Run dot install?" "$DOTFILES/install.sh" --yes
has_fix ssh     && fix_step "SSH key and signed commits" "Run dot ssh?" "$DOTFILES/scripts/ssh-setup.sh"
has_fix addapt  && fix_step "Ubuntu apps not saved" "Add ${unsaved[*]} to setup/apt-packages.txt?" add_unsaved
# Apps from other sources can't go in apt-packages.txt (a new computer lacks their source).
has_fix addother && warn "Not added: ${unsaved_other[*]} only come from their makers' own sources. Add each to install-apps.sh with its source (docs/apps.md), or write -name in setup/apt-packages.txt."
has_fix backups && fix_step "Automatic backups" "Open Backups to turn them on?" open_backups
has_fix ghkeys  && fix_step "GitHub CLI permissions" "Remove its permission to add SSH keys (approve in the browser)?" \
                     gh auth refresh -h github.com --remove-scopes "$GH_KEY_SCOPES"
has_fix restart && warn "The NVIDIA driver needs a restart (and with Secure Boot, the blue MOK screen)."
# Save last, after anything above that changed files.
has_fix save    && fix_step "Snapshots" "Refresh them (dot save)?" "$DOTFILES/dot" save
[[ -n "$(repo_state "$DOTFILES")" ]] && fix_step "Save ~/dotfiles to GitHub" "Run dot push?" "$DOTFILES/dot" push
[[ -d "$VAULT/.git" && -n "$(repo_state "$VAULT")" ]] && fix_step "Save your notes to GitHub" "Run dot notes?" "$DOTFILES/dot" notes
summary
printf '\n  %sCheck again: dot check%s\n' "$C_DIM" "$C_N"
