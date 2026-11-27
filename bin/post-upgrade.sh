#!/usr/bin/env bash
# Run once after upgrading Ubuntu to a new release (for example 26.04 -> 28.04),
# then restart. The upgrade switches off every app's own update source (Chrome,
# VS Code, Claude, Proton VPN, ONLYOFFICE, OBS), so those apps would silently stop
# updating. This script:
#   1. switches those update sources back on (OBS's PPA is added again for the new release)
#   2. updates everything (apt and Flatpak)
#   3. runs install-apps.sh: anything missing comes back, the Snap Firefox is removed
#      again if the upgrade brought it back, the NVIDIA driver and Steam's 32-bit
#      NVIDIA library match, and the weekly/monthly jobs are put back
#   4. runs install.sh, reinstalling GNOME extensions for the new GNOME version
#   5. checks the NVIDIA driver and runs check.sh
#
#   ~/code/github/dotfiles/bin/post-upgrade.sh                  one question: Yes to everything, or ask each
#   ~/code/github/dotfiles/bin/post-upgrade.sh --yes            Yes to everything without asking
#   ~/code/github/dotfiles/bin/post-upgrade.sh --sources-only   only step 1
#   DRY_RUN=1 ~/code/github/dotfiles/bin/post-upgrade.sh --yes  only shows what every step would do
# For testing: SOURCES_DIR=<folder> SUDO= bin/post-upgrade.sh --sources-only
# (SUDO is only for step 1; the updates in step 2 always use sudo)

set -uo pipefail
# shellcheck source=bin/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, skip, have, ask, apt_get, has_nvidia, run_steps, summary

SOURCES_DIR="${SOURCES_DIR:-/etc/apt/sources.list.d}"
SUDO="${SUDO-sudo}"
CODENAME="${CODENAME:-$(. /etc/os-release && echo "${VERSION_CODENAME:-}")}"

# 1. Update sources -----------------------------------------------------------------
reenable_sources() {
  local f changed=0
  # New-style .sources files: the upgrade adds "Enabled: no".
  for f in "$SOURCES_DIR"/*.sources; do
    [[ -f "$f" ]] || continue
    case "${f##*/}" in ubuntu.sources|ubuntu-esm-*|*ppa*|obsproject-*) continue ;; esac
    if grep -qiE '^Enabled:[[:space:]]*no' "$f"; then
      run $SUDO sed -i -E 's/^Enabled:[[:space:]]*no[[:space:]]*$/Enabled: yes/I' "$f"
      did "switched back on: ${f##*/}"; changed=1
    fi
  done
  # Old-style .list files: the upgrade comments the line out and adds "# disabled on upgrade to ...".
  for f in "$SOURCES_DIR"/*.list; do
    [[ -f "$f" ]] || continue
    if grep -qE '^#[[:space:]]*deb .*# disabled on upgrade to' "$f"; then
      run $SUDO sed -i -E 's/^#[[:space:]]*(deb .*[^[:space:]])[[:space:]]*# disabled on upgrade to.*$/\1/' "$f"
      did "switched back on: ${f##*/}"; changed=1
    fi
  done
  # OBS comes from a PPA, which is made for each Ubuntu release: add it again for this one.
  if compgen -G "$SOURCES_DIR/obsproject-*" >/dev/null \
     && ! compgen -G "$SOURCES_DIR/obsproject-*-$CODENAME.sources" >/dev/null; then
    run $SUDO rm -f "$SOURCES_DIR"/obsproject-*
    if have add-apt-repository && [[ "$SOURCES_DIR" == /etc/apt/sources.list.d ]]; then
      # shellcheck disable=SC2086  # $SUDO is sudo, or empty in the tests (no word at all)
      if run_quiet $SUDO add-apt-repository -y ppa:obsproject/obs-studio; then
        did "OBS's PPA added again for $CODENAME"
      else
        run $SUDO rm -f "$SOURCES_DIR"/obsproject-*
        echo "    OBS's PPA doesn't support $CODENAME yet; OBS stays at Ubuntu's version."
        echo "    Run this again in a few weeks (or ~/code/github/dotfiles/bin/post-upgrade.sh --sources-only)."
      fi
    else
      did "old OBS PPA removed (add-apt-repository not run here)"
    fi
    changed=1
  fi
  (( changed )) || echo "    all update sources already on"
}

# 2. Update everything -----------------------------------------------------------------
update_all() {
  apt_get update
  apt_get -y full-upgrade
  if have flatpak; then quiet "Updating Flatpak apps" flatpak update -y --noninteractive; fi
}

# 5. NVIDIA ------------------------------------------------------------------------------
check_nvidia() {
  if ! has_nvidia; then
    echo "    no NVIDIA card visible"; return 0
  fi
  if nvidia-smi >/dev/null 2>&1; then
    echo "    running: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)"
  else
    echo "    the driver isn't running yet. Restart first. If it still isn't running after"
    echo "    the restart: with Secure Boot on, enrol the key on the blue MOK screen at startup,"
    echo "    or run: sudo ubuntu-drivers install"
    return 1
  fi
}

# Main -------------------------------------------------------------------------------------
if [[ "${1:-}" == "--sources-only" ]]; then
  STEP_TOTAL=1
  run_step "Switch app update sources back on" reenable_sources
  summary; exit $?   # 1 if it failed
fi

title="After an Ubuntu upgrade"; [[ "$DRY_RUN" == 1 ]] && title+=" (dry run: changes nothing)"
header "$title" \
  "Switches app update sources back on, updates everything, puts back apps" \
  "and settings, reinstalls GNOME extensions for the new GNOME, and checks" \
  "the NVIDIA driver. Uses sudo."
yes_flag "$@"
choose_answer_mode
ask_or_quit "Continue?"
[[ -z "$SUDO" || "$DRY_RUN" == 1 ]] || keep_sudo || exit 1
[[ -z "$SUDO" ]] || clock_step   # apt rejects updates while the clock is wrong

run_install_apps() { "$DOTFILES/bin/install-apps.sh"; }
run_install() { REINSTALL_EXTENSIONS=1 "$DOTFILES/bin/install.sh" --yes; }

run_steps \
  "Switch app update sources back on|reenable_sources" \
  "Update everything (apt and Flatpak)|update_all" \
  "Apps, Snap Firefox, NVIDIA, weekly jobs (install-apps.sh)|run_install_apps" \
  "Configs, settings, GNOME extensions (install.sh)|run_install" \
  "NVIDIA driver|check_nvidia"

summary; ok=$?
[[ "$DRY_RUN" == 1 ]] && exit "$ok"
"$DOTFILES/bin/check.sh" || true
printf '\n%sNext%s\n' "$C_B" "$C_N"
note "Restart. If a GNOME extension is still off afterwards, switch it on in the Extensions app."
note "If the NVIDIA driver wasn't running, run ~/code/github/dotfiles/bin/post-upgrade.sh again after the restart."
exit "$ok"
