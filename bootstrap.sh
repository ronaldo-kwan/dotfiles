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
