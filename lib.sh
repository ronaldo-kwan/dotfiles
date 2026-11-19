#!/usr/bin/env bash
# Shared helpers for install.sh, install-apps.sh, fresh-install.sh, check.sh and
# post-upgrade.sh. Source it after setting -uo pipefail:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck disable=SC2034  # DOTFILES, SETUP and FAILED are used by the scripts that source this

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DOTFILES/setup"
FAILED=()
# Terminal tools from apt (installed by fresh-install.sh, checked by check.sh)
TOOLS=(git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak)
# Stow packages: folders here whose files are linked into your home folder
PACKAGES=(bash git starship ghostty btop lazygit terminal-default vscode claude systemd)

say()  { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
skip() { printf '    skipped: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- Questions ----------------------------------------------------------------------
# YES_ALL=1 answers Yes to every question, so a run needs no one at the keyboard.
# It's chosen once at the start (choose_answer_mode, or -y / --yes / --all) and passed
# on to scripts started from that one, so they don't ask again.
YES_ALL="${YES_ALL:-}"

# yes_flag "$@": -y, --yes or --all among the arguments means Yes to everything.
yes_flag() {
  local a
  for a in "$@"; do
    case "$a" in -y|--yes|--all) YES_ALL=1; export YES_ALL ;; esac
  done
}

# choose_answer_mode: the one question at the start (skipped if already chosen).
choose_answer_mode() {
  [[ -n "$YES_ALL" ]] && return 0
  local a
  echo
  read -rp "Answer Yes to every question, so the rest runs by itself? [Y/n] (n = ask each one) " a
  if [[ "$a" =~ ^[Nn]$ ]]; then YES_ALL=0; else YES_ALL=1; fi
  export YES_ALL
}

# ask "Question?": true unless the answer is n/N (Enter means yes). With YES_ALL=1
# it shows the question with the answer and doesn't wait.
ask() {
  if [[ "$YES_ALL" == 1 ]]; then printf '    %s [Y/n] y (yes to all)\n' "$1"; return 0; fi
  local a; read -rp "    $1 [Y/n] " a; [[ ! "$a" =~ ^[Nn]$ ]]
}

# keep_sudo: ask for the password once, then keep sudo signed in until this script
# ends, so a long run (big downloads) doesn't stop halfway to ask again.
keep_sudo() {
  sudo -v || return 1
  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do sudo -n true; sleep 50; done ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# installed <package>: is this apt package installed?
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# run_step "title" command...: run one step in a subshell with "stop on error".
# If it fails, say so and add the title to FAILED; later steps still run.
run_step() {
  local title="$1"; shift
  say "$title"
  ( set -e; "$@" )
  local rc=$?
  if (( rc != 0 )); then
    printf '    \033[1;31mfailed\033[0m (exit code %s)\n' "$rc"
    FAILED+=("$title")
  fi
  return 0
}

# show_failures: list FAILED steps, or say "Done."; returns 1 if anything failed.
show_failures() {
  if (( ${#FAILED[@]} > 0 )); then
    say "Finished with problems. These steps failed (see messages above):"
    printf '  - %s\n' "${FAILED[@]}"
    return 1
  fi
  say "Done."
}

# Is the JetBrainsMono Nerd Font installed? (Not `fc-list | grep -q`: with pipefail
# that fails when grep stops reading fc-list's long output early.)
has_nerd_font() { [[ "$(fc-list 2>/dev/null)" == *"JetBrainsMono Nerd Font"* ]]; }

# fill_user <file>: print a system/ script with @USER@ replaced by this user's name.
fill_user() { sed "s/@USER@/$(id -un)/g" "$1"; }
