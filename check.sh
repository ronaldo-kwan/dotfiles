#!/usr/bin/env bash
# Health check: is this computer still set up the way ~/dotfiles describes?
# Read-only: it changes nothing and never commits. Also available as `dotcheck`.
#
#   ~/dotfiles/check.sh            full check (links, tools, apps, Flatpaks, extensions,
#                                  scheduled jobs, Obsidian, snapshots, unsaved changes)
#   ~/dotfiles/check.sh --notify   only "are snapshots out of date / changes not saved?",
#                                  as a desktop notification (used by the weekly reminder)
#
# Exits with 1 if anything needs attention.

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # have, installed, TOOLS, PACKAGES, DOTFILES, SETUP

MODE=full; [[ "${1:-}" == "--notify" ]] && MODE=notify
VAULT="$HOME/Documents/Obsidian Vault"
PROBLEMS=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; PROBLEMS=$((PROBLEMS + 1)); }
info() { printf '  \033[2m–\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;35m%s\033[0m\n' "$*"; }
# list_missing <description> <items...>: ok if nothing given, else one ✘ line
list_missing() {
  local what="$1"; shift
  if (( $# == 0 )); then ok "$what"; else bad "$what: missing $*"; fi
}

# --- Snapshots and unsaved changes (both modes) ------------------------------------
# Writes fresh snapshots into a temporary copy of setup/ and compares.
stale_snapshots() {
  local tmp; tmp="$(mktemp -d)"
  cp -r "$SETUP" "$tmp/setup"
  bash "$DOTFILES/scripts/snapshot.sh" "$tmp/setup" >/dev/null 2>&1
  diff -rq "$SETUP" "$tmp/setup" 2>/dev/null | sed -E "s|^Files $SETUP/([^ ]+) and .*|\1|; s|^Only in $tmp/setup/?([^:]*): (.*)|\1/\2 (new)|; s|^Only in $SETUP/?([^:]*): (.*)|\1/\2 (gone)|; s|^/||"
  rm -rf "$tmp"
}
repo_state() { # repo_state <dir>: prints "uncommitted" and/or "unpushed"
  local d="$1"
  [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]] && echo uncommitted
  [[ -n "$(git -C "$d" log --oneline '@{u}..' 2>/dev/null)" ]] && echo unpushed
  return 0
}

if [[ "$MODE" == notify ]]; then
  msgs=()
  mapfile -t stale < <(stale_snapshots)
  (( ${#stale[@]} )) && msgs+=("Settings changed since your last dotsave (${#stale[@]} files). Run: dotsave")
  for d in "$DOTFILES" "$VAULT"; do
    [[ -d "$d/.git" ]] || continue
    s="$(repo_state "$d" | paste -sd' ' | sed 's/ / and /')"
    [[ -n "$s" ]] && msgs+=("${d/#$HOME/\~} has $s changes.")
  done
  if (( ${#msgs[@]} )); then
    body="$(printf '%s\n' "${msgs[@]}")
Nothing was committed. Details: dotcheck"
    if have notify-send; then
      notify-send -i emblem-synchronizing "Dotfiles: things to save" "$body"
    fi
    printf '%s\n' "$body"
    exit 1
  fi
  echo "Snapshots up to date, nothing unsaved."
  exit 0
fi

# --- Full check -------------------------------------------------------------------------
section "Config links (stow)"
broken=()
for pkg in "${PACKAGES[@]}"; do
  while IFS= read -r -d '' src; do
    rel="${src#"$DOTFILES/$pkg/"}"
    # shellcheck disable=SC2088  # "~/" is only shown, not used as a path
    [[ "$(readlink -f "$HOME/$rel")" == "$(readlink -f "$src")" ]] || broken+=("~/$rel")
  done < <(find "$DOTFILES/$pkg" -type f -print0)
done
list_missing "all config files linked (${PACKAGES[*]})" "${broken[@]}"

section "Terminal tools"
missing=(); for t in "${TOOLS[@]}"; do installed "$t" || missing+=("$t"); done
list_missing "${#TOOLS[@]} tools installed" "${missing[@]}"
has_nerd_font && ok "JetBrainsMono Nerd Font" || bad "JetBrainsMono Nerd Font not installed (run install.sh)"

section "Apps and system jobs (install-apps.sh)"
# shellcheck source=install-apps.sh
source "$DOTFILES/install-apps.sh"   # only loads APPS and the check_* functions
for entry in "${APPS[@]}"; do
  IFS='|' read -r name check _ <<< "$entry"
  out="$(is_done "$check" 2>&1; echo "rc=$?")"; rc="${out##*rc=}"
  out="$(printf '%s' "${out%rc=*}" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')"
  if (( rc != 0 )); then bad "$name${out:+: $out} (run install-apps.sh)"
  elif [[ -n "$out" ]]; then info "$name: $out"   # "not needed", or a hint
  else ok "$name"
  fi
done
if has_nvidia && have nvidia-smi; then
  nvidia-smi >/dev/null 2>&1 && ok "NVIDIA driver running (nvidia-smi)" \
    || bad "NVIDIA driver installed but not running (Secure Boot key not enrolled? restart?)"
fi

section "Flatpaks and extensions"
if have flatpak; then
  missing=(); while read -r a; do [[ -z "$a" ]] || flatpak info "$a" >/dev/null 2>&1 || missing+=("$a"); done < "$SETUP/flatpaks.txt"
  list_missing "$(grep -c . "$SETUP/flatpaks.txt") Flatpak apps" "${missing[@]}"
else bad "flatpak isn't installed"; fi
if have gnome-extensions; then
  enabled="$(gnome-extensions list --enabled 2>/dev/null)"
  missing=(); while read -r u; do [[ -z "$u" || "$u" == \#* ]] || grep -qxF "$u" <<< "$enabled" || missing+=("$u"); done < "$SETUP/gnome-extensions.txt"
  list_missing "GNOME extensions enabled" "${missing[@]}"
fi
if have code; then
  have_ext="$(code --list-extensions 2>/dev/null)"
  missing=(); while read -r e; do [[ -z "$e" ]] || grep -qixF "$e" <<< "$have_ext" || missing+=("$e"); done < "$SETUP/vscode-extensions.txt"
  list_missing "VS Code extensions" "${missing[@]}"
fi

section "Obsidian, safety checks and reminder"
if [[ -d "$VAULT/.git" ]]; then ok "Obsidian vault: ${VAULT/#$HOME/\~}"
else bad "Obsidian vault not cloned (run install.sh)"; fi
for d in "$DOTFILES" "$VAULT"; do
  [[ -d "$d/.git" ]] || continue
  hp="$(git -C "$d" config core.hooksPath)"
  [[ -n "$hp" && -x "$(cd "$d" && readlink -f "$hp")/pre-commit" ]] \
    && ok "secret check before commits: ${d/#$HOME/\~}" \
    || bad "secret check not switched on for ${d/#$HOME/\~} (run install.sh)"
done
if have systemctl; then
  systemctl --user is-enabled dotfiles-reminder.timer >/dev/null 2>&1 \
    && ok "weekly reminder to save settings (dotfiles-reminder.timer)" \
    || bad "weekly reminder not switched on (run install.sh)"
fi

section "Saved settings"
mapfile -t stale < <(stale_snapshots)
if (( ${#stale[@]} )); then
  bad "snapshots out of date, run dotsave: $(printf '%s, ' "${stale[@]}" | sed 's/, $//')"
else ok "snapshots match this computer"; fi
for d in "$DOTFILES" "$VAULT"; do
  [[ -d "$d/.git" ]] || continue
  s="$(repo_state "$d" | paste -sd' ' | sed 's/ / and /')"
  [[ -z "$s" ]] && ok "${d/#$HOME/\~}: everything committed and pushed" || bad "${d/#$HOME/\~}: $s changes"
done

echo
if (( PROBLEMS )); then
  printf '\033[1;31m%s thing(s) need attention.\033[0m\n' "$PROBLEMS"; exit 1
fi
printf '\033[1;32mAll good.\033[0m\n'
