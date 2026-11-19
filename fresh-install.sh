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

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, ask, run_step, show_failures, DOTFILES
# Plugged in? A computer without a battery (a desktop) always counts as plugged in.
on_charger() {
  compgen -G '/sys/class/power_supply/BAT*' >/dev/null || return 0
  cat /sys/class/power_supply/*/online 2>/dev/null | grep -qx 1
}

header "Fresh install" \
  "Sets up this computer from ~/dotfiles, in six steps:" \
  "  1 update the system        2 firmware (on charger only)" \
  "  3 terminal tools           4 configs and desktop (install.sh)" \
  "  5 apps (install-apps.sh)   6 configs again, now the apps exist" \
  "Uses sudo and takes a while. Yes to everything also accepts the" \
  "Microsoft fonts licence (codecs) and restarts at the end."
STEP_TOTAL=6
yes_flag "$@"
choose_answer_mode
ask "Start?" || { echo "Nothing changed."; exit 0; }
keep_sudo || exit 1

# 1. Update the system --------------------------------------------------------------
update_system() {
  quiet "Refreshing package lists" sudo apt-get -o DPkg::Lock::Timeout=300 update
  quiet "Upgrading all packages" sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y full-upgrade
}
run_step "Update the system" update_system

# 2. Firmware (BIOS, SSD, devices) ---------------------------------------------------
update_firmware() {
  command -v fwupdmgr >/dev/null || { skip "fwupdmgr isn't installed"; return 0; }
  if ! on_charger; then
    skip "plug in the charger first (a firmware update must not lose power)"
    note "later: fwupdmgr refresh --force && fwupdmgr update"
    return 0
  fi
  ask "Check for and install firmware updates (BIOS, SSD, devices)? Keep the charger in." \
    || { skip "you chose not to"; return 0; }
  note "checking for firmware updates (shown in full: don't turn the computer off while it installs)"
  sudo fwupdmgr refresh --force >/dev/null 2>&1 || true
  local rc=0
  sudo fwupdmgr update --assume-yes --no-reboot-check || rc=$?
  (( rc == 0 || rc == 2 )) || return "$rc"   # 2 means "nothing to update"
}
run_step "Firmware updates" update_firmware

# 3. Terminal tools and Flathub ---------------------------------------------------------
install_tools() {
  quiet "Installing ${#TOOLS[@]} terminal tools" sudo env DEBIAN_FRONTEND=noninteractive \
    apt-get -o DPkg::Lock::Timeout=300 install -y "${TOOLS[@]}"
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}
run_step "Terminal tools and Flathub" install_tools

# 4-6. The dotfiles scripts -------------------------------------------------------------
run_step "Configs, fonts, Flatpak apps, extensions, settings (install.sh)" "$DOTFILES/install.sh" --yes
run_step "Apps, NVIDIA driver, weekly updates (install-apps.sh)" "$DOTFILES/install-apps.sh"
run_step "VS Code extensions and Obsidian (install.sh again)" "$DOTFILES/install.sh" --yes

# Done -------------------------------------------------------------------------------
summary
printf '\n%sAfter the restart%s\n' "$C_B" "$C_N"
note "Blue \"MOK management\" screen (NVIDIA with Secure Boot): Enroll MOK, Continue, Yes, your password, Reboot"
note "Check the NVIDIA card works: nvidia-smi"
note "Sign in to your apps (Steam, browsers, Discord, Bitwarden)"
note "Open Backups, connect Google Drive, and turn on \"Back Up Automatically\""
note "Then run dotcheck in a new terminal"
echo
if ask "Restart now?"; then
  if [[ "$YES_ALL" == 1 ]]; then
    for n in $(seq 15 -1 1); do
      printf '\r    %sRestarting in %2ss.%s Press Ctrl+C to stay. ' "$C_WARN" "$n" "$C_N"
      sleep 1
    done
    echo
  fi
  sudo reboot
fi
