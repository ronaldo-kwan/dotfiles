#!/usr/bin/env bash
# Install apps that don't come from Ubuntu: Chrome, VS Code, Claude Desktop,
# Proton VPN and OBS Studio. Each one is installed from its maker's official
# download source, which then keeps it updated through `sudo apt upgrade`.
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

say()  { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
skip() { printf '    skipped: %s\n' "$*"; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

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

# --- Main --------------------------------------------------------------------------

APPS=(
  "Google Chrome|google-chrome-stable|install_chrome"
  "VS Code|code|install_vscode"
  "Claude Desktop|claude-desktop|install_claude"
  "Proton VPN|proton-vpn-gnome-desktop|install_protonvpn"
  "OBS Studio|obs-studio|install_obs"
)

for tool in curl gpg sha256sum; do
  command -v "$tool" >/dev/null || { echo "Needs $tool first: sudo apt install $tool"; exit 1; }
done

[[ "$DRY_RUN" == 1 ]] && echo "Dry run: downloads are checked, but nothing is installed."
if [[ "$DRY_RUN" != 1 ]]; then
  echo "This installs apps from their makers' official sources and needs your password (sudo)."
  sudo -v || exit 1
fi

for entry in "${APPS[@]}"; do
  IFS='|' read -r name pkg fn <<< "$entry"
  say "$name"
  if installed "$pkg"; then
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
exit 0
