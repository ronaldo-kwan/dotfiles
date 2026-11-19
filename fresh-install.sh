#!/usr/bin/env bash
# Set up a freshly installed Ubuntu from these dotfiles, in the right order:
#
#   1. Update the system            (apt full-upgrade)
#   2. Update firmware              (optional, only on charger power)
#   3. Install the terminal tools   (starship, eza, ghostty, ...) and Flathub
#   4. install.sh                   (configs, fonts, Flatpak apps, extensions, settings)
#   5. install-apps.sh              (Chrome, VS Code, Steam, NVIDIA driver, weekly updates, ...)
#   6. install.sh again             (VS Code extensions and Obsidian, now that the apps exist)
#   7. Restart
#
# Before running it (see README, "Setting up a new computer"):
#   sudo apt install git gh && gh auth login && gh repo clone dotfiles ~/dotfiles
#
# Every question defaults to Yes: press Enter to go on, type n to skip.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS=(git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak)
FAILED=()

say()  { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ask()  { local a; read -rp "    $1 [Y/n] " a; [[ ! "$a" =~ ^[Nn]$ ]]; }
step() { # step "title" command...: run a step, keep going if it fails
  local title="$1"; shift
  say "$title"
  "$@"; local rc=$?
  (( rc == 0 )) || { printf '    \033[1;31mfailed\033[0m (exit code %s)\n' "$rc"; FAILED+=("$title"); }
}
# Plugged in? A computer without a battery (a desktop) always counts as plugged in.
on_charger() {
  compgen -G '/sys/class/power_supply/BAT*' >/dev/null || return 0
  cat /sys/class/power_supply/*/online 2>/dev/null | grep -qx 1
}

cat <<EOF
This sets up this computer from $DOTFILES:
  1. update the system      2. update firmware (optional)    3. install terminal tools
  4. install.sh             5. install-apps.sh               6. install.sh again
It uses sudo, takes a while (downloads), and ends with a restart.
EOF
ask "Start?" || { echo "Nothing changed."; exit 0; }
sudo -v || exit 1

# 1. Update the system --------------------------------------------------------------
update_system() {
  sudo apt-get update && sudo apt-get -y full-upgrade
}
step "1. Updating the system" update_system

# 2. Firmware (BIOS, SSD, devices) ---------------------------------------------------
update_firmware() {
  command -v fwupdmgr >/dev/null || { echo "    skipped: fwupdmgr isn't installed"; return 0; }
  if ! on_charger; then
    echo "    skipped: plug in the charger first (a firmware update must not lose power)."
    echo "    Later: fwupdmgr refresh --force && fwupdmgr update"
    return 0
  fi
  ask "Check for and install firmware updates (BIOS, SSD, devices)? Keep the charger in." || return 0
  sudo fwupdmgr refresh --force >/dev/null 2>&1
  sudo fwupdmgr update --assume-yes --no-reboot-check
  local rc=$?
  (( rc == 0 || rc == 2 )) || return "$rc"   # 2 means "nothing to update"
}
step "2. Firmware updates" update_firmware

# 3. Terminal tools and Flathub ---------------------------------------------------------
install_tools() {
  sudo apt-get install -y "${TOOLS[@]}" || return 1
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}
step "3. Installing terminal tools and Flathub" install_tools

# 4-6. The dotfiles scripts -------------------------------------------------------------
step "4. install.sh (configs, fonts, Flatpak apps, extensions, settings)" "$DOTFILES/install.sh" --yes
step "5. install-apps.sh (apps, NVIDIA driver, weekly updates)" "$DOTFILES/install-apps.sh"
step "6. install.sh again (VS Code extensions, Obsidian)" "$DOTFILES/install.sh" --yes

# 7. Done -----------------------------------------------------------------------------
if (( ${#FAILED[@]} > 0 )); then
  say "Finished with problems. These steps failed (see messages above):"
  printf '  - %s\n' "${FAILED[@]}"
  echo "  Fix the cause and run ~/dotfiles/fresh-install.sh again; finished parts are skipped."
else
  say "All done."
fi
cat <<'EOF'

After the restart:
  - If a blue "MOK management" screen appears (NVIDIA driver with Secure Boot):
    Enroll MOK -> Continue -> Yes -> type the password you chose -> Reboot.
  - Check the NVIDIA card works: nvidia-smi
  - Sign in to your apps (Steam, browsers, Discord, Bitwarden).
  - Open Backups, connect Google Drive, and turn on "Back Up Automatically".
EOF
ask "Restart now?" && sudo reboot
