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
#   bash <(wget -qO- https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/bootstrap.sh)
# (which installs git, gum and gh, downloads ~/dotfiles and starts this script)
#
# One question at the start: Yes to everything (runs by itself), or choose as it goes.
# With gum installed, questions are arrow-key menus and the steps stay pinned on screen.
#
# DRY_RUN=1 ~/dotfiles/fresh-install.sh --yes   only shows what every step would do
# (install.sh and install-apps.sh too); downloads are checked, nothing changes.

set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, ask, apt_get, run_steps, summary, DOTFILES
# Plugged in? A computer without a battery (a desktop) always counts as plugged in.
on_charger() {
  compgen -G '/sys/class/power_supply/BAT*' >/dev/null || return 0
  cat /sys/class/power_supply/*/online 2>/dev/null | grep -qx 1
}

title="Fresh install"; [[ "$DRY_RUN" == 1 ]] && title+=" (dry run: changes nothing)"
header "$title" \
  "Sets up this computer from ~/dotfiles, in six steps:" \
  "  1 update the system        2 firmware (on charger only)" \
  "  3 terminal tools           4 configs and desktop (install.sh)" \
  "  5 apps (install-apps.sh)   6 configs again, now the apps exist" \
  "Uses sudo and takes a while. Yes to everything also accepts the" \
  "Microsoft fonts licence (codecs) and restarts at the end."
yes_flag "$@"
[[ "$DRY_RUN" == 1 ]] && note "Dry run: shows what every step would do; downloads are checked, nothing changes."
check_system
# gum draws the menus. If the first command didn't install it, get it now (needs the
# password and a correct clock first), so the questions below are menus too.
if ! have gum && [[ -z "$YES_ALL" && -t 0 && "$DRY_RUN" != 1 ]]; then
  note "Getting the menus ready: installing gum (asks for your password once)"
  keep_sudo || exit 1
  clock_step
  { apt_get update && apt_get install -y gum; } || true
fi
[[ "$DRY_RUN" == 1 ]] || git_identity
choose_answer_mode
ask_or_quit "Start?"
[[ "$DRY_RUN" == 1 ]] || keep_sudo || exit 1
clock_step   # before the first update: apt rejects updates while the clock is wrong

# 1. Update the system --------------------------------------------------------------
update_system() {
  apt_get update
  apt_get -y full-upgrade
}

# 2. Firmware (BIOS, SSD, devices) ---------------------------------------------------
update_firmware() {
  need firmware || return 0
  command -v fwupdmgr >/dev/null || { skip "fwupdmgr isn't installed"; return 0; }
  if ! on_charger; then
    skip "plug in the charger first (a firmware update must not lose power)"
    note "later: fwupdmgr refresh --force && fwupdmgr update"
    return 0
  fi
  ask "Check for and install firmware updates (BIOS, SSD, devices)? Keep the charger in." \
    || { skip "you chose not to"; return 0; }
  note "checking for firmware updates (shown in full: don't turn the computer off while it installs)"
  run_quiet sudo fwupdmgr refresh --force || true
  local rc=0
  run sudo fwupdmgr update --assume-yes --no-reboot-check || rc=$?
  (( rc == 0 || rc == 2 )) || return "$rc"   # 2 means "nothing to update"
}

# 3. Terminal tools and Flathub ---------------------------------------------------------
install_tools() {
  apt_get_as "Installing ${#TOOLS[@]} terminal tools" install -y "${TOOLS[@]}"
  run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# 4-6. The dotfiles scripts -------------------------------------------------------------
# DEFER_DESKTOP: the look (theme, fonts, extensions, wallpaper) stays Ubuntu's until the
# very end, then changes once, right before the restart (apply_look below).
run_install() { DEFER_DESKTOP=1 "$DOTFILES/install.sh" --yes; }
run_install_apps() { "$DOTFILES/install-apps.sh"; }

run_steps \
  "Update the system|update_system" \
  "Firmware updates|update_firmware" \
  "Terminal tools and Flathub|install_tools" \
  "Configs, fonts, Flatpak apps, extensions, settings (install.sh)|run_install" \
  "Apps, NVIDIA driver, weekly updates (install-apps.sh)|run_install_apps" \
  "VS Code extensions and Obsidian (install.sh again)|run_install"

# Done -------------------------------------------------------------------------------
summary; ok=$?
if [[ "$DRY_RUN" == 1 ]]; then
  note "Then it would apply your desktop look (install.sh --desktop-only) and offer to restart."
  exit "$ok"
fi
printf '\n%sAfter the restart%s\n' "$C_B" "$C_N"
note "Blue \"MOK management\" screen (NVIDIA with Secure Boot): Enroll MOK, Continue, Yes, your password, Reboot"
note "Check the NVIDIA card works: nvidia-smi"
note "Sign in to your apps (Steam, browsers, Discord)"
note "Open Backups, connect Google Drive, and turn on \"Back Up Automatically\""
note "Sign in to GitHub (for your notes, pushing and signed commits): gh auth login, then dot install and dot ssh"
note "Then run dot check in a new terminal"
echo
# Your desktop look, all at once: right before the restart, so the screen doesn't
# change halfway through. Also when you don't restart (or press Ctrl+C to stay).
apply_look() {
  note "Applying your desktop look (theme, fonts, extensions, wallpaper)"
  "$DOTFILES/install.sh" --desktop-only > /dev/null 2>&1 || warn "some of it didn't apply: run dot install"
}
if ask "Restart now?"; then
  if [[ "$YES_ALL" == 1 ]]; then
    trap 'echo; apply_look; note "Not restarting: log out and back in to see your desktop look."; exit 0' INT
    for n in $(seq 15 -1 1); do
      printf '\r    %sRestarting in %2ss.%s Press Ctrl+C to stay. ' "$C_WARN" "$n" "$C_N"
      sleep 1
    done
    echo
    trap - INT
  fi
  apply_look
  sudo reboot
else
  apply_look
  note "Log out and back in (or restart) to see it fully, with the extensions running."
fi
