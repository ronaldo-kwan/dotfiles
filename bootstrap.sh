#!/usr/bin/env bash
# Set up a freshly installed Ubuntu with these dotfiles, in one command:
#
#   bash <(wget -qO- https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/bootstrap.sh)
#
# (wget, because a fresh Ubuntu has it but not curl.) It installs git, gum and gh,
# downloads the dotfiles to ~/dotfiles (no GitHub sign-in needed: the repo is public)
# and starts fresh-install.sh. Options are passed on, e.g. ... bootstrap.sh) --yes
#
# The website (site/) adds what you picked in front of the command:
#   DOTFILES_CHOICES='terminal desktop app:chrome ...'   what to set up (default: everything)
#   DOTFILES_SKIP='claude-md app:steam'                  or: everything except these
#   DOTFILES_GIT_NAME='...' DOTFILES_GIT_EMAIL='...'      your name and email for git
#
# Using your own fork? Point it there:
#   DOTFILES_REPO=https://github.com/YOU/dotfiles.git bash <(wget -qO- https://raw.githubusercontent.com/YOU/dotfiles/main/bootstrap.sh)

set -euo pipefail

# Is this a system these dotfiles are made for? Ubuntu 26.04 with GNOME carries on without
# a word. Another Ubuntu version, an Ubuntu-based system (Mint, Pop!_OS) or another desktop
# says why and asks first (Enter = no; --yes carries on). Anything else stops before
# changing anything. OS_RELEASE_FILE is for tests. (A copy of check_system in lib.sh.)
check_system() {
  local id like ver name problems=() a
  # shellcheck source=/dev/null
  IFS='|' read -r id like ver name < <(. "${OS_RELEASE_FILE:-/etc/os-release}" 2>/dev/null
    echo "${ID:-}|${ID_LIKE:-}|${VERSION_ID:-}|${PRETTY_NAME:-this system}")
  if [[ "$id" != ubuntu && " $like " != *" ubuntu "* ]]; then
    printf '\n✘ These dotfiles are for Ubuntu 26.04 with GNOME; this is %s.\n  Nothing was changed.\n' "$name"
    exit 1
  fi
  [[ "$id" != ubuntu ]] && problems+=("$name is based on Ubuntu, but these dotfiles are made for Ubuntu 26.04 itself.")
  [[ "$id" == ubuntu && "$ver" != 26.04 ]] && problems+=("This is Ubuntu $ver; these dotfiles are made and tested for 26.04. App sources and GNOME extensions may not work.")
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "${XDG_CURRENT_DESKTOP^^}" != *GNOME* ]]; then
    problems+=("The desktop is $XDG_CURRENT_DESKTOP, not GNOME: the desktop look, extensions and dock won't apply.")
  elif [[ -z "${XDG_CURRENT_DESKTOP:-}" ]] && ! command -v gnome-shell >/dev/null 2>&1; then
    problems+=("GNOME isn't installed: the desktop look, extensions and dock won't apply.")
  fi
  (( ${#problems[@]} )) || return 0
  echo
  for a in "${problems[@]}"; do printf '! %s\n' "$a"; done
  for a in "$@"; do [[ "$a" == -y || "$a" == --yes || "$a" == --all ]] && { echo "  Carrying on (--yes)."; return 0; }; done
  a=""; if [[ -t 0 ]]; then read -rp "Carry on anyway? [y/N] " a || true; fi
  [[ "$a" =~ ^[Yy] ]] || { echo "Nothing was changed."; exit 0; }
}
check_system "$@"
export DOTFILES_SYSTEM_CHECKED=1   # fresh-install.sh doesn't ask again

REPO="${DOTFILES_REPO:-https://github.com/ronaldo-kwan/dotfiles.git}"
DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

printf '\n\e[1mSetting up this computer from %s\e[0m\n' "$REPO"
echo "First: git, gum (menus) and gh (GitHub, used later). Asks for your password."
# A failed refresh (for example a wrong clock) isn't fatal: the installer's package
# lists still work for these, and fresh-install.sh fixes the clock and updates fully.
sudo apt-get update -qq || echo "  (couldn't refresh the package lists; carrying on)"
sudo apt-get install -y -qq git gum gh
# After an automated install (setup/autoinstall.yaml), this ran from a one-time step at
# the first login. It's started now, so remove that step.
sudo rm -f /etc/xdg/autostart/dotfiles-setup.desktop /usr/local/bin/dotfiles-first-login /etc/dotfiles-choices

# Remember what was picked on the website, so later runs (dot install, dot check) follow it.
if [[ -n "${DOTFILES_CHOICES:-}${DOTFILES_SKIP:-}" ]]; then
  mkdir -p "$HOME/.config/dotfiles"
  { echo "# What to set up, picked on the dotfiles website (-name = skipped). Delete for everything."
    for c in ${DOTFILES_CHOICES:-}; do echo "$c"; done
    for c in ${DOTFILES_SKIP:-}; do echo "-$c"; done; } > "$HOME/.config/dotfiles/choices"
  echo "Your choices are saved in ~/.config/dotfiles/choices"
fi

if [[ -d "$DIR/.git" ]]; then
  echo "Updating $DIR"
  git -C "$DIR" pull --ff-only
else
  echo "Downloading the dotfiles to $DIR"
  git clone --quiet "$REPO" "$DIR"
fi
exec "$DIR/fresh-install.sh" "$@"
