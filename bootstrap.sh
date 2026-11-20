#!/usr/bin/env bash
# Set up a freshly installed Ubuntu with these dotfiles, in one command:
#
#   bash <(wget -qO- https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/bootstrap.sh)
#
# (wget, because a fresh Ubuntu has it but not curl.) It installs git, gum and gh,
# downloads the dotfiles to ~/dotfiles (no GitHub sign-in needed: the repo is public)
# and starts fresh-install.sh. Options are passed on, e.g. ... bootstrap.sh) --yes
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

if [[ -d "$DIR/.git" ]]; then
  echo "Updating $DIR"
  git -C "$DIR" pull --ff-only
else
  echo "Downloading the dotfiles to $DIR"
  git clone --quiet "$REPO" "$DIR"
fi
exec "$DIR/fresh-install.sh" "$@"
