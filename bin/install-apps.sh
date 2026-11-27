#!/usr/bin/env bash
# Install apps that need sudo: Chrome, Brave Origin, VS Code, Claude Desktop, Claude Code,
# Proton VPN, OBS Studio, ONLYOFFICE, Steam, and the Ubuntu apps listed in
# setup/apt-packages.txt. Each one comes from its maker's official download
# source (or Ubuntu's own), which then keeps it updated through `sudo apt upgrade`.
# It can also remove Ubuntu's Snap Firefox (this setup uses the Flatpak one),
# set up weekly automatic updates and a monthly clean-up, style the login screen, and install the NVIDIA driver on computers
# with an NVIDIA graphics card.
#
# Uses sudo. Asks before each app, and skips apps that are already installed.
#
#   ~/code/github/dotfiles/bin/install-apps.sh            asks once: Yes to everything, or ask before each app
#   ~/code/github/dotfiles/bin/install-apps.sh --yes      Yes to everything without asking (--all and -y too)
#   DRY_RUN=1 ~/code/github/dotfiles/bin/install-apps.sh  only show what would happen

set -uo pipefail

# shellcheck source=bin/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # say, skip, ask, run, apt_get, installed, fill_user, SETUP

# Where apt keeps update sources and their signing keys
APT_SOURCES=/etc/apt/sources.list.d APT_KEYS=/usr/share/keyrings
# Brave Origin's settings: policy files in system/etc/, put in /etc/ as they are (Brave reads
# /etc/brave/policies/, as regular Brave does). managed/: locked; recommended/: defaults you
# can change in Brave (Google as the search engine). What each setting does: docs/apps.md.
BRAVE_POLICY=brave/policies/managed/dotfiles.json
BRAVE_RECOMMENDED=brave/policies/recommended/dotfiles.json

# --- What it sets up -------------------------------------------------------------------
# One line per entry, in order:
#   choice (lib.sh: chosen; "pkg:*" = any Ubuntu app picked)|name|done check (a package,
#   or a check_ function below)|install function|verb (empty = Install)
# scripts/build-site.py reads this list for the website: entries whose choice is app:...
# are offered as single apps.
APPS=(
  "app:chrome|Google Chrome|google-chrome-stable|install_chrome"
  "app:brave-origin|Brave Origin|check_brave_origin|install_brave_origin"
  "app:code|VS Code|code|install_vscode"
  "app:claude|Claude Desktop|claude-desktop|install_claude"
  "app:claude-code|Claude Code (the claude command)|claude-code|install_claude_code"
  "app:chatgpt|ChatGPT (with Codex)|chatgpt|install_chatgpt"
  "app:protonvpn|Proton VPN|proton-vpn-gnome-desktop|install_protonvpn"
  "app:obs|OBS Studio|obs-studio|install_obs"
  "app:onlyoffice|ONLYOFFICE|check_onlyoffice|install_onlyoffice"
  "app:steam|Steam|steam-installer|install_steam"
  "pkg:*|Ubuntu apps (VLC, qBittorrent, Tweaks, Backups, codecs and more: setup/apt-packages.txt)|check_ubuntu_apps|install_ubuntu_apps"
  "nvidia|NVIDIA graphics driver|check_nvidia_driver|install_nvidia_driver"
  "nvidia|Steam on the NVIDIA card (32-bit library, shortcut)|check_steam_nvidia|setup_steam_nvidia|Set up"
  "updates|weekly automatic updates (/etc/cron.weekly/system-update)|check_weekly_updates|setup_weekly_updates|Set up"
  "updates|monthly clean-up of unused packages (/etc/cron.monthly/system-cleanup)|check_monthly_cleanup|setup_monthly_cleanup|Set up"
  "desktop|the login screen: blurred wallpaper, dark theme, blue accent, Roboto|check_login_screen|setup_login_screen|Set up"
  "firewall|the firewall (ufw), blocking connections from outside|check_firewall|setup_firewall|Switch on"
  "nosnapfirefox|Ubuntu's Snap Firefox (you use the Flatpak one)|check_no_snap_firefox|remove_snap_firefox|Remove"
)

# What each app from its maker adds to the system, by its choice: its packages, then
# the update source and key files it adds (a ppa: is removed with add-apt-repository).
# uninstall.sh --apps removes these; check.sh counts the packages as saved.
declare -gA APP_PARTS=(
  [app:chrome]="google-chrome-stable|$APT_SOURCES/google-chrome.sources $APT_SOURCES/google-chrome.list $APT_KEYS/google-chrome.gpg"
  [app:brave-origin]="brave-origin|$APT_SOURCES/brave-browser-release.sources $APT_KEYS/brave-browser-archive-keyring.gpg /etc/$BRAVE_POLICY /etc/$BRAVE_RECOMMENDED"
  [app:code]="code|$APT_SOURCES/vscode.sources $APT_SOURCES/vscode.list $APT_KEYS/microsoft.gpg"
  [app:claude]="claude-desktop|$APT_SOURCES/claude-desktop.list $APT_KEYS/claude-desktop-archive-keyring.asc"
  [app:claude-code]="claude-code|$APT_SOURCES/claude-code.list $APT_KEYS/claude-code.asc"
  [app:chatgpt]="chatgpt|$APT_SOURCES/chatgpt.sources $APT_KEYS/chatgpt-archive-keyring.gpg"
  [app:protonvpn]="proton-vpn-gnome-desktop protonvpn-stable-release protonvpn-beta-release|"
  [app:obs]="obs-studio|ppa:obsproject/obs-studio"
  [app:onlyoffice]="onlyoffice-desktopeditors|$APT_SOURCES/onlyoffice.list $APT_KEYS/onlyoffice.gpg"
  [app:steam]="steam-installer steam-launcher|"
)
# Every package this script installs itself (not from setup/apt-packages.txt)
APP_PACKAGES=()
for _c in "${!APP_PARTS[@]}"; do read -ra _p <<< "${APP_PARTS[$_c]%%|*}"; APP_PACKAGES+=("${_p[@]}"); done
APP_PACKAGES+=('nvidia-driver-*' 'libnvidia-gl-*' 'linux-modules-nvidia-*' ufw)

# entry_chosen <choice>: was this entry picked? (everything when there's no list)
entry_chosen() { if [[ "$1" == *'*' ]]; then chosen_any "${1%\*}"; else chosen "$1"; fi; }

# --- "Already done?" checks, for entries that need more than one installed package ----
# Packages from setup/apt-packages.txt; only the ones chosen (pkg:<name>), when there's a list.
ubuntu_apps() { chosen_from apt-packages.txt pkg:; }
check_ubuntu_apps() {
  local p; for p in $(ubuntu_apps); do installed "$p" || return 1; done
}
check_brave_origin() {
  installed brave-origin || return 1
  local f
  for f in "$BRAVE_POLICY" "$BRAVE_RECOMMENDED"; do
    if ! cmp -s "$DOTFILES/system/etc/$f" "/etc/$f"; then
      echo "    installed, but without the saved settings (/etc/$f)"
      return 1
    fi
  done
}
check_onlyoffice() {
  installed onlyoffice-desktopeditors || return 1
  if [[ ! -f "$APT_SOURCES/onlyoffice.list" ]]; then
    echo "    installed, but without ONLYOFFICE's update source, so it never updates"
    return 1
  fi
}

# The weekly update and monthly clean-up jobs: scripts in system/etc/, with this
# computer's username filled in. check_job / install_job <path under /etc>
check_job() {
  [[ -f "/etc/$1" ]] || return 1
  if ! cmp -s <(fill_user "$DOTFILES/system/etc/$1") "/etc/$1"; then
    echo "    set up, but different from the saved version"
    return 1
  fi
}
install_job() {
  fill_user "$DOTFILES/system/etc/$1" > "$TMP/job"
  run sudo install -m 755 -o root -g root "$TMP/job" "/etc/$1"
}
check_weekly_updates() { check_job cron.weekly/system-update; }
check_monthly_cleanup() { check_job cron.monthly/system-cleanup; }

# The login screen (GDM) runs as its own system user, so its look is system-wide: GNOME's
# usual way is a settings file in /etc/dconf/db/gdm.d/, which `dconf update` compiles, read
# through a dconf profile that includes it (Ubuntu's own, /usr/share/dconf/profile/gdm, plus
# `system-db:gdm`). It can't read your home folder, so the background is copied too.
LOGIN_BG=/usr/share/backgrounds/dotfiles/login-blurred.jpg
GDM_PROFILE=/etc/dconf/profile/gdm
GDM_SETTINGS=/etc/dconf/db/gdm.d/90-dotfiles
# The settings: the blurred, darkened wallpaper (setup/wallpaper/login-blurred.jpg), and
# the desktop's own dark theme, accent colour and font (from setup/gnome-desktop.dconf).
login_settings() {
  local k
  echo "# Written by ~/dotfiles (install-apps.sh): how the login screen looks."
  echo "# To undo: dot uninstall --apps (or delete this file and run: sudo dconf update)"
  echo "[com/ubuntu/login-screen]"
  echo "background-picture-uri='file://$LOGIN_BG'"
  echo "background-size='cover'"
  echo
  echo "[org/gnome/desktop/interface]"
  for k in color-scheme accent-color font-name; do
    sed -n '/^\[desktop\/interface\]/,/^$/p' "$SETUP/gnome-desktop.dconf" | grep "^$k="
  done
}
# Ubuntu's profile for the login screen, plus the system settings above (its first line
# marks it as ours, so uninstall.sh only ever removes this one).
login_profile() {
  echo "# Written by ~/dotfiles (install-apps.sh): Ubuntu's login screen profile, plus system-db:gdm"
  sed '/^user-db:/a system-db:gdm' /usr/share/dconf/profile/gdm
}
check_login_screen() {
  if [[ ! -f /usr/share/dconf/profile/gdm ]]; then   # another login manager, or none (a container)
    echo "    not needed: the login screen isn't GNOME's (GDM)"; NOT_NEEDED=1; return 0
  fi
  [[ -f "$GDM_SETTINGS" ]] || return 1
  if ! cmp -s <(login_settings) "$GDM_SETTINGS" || ! cmp -s <(login_profile) "$GDM_PROFILE" \
     || ! cmp -s "$SETUP/wallpaper/login-blurred.jpg" "$LOGIN_BG"; then
    echo "    set up, but different from the saved version"
    return 1
  fi
}

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
  installed 'nvidia-driver-*'
}

# NVIDIA driver version number (595, ...): from the running driver, or the installed package.
nvidia_major() {
  local v
  v="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1)"
  # When the driver isn't running, nvidia-smi prints its error message as output: only a number counts.
  [[ "$v" =~ ^[0-9]+$ ]] || v=""
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
    && grep -q '^PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT" 2>/dev/null \
    && ! grep -q '^Name=Install Steam$' "$STEAM_SHORTCUT"
}

# Firewall: block connections from outside (nothing you start yourself is affected).
check_firewall() { grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null; }
setup_firewall() {
  installed ufw || apt_get install -y ufw
  run sudo ufw default deny incoming
  run sudo ufw default allow outgoing
  # qBittorrent shares faster when other people can connect to it: open its port.
  local port='' conf="$HOME/.config/qBittorrent/qBittorrent.conf"
  [[ -f "$conf" ]] && port="$(sed -n 's/^Session\\Port=//p' "$conf" | head -1)"   # no settings, no port
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    run sudo ufw allow "$port" comment qBittorrent
    note "port $port left open for qBittorrent"
  fi
  run sudo ufw --force enable
  mark_added firewall   # it was off (else this step is skipped): dot uninstall may switch it off
  note "on; see the rules: sudo ufw status verbose"
}

check_no_snap_firefox() {
  ! snap list firefox >/dev/null 2>&1 && ! installed firefox
}
is_done() { if [[ "$1" == check_* ]]; then "$1"; else installed "$1"; fi; }

# added_candidates: "item|label" for each thing on this computer the dotfiles may have added
# (what dot uninstall --apps can offer), with the item as the record writes it (lib.sh:
# ADDED_FILE). For a computer set up before the record was kept: dot check's fixes ask you
# which of these the dotfiles added.
added_candidates() {
  local entry choice name p pkgs desk uuid id
  for entry in "${APPS[@]}"; do
    IFS='|' read -r choice name _ <<< "$entry"
    [[ -n "${APP_PARTS[$choice]:-}" ]] || continue
    pkgs="${APP_PARTS[$choice]%%|*}"
    for p in $pkgs; do installed "$p" && { echo "$choice|${name%% (*}"; break; }; done
  done
  # Not the ones Ubuntu's own desktop includes (like Backups), as in uninstall.sh
  desk="$(apt-cache depends ubuntu-desktop ubuntu-desktop-minimal 2>/dev/null | awk '/(Depends|Recommends):/ {print $2}')"
  for p in $(list_of apt-packages.txt); do
    installed "$p" && ! grep -qxF "$p" <<< "$desk" && echo "pkg:$p|$p (Ubuntu app)"
  done
  for p in "${TOOLS[@]}"; do
    case "$p" in git|curl|gum|gh|stow|flatpak) continue ;; esac   # general tools stay anyway
    installed "$p" && echo "pkg:$p|$p (terminal tool)"
  done
  if have flatpak; then
    while IFS=$'\t' read -r id name; do
      grep -qxF "$id" "$SETUP/flatpaks.txt" && echo "flatpak:$id|$name (Flatpak)"
    done < <(flatpak list --app --columns=application,name 2>/dev/null)
  fi
  for uuid in $(list_of gnome-extensions.txt); do
    [[ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]] && echo "extension:$uuid|$uuid (GNOME extension)"
  done
  grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null && echo "firewall|the firewall (switched on)"
  if have snap && ! snap list firefox >/dev/null 2>&1; then echo "snapfirefox|Ubuntu's Snap Firefox (removed)"; fi
  return 0
}

# check.sh and uninstall.sh load this file only for APPS, APP_PARTS and the checks above.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

# --- Downloads and update sources --------------------------------------------------------
# Download a file (also done in dry-run mode, to check the link still works).
fetch() { curl -fsSL --retry 3 -o "$1" "$2"; }

# key_ok <key file> <expected fingerprint>...: the file must hold exactly these keys, no
# more and no fewer. (apt trusts every key in a signing-key file, so a file with an extra
# key added would otherwise pass a check of only the expected ones.) Most makers sign with
# one key; Brave's file holds its three release keys.
key_ok() {
  local file="$1" found want; shift
  # Each key's own fingerprint: the fpr line right after its pub line (not its subkeys').
  found="$(gpg --show-keys --with-colons "$file" 2>/dev/null \
    | awk -F: '$1=="pub"{p=1; next} $1=="fpr"&&p{print $10; p=0}' | sort)"
  want="$(printf '%s\n' "$@" | sort)"
  [[ -n "$found" && "$found" == "$want" ]] && return 0
  echo "    the signing key file holds $(grep -c . <<< "$found") key(s) (${found//$'\n'/, }); expected only $*. Not installing." >&2
  return 1
}

# package_in <Packages file> <package>: its file path and SHA-256 in an apt package index
package_in() {
  awk -v p="$2" '
    $1=="Package:"{x=($2==p)} x&&$1=="Filename:"{f=$2} x&&$1=="SHA256:"{s=$2}
    END{print f, s}' "$1"
}

# signed_source <name> <key> <fingerprints> <repo URL> <suite>: fetch a maker's key (a URL,
# or a key file kept in setup/keys/), check it holds exactly the key(s) with those
# fingerprints (space-separated when there are several), and
# check the source's package list (InRelease) is signed with one of them. Leaves the key as
# $TMP/<name>.key (as given) and $TMP/<name>.gpg (binary; gpg --dearmor passes a key that's
# already binary through as it is), and only the signed part of the
# list in $TMP/<name>.Release. Done in dry runs too, so a maker changing its key or its
# source fails GitHub's weekly check instead of a new computer.
signed_source() {
  local name="$1" key="$2" fpr="$3" repo="${4%/}" suite="$5"
  local fprs; read -ra fprs <<< "$fpr"
  if [[ "$key" == http* ]]; then fetch "$TMP/$name.key" "$key"; else cp "$key" "$TMP/$name.key"; fi
  key_ok "$TMP/$name.key" "${fprs[@]}" || return 1
  gpg --dearmor < "$TMP/$name.key" > "$TMP/$name.gpg"
  fetch "$TMP/$name.InRelease" "$repo/dists/$suite/InRelease"
  if ! gpgv --keyring "$TMP/$name.gpg" --output "$TMP/$name.Release" "$TMP/$name.InRelease" >/dev/null 2>&1; then
    echo "    $repo isn't signed with the expected key. Not installing." >&2
    return 1
  fi
  echo "    update source signed with the expected key"
}

# add_source <source file> <keyring file> <key> <fingerprint> <source>: add a maker's update
# source (<source> is the file's text: a deb line, or deb822 fields) as $APT_SOURCES/<source
# file>, trusting only <key> (see signed_source, which checks it first). A keyring file
# ending in .gpg gets the key in binary form. Then the package lists are refreshed.
add_source() {
  local file="$1" keyring="$2" key="$3" fpr="$4" src="$5" repo suite
  read -r repo suite < <(awk '/^URIs:/ {r = $2} /^Suites:/ {s = $2}
    /^deb / {for (i = 2; i <= NF; i++) if ($i ~ /^https?:/) {r = $i; s = $(i + 1); break}}
    END {print r, s}' <<< "$src")
  signed_source "$file" "$key" "$fpr" "$repo" "$suite" || return 1
  if [[ "$keyring" == *.gpg ]]; then cp "$TMP/$file.gpg" "$TMP/$file.keyring"; else cp "$TMP/$file.key" "$TMP/$file.keyring"; fi
  printf '%s\n' "$src" > "$TMP/$file"
  run sudo install -m 644 "$TMP/$file.keyring" "$APT_KEYS/$keyring"
  run sudo install -m 644 "$TMP/$file" "$APT_SOURCES/$file"
  apt_get update
}

# --- Apps --------------------------------------------------------------------------
# Anthropic signs Claude Desktop's and Claude Code's update sources with this key.
ANTHROPIC_KEY=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

install_chrome() {
  # Google's update source: the same file Chrome itself writes and then keeps up to date.
  add_source google-chrome.sources google-chrome.gpg https://dl.google.com/linux/linux_signing_key.pub \
    EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 "X-Repolib-Name: Google Chrome
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: $APT_KEYS/google-chrome.gpg"
  apt_get install -y google-chrome-stable
}

# Brave signs its Linux release source with these keys, all three in the keyring file it
# publishes (and lists on brave.com/signing-keys): the 2022 key, which signs it now, and
# two from 2025 for when it moves to a new one.
BRAVE_KEYS="DBF1A116C220B8C7164F98230686B78420038257 47D32A74E9A9E013A4B4926C68D513D36A73CD96 B2A3DCA350E67256740DF904DE4EC67BE4B0DCA0"

install_brave_origin() {
  # Brave Origin: Brave without Leo AI, Rewards, the wallet, the VPN and News (free on
  # Linux). From Brave's own release source, the one regular Brave uses too: the same
  # file names and contents as Brave's install steps (brave.com/origin/linux), so it
  # matches if Brave was set up from there before. Then its settings (telemetry off,
  # tracking protections locked on: docs/apps.md), applied from Brave's next start.
  if ! installed brave-origin; then
    add_source brave-browser-release.sources brave-browser-archive-keyring.gpg \
      https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg "$BRAVE_KEYS" "Types: deb
URIs: https://brave-browser-apt-release.s3.brave.com
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: $APT_KEYS/brave-browser-archive-keyring.gpg" || return 1
    apt_get install -y brave-origin
  fi
  local f
  for f in "$BRAVE_POLICY" "$BRAVE_RECOMMENDED"; do
    run sudo install -D -m 644 "$DOTFILES/system/etc/$f" "/etc/$f"
  done
  echo "    settings: /etc/brave/policies/ (see them at brave://policy)"
}

install_vscode() {
  # Microsoft's update source: the same file VS Code writes and keeps up to date when
  # this question is answered "yes".
  echo "code code/add-microsoft-repo boolean true" > "$TMP/code.debconf"
  run sudo debconf-set-selections "$TMP/code.debconf"
  add_source vscode.sources microsoft.gpg https://packages.microsoft.com/keys/microsoft.asc \
    BC528686B50D79E339D3721CEB3E94ADBE1229CF "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: $APT_KEYS/microsoft.gpg"
  apt_get install -y code
}

install_claude() {
  add_source claude-desktop.list claude-desktop-archive-keyring.asc \
    https://downloads.claude.ai/claude-desktop/key.asc "$ANTHROPIC_KEY" \
    "deb [arch=amd64,arm64 signed-by=$APT_KEYS/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
  apt_get install -y claude-desktop
}

install_chatgpt() {
  # OpenAI's ChatGPT desktop app (with Codex), from OpenAI's own update source. OpenAI
  # ships its signing key inside the app's package, not at a download address, so a copy
  # is kept in setup/keys/chatgpt.asc (it's public), pinned to this fingerprint.
  add_source chatgpt.sources chatgpt-archive-keyring.gpg "$SETUP/keys/chatgpt.asc" \
    3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4 "X-Repolib-Name: ChatGPT
Types: deb
URIs: https://persistent.oaistatic.com/codex-app-prod/linux/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: $APT_KEYS/chatgpt-archive-keyring.gpg"
  apt_get install -y chatgpt
}

install_claude_code() {
  # Claude Code (the `claude` command for the terminal), from Anthropic's own update
  # source, signed with the same key as Claude Desktop's. Updates come with apt.
  add_source claude-code.list claude-code.asc https://downloads.claude.ai/keys/claude-code.asc "$ANTHROPIC_KEY" \
    "deb [arch=amd64,arm64 signed-by=$APT_KEYS/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main"
  apt_get install -y claude-code
}

install_protonvpn() {
  # Proton's setup package adds Proton's update source. Checked link by link: Proton's
  # package list is signed with its key (this fingerprint), it gives the checksum of the
  # package index, and the index gives the setup package's checksum.
  local base=https://repo.protonvpn.com/debian index=main/binary-all/Packages sum path sha
  signed_source protonvpn "$base/public_key.asc" 84B0D3492C76C9C6F5873C18EDA3E22630349F1C "$base" stable || return 1
  sum="$(awk -v f="$index" '/^SHA256:/ {s = 1; next} /^[^ ]/ {s = 0} s && $3 == f {print $1}' "$TMP/protonvpn.Release")"
  fetch_checked "$base/dists/stable/$index" "$sum" "$TMP/protonvpn.Packages" "Downloading Proton's package index"
  read -r path sha < <(package_in "$TMP/protonvpn.Packages" protonvpn-stable-release)
  [[ -n "$path" && -n "$sha" ]] || { echo "    couldn't find Proton's setup package" >&2; return 1; }
  fetch_checked "$base/$path" "$sha" "$TMP/protonvpn-release.deb" "Downloading Proton's setup package"
  echo "    setup package matches Proton's signed package list"
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
  add_source onlyoffice.list onlyoffice.gpg https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
    E09CA29F6E178040EF22B4098320CA65CB2DE8E5 \
    "deb [signed-by=$APT_KEYS/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main"
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
  for p in "${missing[@]}"; do mark_added "pkg:$p"; done   # for dot uninstall
}

setup_weekly_updates() {
  # Updates everything once a week and shows a notification if it fails or gets stuck.
  install_job cron.weekly/system-update
  echo "    runs once a week; log: /var/log/system-update.log"
}

setup_login_screen() {
  # Someone else's profile for the login screen stays as it is (only ours is replaced).
  if [[ -f "$GDM_PROFILE" ]] && ! head -1 "$GDM_PROFILE" | grep -q '^# Written by ~/dotfiles'; then
    echo "    $GDM_PROFILE exists and isn't from the dotfiles; leaving the login screen alone" >&2
    return 1
  fi
  login_settings > "$TMP/90-dotfiles"
  login_profile > "$TMP/gdm-profile"
  run sudo install -D -m 644 "$SETUP/wallpaper/login-blurred.jpg" "$LOGIN_BG"
  run sudo install -D -m 644 "$TMP/gdm-profile" "$GDM_PROFILE"
  run sudo install -D -m 644 "$TMP/90-dotfiles" "$GDM_SETTINGS"
  run sudo dconf update
  echo "    shows from the next login screen (log out, or restart)"
}

setup_monthly_cleanup() {
  # Removes unused packages (apt autoremove) and Flatpak runtimes once a month.
  install_job cron.monthly/system-cleanup
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
  # Ubuntu's steam-installer names its shortcut "Install Steam" even once Steam is
  # installed, so the copy is renamed "Steam" (copies made before this are fixed too).
  if ! grep -q '^PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT" 2>/dev/null \
     || grep -q '^Name=Install Steam$' "$STEAM_SHORTCUT"; then
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "    would make Steam's shortcut use the NVIDIA card and name it Steam: $STEAM_SHORTCUT"
    else
      mkdir -p "$(dirname "$STEAM_SHORTCUT")"
      if ! grep -q '^PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT" 2>/dev/null; then
        cp /usr/share/applications/steam.desktop "$STEAM_SHORTCUT"
        sed -i '/^\[Desktop Entry\]/a PrefersNonDefaultGPU=true' "$STEAM_SHORTCUT"
      fi
      sed -i 's/^Name=Install Steam$/Name=Steam/' "$STEAM_SHORTCUT"
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
    mark_added snapfirefox   # (removed, not added): dot uninstall may put it back
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

# --- Main (the clock check, clock_step, is in lib.sh) ----------------------------------

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
chmod 755 "$TMP"   # lets apt's download user read the .deb files

for tool in curl gpg sha256sum; do
  command -v "$tool" >/dev/null || { echo "Needs $tool first: sudo apt install $tool"; exit 1; }
done

title="Apps and system jobs"; [[ "$DRY_RUN" == 1 ]] && title+=" (dry run: installs nothing)"
header "$title" \
  "Apps from their makers' official sources, kept updated by apt:" \
  "Chrome, Brave Origin, VS Code, Claude Desktop, Claude Code, ChatGPT," \
  "Proton VPN, OBS, ONLYOFFICE, Steam and Ubuntu apps; the NVIDIA driver," \
  "weekly updates, monthly clean-up, the login screen's look, the" \
  "firewall and no Snap Firefox." \
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
added_init   # before anything is installed: what was already here isn't counted as added

# What's already done, not needed, or still to do (quietly, before anything runs).
STATUS=()
for i in "${!APPS[@]}"; do
  IFS='|' read -r choice _ check _ _ <<< "${APPS[$i]}"
  if ! entry_chosen "$choice"; then STATUS[i]=notchosen; continue; fi
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
    IFS='|' read -r _ name _ _ verb <<< "${APPS[$i]}"
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
  IFS='|' read -r _ name _ _ verb <<< "$entry"; titles+=("${verb:-Install}: $name")
done
ui_plan "${titles[@]}"

for i in "${!APPS[@]}"; do
  IFS='|' read -r choice name check fn verb <<< "${APPS[$i]}"
  verb="${verb:-Install}"
  step_begin "$verb: $name"
  if [[ "${STATUS[i]}" == notchosen ]]; then step_end skip "not chosen"; continue; fi
  NOT_NEEDED=0
  if is_done "$check"; then
    if (( NOT_NEEDED )); then step_end notneeded; continue; fi
    if [[ "$DRY_RUN" != 1 ]]; then step_end already; continue; fi
    note "already done (checking the download anyway)"
  fi
  if (( CHECKLIST )); then
    # Only what was to do at the start was in the checklist. One that became needed since
    # (Steam on the NVIDIA card, once Steam is installed) follows from what you ticked.
    [[ "$CHOSEN" == *" $i "* || "${STATUS[i]}" != todo ]] || { step_end skip "not chosen"; continue; }
  elif [[ "$DRY_RUN" != 1 ]] && ! ask "$verb $name?"; then
    step_end skip "you chose not to"; continue
  fi
  ( set -e; "$fn" )
  rc=$?
  if (( rc != 0 )); then step_end fail "exit code $rc"; else step_end ok; fi
  # An app from its maker that wasn't here before (ones already installed were skipped
  # above), for dot uninstall. Ubuntu apps, the firewall and Snap Firefox mark their own.
  if (( rc == 0 )) && [[ "$choice" == app:* ]]; then mark_added "$choice"; fi
done

summary; ok=$?
if [[ "$DRY_RUN" != 1 && "$UI_NESTED" == 0 ]]; then
  echo
  note "Installed VS Code? Run ~/code/github/dotfiles/bin/install.sh again to add its extensions."
  note "Installed Steam? Its first start downloads the rest of Steam, then you sign in."
fi
exit "$ok"
