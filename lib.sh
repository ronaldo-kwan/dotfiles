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

# ask "Question?": true unless the answer is n/N (Enter means yes).
ask() { local a; read -rp "    $1 [Y/n] " a; [[ ! "$a" =~ ^[Nn]$ ]]; }

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
