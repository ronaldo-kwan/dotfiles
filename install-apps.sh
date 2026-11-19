#!/usr/bin/env bash
# Install apps that need sudo: Chrome, VS Code, Claude Desktop, Proton VPN,
# OBS Studio, ONLYOFFICE, Steam, and the Ubuntu apps listed in
# setup/apt-packages.txt. Each one comes from its maker's official download
# source (or Ubuntu's own), which then keeps it updated through `sudo apt upgrade`.
#
# Uses sudo. Asks before each app, and skips apps that are already installed.
#
#   ~/dotfiles/install-apps.sh            install, asking before each app
#   ~/dotfiles/install-apps.sh --all      install all of them without asking
#   DRY_RUN=1 ~/dotfiles/install-apps.sh  only show what would happen

set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
ASK=1; [[ "${1:-}" == "--all" ]] && ASK=0
FAILED=()
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
chmod 755 "$TMP"   # lets apt's download user read the .deb files

SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup"

say()  { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
skip() { printf '    skipped: %s\n' "$*"; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# Packages from setup/apt-packages.txt (comments and blank lines ignored).
ubuntu_apps() { sed 's/#.*//' "$SETUP/apt-packages.txt" | awk 'NF{print $1}'; }

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
is_done() { if [[ "$1" == check_* ]]; then "$1"; else installed "$1"; fi; }

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

# Fingerprint of the first key in an ASCII-armoured key file.
key_fingerprint() { gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}'; }

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
  run sudo apt-get install -y "$TMP/chrome.deb"
}

install_vscode() {
  # Microsoft's .deb adds Microsoft's update source when this is answered "yes".
  echo "code code/add-microsoft-repo boolean true" > "$TMP/code.debconf"
  run sudo debconf-set-selections "$TMP/code.debconf"
  fetch_big "$TMP/code.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
  run sudo apt-get install -y "$TMP/code.deb"
}

install_claude() {
  # Anthropic's update source, signed with this key:
  local expected=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
  fetch "$TMP/claude.asc" https://downloads.claude.ai/claude-desktop/key.asc
  local got; got="$(key_fingerprint "$TMP/claude.asc")"
  if [[ "$got" != "$expected" ]]; then
    echo "    signing key fingerprint is $got, expected $expected. Not installing." >&2
    return 1
  fi
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > "$TMP/claude.list"
  run sudo install -m 644 "$TMP/claude.asc" /usr/share/keyrings/claude-desktop-archive-keyring.asc
  run sudo install -m 644 "$TMP/claude.list" /etc/apt/sources.list.d/claude-desktop.list
  run sudo apt-get update
  run sudo apt-get install -y claude-desktop
}

install_protonvpn() {
  # Proton's setup package adds Proton's update source. Its checksum is checked
  # against Proton's own package index before installing.
  local base=https://repo.protonvpn.com/debian path sha
  read -r path sha < <(repo_lookup "$base/dists/stable/main/binary-all/Packages" protonvpn-stable-release)
  [[ -n "$path" && -n "$sha" ]] || { echo "    couldn't find Proton's setup package" >&2; return 1; }
  fetch "$TMP/protonvpn-release.deb" "$base/$path"
  echo "$sha  $TMP/protonvpn-release.deb" | sha256sum -c --quiet - || { echo "    checksum didn't match. Not installing." >&2; return 1; }
  run sudo apt-get install -y "$TMP/protonvpn-release.deb"
  run sudo apt-get update
  run sudo apt-get install -y proton-vpn-gnome-desktop
}

install_obs() {
  run sudo add-apt-repository -y ppa:obsproject/obs-studio
  run sudo apt-get install -y obs-studio
}

install_onlyoffice() {
  # ONLYOFFICE's update source, signed with this key (same key as on Ubuntu's keyserver):
  local expected=E09CA29F6E178040EF22B4098320CA65CB2DE8E5
  fetch "$TMP/onlyoffice.asc" https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
  local got; got="$(key_fingerprint "$TMP/onlyoffice.asc")"
  if [[ "$got" != "$expected" ]]; then
    echo "    signing key fingerprint is $got, expected $expected. Not installing." >&2
    return 1
  fi
  gpg --dearmor < "$TMP/onlyoffice.asc" > "$TMP/onlyoffice.gpg"
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" > "$TMP/onlyoffice.list"
  run sudo install -m 644 "$TMP/onlyoffice.gpg" /usr/share/keyrings/onlyoffice.gpg
  run sudo install -m 644 "$TMP/onlyoffice.list" /etc/apt/sources.list.d/onlyoffice.list
  run sudo apt-get update
  run sudo apt-get install -y onlyoffice-desktopeditors
}

install_ubuntu_apps() {
  local missing=() p
  for p in $(ubuntu_apps); do installed "$p" || missing+=("$p"); done
  if (( ${#missing[@]} == 0 )); then
    [[ "$DRY_RUN" == 1 ]] && printf '    would install (if missing): %s\n' "$(ubuntu_apps | tr '\n' ' ')"
    return 0
  fi
  echo "    installing: ${missing[*]}"
  run sudo apt-get install -y "${missing[@]}"
}

install_steam() {
  # Ubuntu's own Steam package (from "multiverse"). Steam needs 32-bit support.
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    run sudo dpkg --add-architecture i386
  fi
  run sudo apt-get update
  # Non-interactive skips an information note the installer shows on some NVIDIA setups.
  run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y steam-installer
}

# --- Clock check -------------------------------------------------------------------
# apt refuses update sources whose release files look like they're "from the future",
# which happens when the clock is wrong (for example a VM resumed from a saved state).
# Compares this computer's clock with GitHub's; fails if they differ by over 5 minutes.
CLOCK_OFF=""
CLOCK_SERVER=""   # the real time (seconds since 1970), from the last check
check_clock() {
  local server now diff
  server="$(curl -fsSI --max-time 10 https://github.com 2>/dev/null \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="date"{print $2; exit}')"
  [[ -n "$server" ]] || return 0                 # offline: can't check, carry on
  server="$(date -d "$server" +%s 2>/dev/null)" || return 0
  CLOCK_SERVER="$server"
  now="$(date +%s)"; diff=$(( now - server )); diff=${diff#-}
  (( diff <= 300 )) && return 0
  CLOCK_OFF="$(( diff / 3600 ))h $(( diff % 3600 / 60 ))min $([[ $now -lt $server ]] && echo behind || echo ahead of)"
  return 1
}

clock_step() {
  check_clock && return 0
  say "Clock"
  echo "    This computer's clock is $CLOCK_OFF the real time."
  echo "    Installs would fail with \"Release file ... is not valid yet\"."
  if [[ "$DRY_RUN" == 1 ]]; then
    if command -v chronyc >/dev/null; then
      echo "    would offer to fix it with chrony: sudo chronyc makestep"
    else
      echo "    would offer to fix it: sudo systemctl restart systemd-timesyncd"
    fi
    echo "    (and if that doesn't work, set the clock from the internet time)"
    return 0
  fi
  local answer=y
  (( ASK )) && read -rp "    Fix the clock now? [Y/n] " answer
  if [[ ! "$answer" =~ ^[Nn]$ ]]; then
    # 1. Ask the time service to correct the clock right away.
    if command -v chronyc >/dev/null; then
      # Ubuntu 25.10+ uses chrony. "makestep" jumps straight to the right time
      # instead of slowly adjusting it.
      sudo chronyc -a burst 4/4 >/dev/null 2>&1
      sleep 5
      sudo chronyc -a makestep >/dev/null 2>&1
    elif systemctl cat systemd-timesyncd.service >/dev/null 2>&1; then
      sudo systemctl restart systemd-timesyncd
    fi
    for _ in $(seq 1 10); do sleep 2; check_clock && { echo "    clock fixed"; return 0; }; done
    # 2. Still wrong: set it directly from the internet time measured above.
    if [[ -n "$CLOCK_SERVER" ]]; then
      echo "    the time service didn't correct it; setting the clock from the internet time"
      sudo date -s "@$CLOCK_SERVER" >/dev/null && check_clock && { echo "    clock fixed"; return 0; }
    fi
    echo "    The clock is still $CLOCK_OFF. Check: timedatectl"
  fi
  answer=n
  (( ASK )) && read -rp "    Continue anyway? Installs will probably fail. [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Stopped. Nothing was installed."; exit 1; }
}

# --- Main --------------------------------------------------------------------------

APPS=(
  "Google Chrome|google-chrome-stable|install_chrome"
  "VS Code|code|install_vscode"
  "Claude Desktop|claude-desktop|install_claude"
  "Proton VPN|proton-vpn-gnome-desktop|install_protonvpn"
  "OBS Studio|obs-studio|install_obs"
  "ONLYOFFICE|check_onlyoffice|install_onlyoffice"
  "Steam|steam-installer|install_steam"
  "Ubuntu apps (VLC, qBittorrent, Tweaks, Extension Manager, Backups, Software)|check_ubuntu_apps|install_ubuntu_apps"
)

for tool in curl gpg sha256sum; do
  command -v "$tool" >/dev/null || { echo "Needs $tool first: sudo apt install $tool"; exit 1; }
done

[[ "$DRY_RUN" == 1 ]] && echo "Dry run: downloads are checked, but nothing is installed."
if [[ "$DRY_RUN" != 1 ]]; then
  echo "This installs apps from their makers' official sources and needs your password (sudo)."
  sudo -v || exit 1
fi
clock_step

for entry in "${APPS[@]}"; do
  IFS='|' read -r name check fn <<< "$entry"
  say "$name"
  if is_done "$check"; then
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "    already installed (checking its download anyway)"
    else
      echo "    already installed"
      continue
    fi
  fi
  if (( ASK )) && [[ "$DRY_RUN" != 1 ]]; then
    read -rp "    Install $name? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { skip "you chose not to"; continue; }
  fi
  ( set -e; "$fn" )
  rc=$?
  if (( rc != 0 )); then
    printf '    \033[1;31mfailed\033[0m (exit code %s)\n' "$rc"
    FAILED+=("$name")
  elif [[ "$DRY_RUN" != 1 ]]; then
    echo "    installed"
  fi
done

if (( ${#FAILED[@]} > 0 )); then
  say "Finished with problems. These apps failed (see messages above):"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
say "Done."
[[ "$DRY_RUN" != 1 ]] && echo "If you installed VS Code, run ~/dotfiles/install.sh again to add its extensions."
[[ "$DRY_RUN" != 1 ]] && echo "If you installed Steam, its first start downloads the rest of Steam, then you sign in."
exit 0
