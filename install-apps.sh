#!/usr/bin/env bash
# Install apps that need sudo: Chrome, VS Code, Claude Desktop, Proton VPN,
# OBS Studio, ONLYOFFICE, Steam, and the Ubuntu apps listed in
# setup/apt-packages.txt. Each one comes from its maker's official download
# source (or Ubuntu's own), which then keeps it updated through `sudo apt upgrade`.
# It can also remove Ubuntu's Snap Firefox (this setup uses the Flatpak one),
# set up weekly automatic updates and a monthly clean-up, and install the NVIDIA driver on computers
# with an NVIDIA graphics card.
#
# Uses sudo. Asks before each app, and skips apps that are already installed.
#
#   ~/dotfiles/install-apps.sh            asks once: Yes to everything, or ask before each app
#   ~/dotfiles/install-apps.sh --yes      Yes to everything without asking (--all and -y too)
#   DRY_RUN=1 ~/dotfiles/install-apps.sh  only show what would happen

set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, skip, ask, installed, fill_user, SETUP


# Packages from setup/apt-packages.txt (comments and blank lines ignored).
ubuntu_apps() { sed 's/#.*//' "$SETUP/apt-packages.txt" | awk 'NF && $1 !~ /^-/ {print $1}'; }

# "Already done?" checks for entries that need more than one package installed.
check_ubuntu_apps() {
  local p; for p in $(ubuntu_apps); do installed "$p" || return 1; done
}
check_onlyoffice() {
  installed onlyoffice-desktopeditors || return 1
  if [[ ! -f /etc/apt/sources.list.d/onlyoffice.list ]]; then
    echo "    installed, but without ONLYOFFICE's update source, so it never updates"
    return 1
  fi
}
# The weekly update script from system/, with this computer's username filled in.
weekly_script() {
  fill_user "$DOTFILES/system/etc/cron.weekly/system-update"
}
check_weekly_updates() {
  [[ -f /etc/cron.weekly/system-update ]] || return 1
  if ! cmp -s <(weekly_script) /etc/cron.weekly/system-update; then
    echo "    set up, but different from the saved version"
    return 1
  fi
}

# The monthly clean-up script from system/, with this computer's username filled in.
cleanup_script() {
  fill_user "$DOTFILES/system/etc/cron.monthly/system-cleanup"
}
check_monthly_cleanup() {
  [[ -f /etc/cron.monthly/system-cleanup ]] || return 1
  if ! cmp -s <(cleanup_script) /etc/cron.monthly/system-cleanup; then
    echo "    set up, but different from the saved version"
    return 1
  fi
}

has_nvidia() { lspci 2>/dev/null | grep -qiE '(vga|3d|display).*nvidia'; }
check_nvidia_driver() {
  if ! has_nvidia; then
    if grep -qi legion /sys/class/dmi/id/product_version 2>/dev/null; then
      # Legion laptops with "Hybrid-iGPU only" mode hide the NVIDIA card from Linux.
      echo "    no NVIDIA card visible. On this Legion it's probably hidden by the GPU mode:"
      echo "    restart, press F2 for the BIOS, set GPU Working Mode to Hybrid, then run this again"
    else
      echo "    not needed: this computer has no NVIDIA graphics card"
    fi
    NOT_NEEDED=1
    return 0
  fi
  dpkg-query -W -f='${Status}\n' 'nvidia-driver-*' 2>/dev/null | grep -q "install ok installed"
}

# NVIDIA driver version number (595, ...): from the running driver, or the installed package.
nvidia_major() {
  local v
  v="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1)"
  [[ -n "$v" ]] || v="$(dpkg-query -W -f='${Package} ${Status}\n' 'nvidia-driver-*' 2>/dev/null \
    | awk '/install ok installed/ {print $1}' | grep -oE '[0-9]+' | head -1)"
  echo "$v"
}
STEAM_SHORTCUT="$HOME/.local/share/applications/steam.desktop"
check_steam_nvidia() {
  if ! installed steam-installer || ! has_nvidia; then
    echo "    not needed: $(installed steam-installer && echo "no NVIDIA graphics card" || echo "Steam isn't installed")"
    NOT_NEEDED=1
    return 0
  fi
  local major; major="$(nvidia_major)"
  [[ -n "$major" ]] && installed "libnvidia-gl-$major:i386" \
    && grep -q '^PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT" 2>/dev/null
}

# Firewall: block connections from outside (nothing you start yourself is affected).
check_firewall() { grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null; }
setup_firewall() {
  installed ufw || apt_get install -y ufw
  run sudo ufw default deny incoming
  run sudo ufw default allow outgoing
  # qBittorrent shares faster when other people can connect to it: open its port.
  local port
  port="$(sed -n 's/^Session\\Port=//p' "$HOME/.config/qBittorrent/qBittorrent.conf" 2>/dev/null | head -1)"
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    run sudo ufw allow "$port" comment qBittorrent
    note "port $port left open for qBittorrent"
  fi
  run sudo ufw --force enable
  note "on; see the rules: sudo ufw status verbose"
}

check_no_snap_firefox() {
  ! snap list firefox >/dev/null 2>&1 && ! installed firefox
}
is_done() { if [[ "$1" == check_* ]]; then "$1"; else installed "$1"; fi; }

# Wait while another program (such as Ubuntu's automatic updates) is using apt.
# Only one program can install or refresh package lists at a time.
APT_LOCKS=(/var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
apt_wait() {
  [[ "$DRY_RUN" == 1 ]] && return 0
  command -v fuser >/dev/null || return 0
  local waited=0
  while sudo fuser "${APT_LOCKS[@]}" >/dev/null 2>&1; do
    (( waited == 0 )) && echo "    waiting for another software update to finish (often Ubuntu's automatic updates)..."
    sleep 5; waited=$(( waited + 5 ))
    if (( waited >= 900 )); then echo "    still busy after 15 minutes; trying anyway"; break; fi
  done
}

# apt-get, after waiting for other updates to finish. DPkg::Lock::Timeout also
# makes apt itself wait (up to 5 minutes) if something starts in between.
# apt_get <apt-get arguments>: with a spinner and a short label; full output in the log.
apt_get() {
  apt_wait
  if [[ "$DRY_RUN" == 1 ]]; then run sudo apt-get "$@"; return 0; fi
  local label a pkgs=()
  for a in "$@"; do [[ "$a" == -* || "$a" == install || "$a" == remove || "$a" == update ]] || pkgs+=("${a##*/}"); done
  case " $* " in
    *" update "*)  label="Refreshing package lists" ;;
    *" remove "*)  label="Removing ${pkgs[*]}" ;;
    *)             label="Installing ${pkgs[*]}" ;;
  esac
  (( ${#label} > 60 )) && label="${label:0:57}..."
  quiet "$label" sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# Run a command, or only print it in dry-run mode.
run() {
  if [[ "$DRY_RUN" == 1 ]]; then printf '    would run: %s\n' "$*"; else "$@"; fi
}

# Download a file (also done in dry-run mode, to check the link still works).
fetch() { curl -fsSL --retry 3 -o "$1" "$2"; }

# Download a large installer. In dry-run mode, only check that the link works.
fetch_big() {
  if [[ "$DRY_RUN" == 1 ]]; then
    curl -fsIL --retry 3 -o /dev/null "$2" && printf '    download link works: %s\n' "$2"
  else
    fetch "$1" "$2"
  fi
}

# key_ok <key file> <expected fingerprint>: the file must hold exactly one key, and
# it must be that one. (apt trusts every key in a signing-key file, so a file with an
# extra key added would otherwise pass a check of only the first one.)
key_ok() {
  local keys n fpr
  keys="$(gpg --show-keys --with-colons "$1" 2>/dev/null)"
  n="$(grep -c '^pub' <<< "$keys")"
  fpr="$(awk -F: '$1=="fpr"{print $10; exit}' <<< "$keys")"
  [[ "$n" == 1 && "$fpr" == "$2" ]] && return 0
  echo "    the signing key file holds $n key(s) (first: ${fpr:-none}); expected only $2. Not installing." >&2
  return 1
}

# Look up a package's file path and SHA-256 in an apt repository's package index.
repo_lookup() { # repo_lookup <Packages URL> <package>  -> prints "path sha256"
  curl -fsSL "$1" | awk -v p="$2" '
    $1=="Package:"{x=($2==p)} x&&$1=="Filename:"{f=$2} x&&$1=="SHA256:"{s=$2}
    END{print f, s}'
}

# --- Apps --------------------------------------------------------------------------

install_chrome() {
  # Google's .deb adds Google's update source itself.
  fetch_big "$TMP/chrome.deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt_get install -y "$TMP/chrome.deb"
}

install_vscode() {
  # Microsoft's .deb adds Microsoft's update source when this is answered "yes".
  echo "code code/add-microsoft-repo boolean true" > "$TMP/code.debconf"
  run sudo debconf-set-selections "$TMP/code.debconf"
  fetch_big "$TMP/code.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
  apt_get install -y "$TMP/code.deb"
}

install_claude() {
  # Anthropic's update source, signed with this key:
  local expected=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
  fetch "$TMP/claude.asc" https://downloads.claude.ai/claude-desktop/key.asc
  key_ok "$TMP/claude.asc" "$expected" || return 1
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > "$TMP/claude.list"
  run sudo install -m 644 "$TMP/claude.asc" /usr/share/keyrings/claude-desktop-archive-keyring.asc
  run sudo install -m 644 "$TMP/claude.list" /etc/apt/sources.list.d/claude-desktop.list
  apt_get update
  apt_get install -y claude-desktop
}

install_protonvpn() {
  # Proton's setup package adds Proton's update source. Its checksum is checked
  # against Proton's own package index before installing.
  local base=https://repo.protonvpn.com/debian path sha
  read -r path sha < <(repo_lookup "$base/dists/stable/main/binary-all/Packages" protonvpn-stable-release)
  [[ -n "$path" && -n "$sha" ]] || { echo "    couldn't find Proton's setup package" >&2; return 1; }
  fetch "$TMP/protonvpn-release.deb" "$base/$path"
  echo "$sha  $TMP/protonvpn-release.deb" | sha256sum -c --quiet - || { echo "    checksum didn't match. Not installing." >&2; return 1; }
  apt_get install -y "$TMP/protonvpn-release.deb"
  apt_get update
  apt_get install -y proton-vpn-gnome-desktop
}

install_obs() {
  apt_wait
  run sudo add-apt-repository -y ppa:obsproject/obs-studio
  apt_get install -y obs-studio
}

install_onlyoffice() {
  # ONLYOFFICE's update source, signed with this key (same key as on Ubuntu's keyserver):
  local expected=E09CA29F6E178040EF22B4098320CA65CB2DE8E5
  fetch "$TMP/onlyoffice.asc" https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
  key_ok "$TMP/onlyoffice.asc" "$expected" || return 1
  gpg --dearmor < "$TMP/onlyoffice.asc" > "$TMP/onlyoffice.gpg"
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" > "$TMP/onlyoffice.list"
  run sudo install -m 644 "$TMP/onlyoffice.gpg" /usr/share/keyrings/onlyoffice.gpg
  run sudo install -m 644 "$TMP/onlyoffice.list" /etc/apt/sources.list.d/onlyoffice.list
  apt_get update
  apt_get install -y onlyoffice-desktopeditors
}

install_ubuntu_apps() {
  local missing=() p
  for p in $(ubuntu_apps); do installed "$p" || missing+=("$p"); done
  if (( ${#missing[@]} == 0 )); then
    [[ "$DRY_RUN" == 1 ]] && printf '    would install (if missing): %s\n' "$(ubuntu_apps | tr '\n' ' ')"
    return 0
  fi
  echo "    installing: ${missing[*]}"
  # The codecs bring Microsoft's fonts, whose installer stops on a licence screen.
  # Answer it here instead (Yes to everything counts as accepting it).
  if printf '%s\n' "${missing[@]}" | grep -qx ubuntu-restricted-extras; then
    # LICENCE comes from the checklist; without one, ask here.
    if [[ "${LICENCE:-}" == yes ]] || { [[ -z "${LICENCE:-}" ]] && ask "Accept the Microsoft fonts licence (needed for the codecs)?"; }; then
      echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" > "$TMP/fonts.debconf"
      run sudo debconf-set-selections "$TMP/fonts.debconf"
    fi
  fi
  apt_get install -y "${missing[@]}"
}

setup_weekly_updates() {
  # Updates everything once a week and shows a notification if it fails or gets stuck.
  weekly_script > "$TMP/system-update"
  run sudo install -m 755 -o root -g root "$TMP/system-update" /etc/cron.weekly/system-update
  echo "    runs once a week; log: /var/log/system-update.log"
}

setup_monthly_cleanup() {
  # Removes unused packages (apt autoremove) and Flatpak runtimes once a month.
  cleanup_script > "$TMP/system-cleanup"
  run sudo install -m 755 -o root -g root "$TMP/system-cleanup" /etc/cron.monthly/system-cleanup
  echo "    runs once a month; log: /var/log/system-cleanup.log"
}

install_nvidia_driver() {
  # Ubuntu picks the right driver for the card (works with Secure Boot).
  has_nvidia || { skip "this computer has no NVIDIA graphics card"; return 0; }
  apt_wait
  run sudo ubuntu-drivers install
  echo "    restart the computer to start using the NVIDIA driver"
}

setup_steam_nvidia() {
  # 1. Many games need the 32-bit NVIDIA library that matches the driver.
  local major; major="$(nvidia_major)"
  if [[ -z "$major" ]]; then
    skip "the NVIDIA driver isn't installed yet (install it first, then run this again)"
    return 0
  fi
  installed "libnvidia-gl-$major:i386" || apt_get install -y "libnvidia-gl-$major:i386"
  # 2. A copy of Steam's shortcut that asks for the NVIDIA card, so games run on it.
  if ! grep -q '^PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT" 2>/dev/null; then
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "    would make Steam's shortcut use the NVIDIA card: $STEAM_SHORTCUT"
    else
      mkdir -p "$(dirname "$STEAM_SHORTCUT")"
      cp /usr/share/applications/steam.desktop "$STEAM_SHORTCUT"
      sed -i '/^\[Desktop Entry\]/a PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT"
      echo "    Steam now starts on the NVIDIA card (quit Steam fully first if it's open)"
    fi
  fi
}

remove_snap_firefox() {
  # Ubuntu ships Firefox as a Snap; this setup uses the Flatpak one (setup/flatpaks.txt).
  # Only remove it when the Flatpak Firefox is there, so you're never left without one.
  if ! flatpak info org.mozilla.firefox >/dev/null 2>&1; then
    skip "the Flatpak Firefox isn't installed (run install.sh first), so the Snap one stays"
    return 0
  fi
  if snap list firefox >/dev/null 2>&1; then
    run sudo snap remove firefox
  fi
  # Ubuntu's "firefox" package only exists to install the Snap; an update to it
  # would bring the Snap back, so remove it too. Nothing else depends on it.
  if installed firefox; then
    apt_get remove -y firefox
  fi
}

install_steam() {
  # Ubuntu's own Steam package (from "multiverse"). Steam needs 32-bit support.
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    run sudo dpkg --add-architecture i386
  fi
  apt_get update
  # (apt_get runs non-interactively, which skips a note Steam shows on some NVIDIA setups.)
  apt_get install -y steam-installer
}

# --- Clock check: clock_step is in lib.sh (fresh-install.sh and post-upgrade.sh run it first too)

# --- Main --------------------------------------------------------------------------

APPS=(
  "Google Chrome|google-chrome-stable|install_chrome"
  "VS Code|code|install_vscode"
  "Claude Desktop|claude-desktop|install_claude"
  "Proton VPN|proton-vpn-gnome-desktop|install_protonvpn"
  "OBS Studio|obs-studio|install_obs"
  "ONLYOFFICE|check_onlyoffice|install_onlyoffice"
  "Steam|steam-installer|install_steam"
  "Ubuntu apps (VLC, qBittorrent, Tweaks, Backups, codecs and more: setup/apt-packages.txt)|check_ubuntu_apps|install_ubuntu_apps"
  "NVIDIA graphics driver|check_nvidia_driver|install_nvidia_driver"
  "Steam on the NVIDIA card (32-bit library, shortcut)|check_steam_nvidia|setup_steam_nvidia|Set up"
  "weekly automatic updates (/etc/cron.weekly/system-update)|check_weekly_updates|setup_weekly_updates|Set up"
  "monthly clean-up of unused packages (/etc/cron.monthly/system-cleanup)|check_monthly_cleanup|setup_monthly_cleanup|Set up"
  "the firewall (ufw), blocking connections from outside|check_firewall|setup_firewall|Switch on"
  "Ubuntu's Snap Firefox (you use the Flatpak one)|check_no_snap_firefox|remove_snap_firefox|Remove"
)

# check.sh loads this file only for APPS and the check_* functions above.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
chmod 755 "$TMP"   # lets apt's download user read the .deb files

for tool in curl gpg sha256sum; do
  command -v "$tool" >/dev/null || { echo "Needs $tool first: sudo apt install $tool"; exit 1; }
done

title="Apps and system jobs"; [[ "$DRY_RUN" == 1 ]] && title+=" (dry run: installs nothing)"
header "$title" \
  "Apps from their makers' official sources, kept updated by apt:" \
  "Chrome, VS Code, Claude, Proton VPN, OBS, ONLYOFFICE, Steam, Ubuntu apps;" \
  "the NVIDIA driver, weekly updates, monthly clean-up, no Snap Firefox." \
  "Uses sudo. Yes to everything also accepts the Microsoft fonts licence."
# shellcheck disable=SC2034  # read by step_begin in lib.sh
STEP_TOTAL=${#APPS[@]}
[[ "$DRY_RUN" == 1 ]] && note "Dry run: downloads are checked, but nothing is installed."
if [[ "$DRY_RUN" != 1 ]]; then
  yes_flag "$@"
  choose_answer_mode
  keep_sudo || exit 1
fi
clock_step

# What's already done, not needed, or still to do (quietly, before anything runs).
STATUS=()
for i in "${!APPS[@]}"; do
  IFS='|' read -r _ check _ <<< "${APPS[$i]}"
  NOT_NEEDED=0
  if is_done "$check" >/dev/null 2>&1; then
    if (( NOT_NEEDED )); then STATUS[i]=notneeded; else STATUS[i]="done"; fi
  else STATUS[i]=todo; fi
done

# "Let me choose" with gum: one checklist instead of a question per app.
CHECKLIST=0 CHOSEN=" " LICENCE=""
if [[ "$DRY_RUN" != 1 && "$YES_ALL" == 0 ]] && ui_gum; then
  opts=() done_names=() licence_offered=0
  for i in "${!APPS[@]}"; do
    IFS='|' read -r name _ _ verb <<< "${APPS[$i]}"
    case "${STATUS[i]}" in
      todo) opts+=("$( [[ -z "$verb" ]] || printf '%s ' "$verb")$name|$i") ;;
      done) done_names+=("${name%% (*}") ;;
    esac
    if [[ "${STATUS[i]}" == todo && "${APPS[$i]}" == *"|install_ubuntu_apps"* ]] && ! installed ubuntu-restricted-extras; then
      opts+=("Accept the Microsoft fonts licence (needed for the codecs)|licence"); licence_offered=1
    fi
  done
  if (( ${#opts[@]} )); then
    hdr="Choose what to set up: Space ticks or unticks, Enter starts."
    (( ${#done_names[@]} )) && hdr+=$'\n'"Already done: $(printf '%s, ' "${done_names[@]}" | sed 's/, $//')"
    echo
    picked="$(gum choose --no-limit --selected='*' --label-delimiter='|' --header "$hdr" \
      --height $(( ${#opts[@]} + 4 )) "${opts[@]}")" || { echo "Nothing changed."; exit 0; }
    CHECKLIST=1 CHOSEN=" $(tr '\n' ' ' <<< "$picked") "
    (( licence_offered )) && { [[ "$CHOSEN" == *" licence "* ]] && LICENCE=yes || LICENCE=no; }
  fi
fi

titles=()
for entry in "${APPS[@]}"; do
  IFS='|' read -r name _ _ verb <<< "$entry"; titles+=("${verb:-Install}: $name")
done
ui_plan "${titles[@]}"

for i in "${!APPS[@]}"; do
  IFS='|' read -r name check fn verb <<< "${APPS[$i]}"
  verb="${verb:-Install}"
  step_begin "$verb: $name"
  NOT_NEEDED=0
  if is_done "$check"; then
    if (( NOT_NEEDED )); then step_end notneeded; continue; fi
    if [[ "$DRY_RUN" != 1 ]]; then step_end already; continue; fi
    note "already done (checking the download anyway)"
  fi
  if (( CHECKLIST )); then
    [[ "$CHOSEN" == *" $i "* ]] || { step_end skip "not chosen"; continue; }
  elif [[ "$DRY_RUN" != 1 ]] && ! ask "$verb $name?"; then
    step_end skip "you chose not to"; continue
  fi
  ( set -e; "$fn" )
  rc=$?
  if (( rc != 0 )); then step_end fail "exit code $rc"; else step_end ok; fi
done

summary; ok=$?
if [[ "$DRY_RUN" != 1 && "$UI_NESTED" == 0 ]]; then
  echo
  note "Installed VS Code? Run ~/dotfiles/install.sh again to add its extensions."
  note "Installed Steam? Its first start downloads the rest of Steam, then you sign in."
fi
exit "$ok"
