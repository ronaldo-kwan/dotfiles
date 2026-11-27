#!/usr/bin/env bash
# Tests the desktop part for real: install.sh loads the saved desktop settings (setup/*.dconf),
# the dock and the wallpaper; then uninstall.sh puts everything back to Ubuntu's defaults.
# Checks every saved setting both times. It CHANGES the desktop settings, so it only runs in
# GitHub's checks (CI=true), in a container without a screen, started like this:
#   dbus-run-session -- bash scripts/test-desktop.sh

set -uo pipefail
[[ "${CI:-}" == true ]] || { echo "Only for GitHub's checks: this changes the desktop settings."; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib.sh
source "$ROOT/bin/lib.sh"   # DCONF_FILES, fill_home, WALLPAPER, SETUP
export NO_COLOR=1 DOT_PLAIN=1 DOTFILES_CHOICES=desktop

fails=0
bad() { printf '  ✘ %s\n' "$*"; fails=$((fails + 1)); }

# saved_keys: every setting in the setup/*.dconf files, as "<dconf path><TAB><value>",
# with @HOME@ filled in (read independently of install.sh and uninstall.sh).
saved_keys() {
  local e
  for e in "${DCONF_FILES[@]}"; do
    [[ -f "$SETUP/${e%%|*}" ]] || continue
    fill_home "$SETUP/${e%%|*}" | python3 -I -c '
import re, sys
prefix, section = sys.argv[1], None
for line in sys.stdin.read().splitlines():
    if m := re.match(r"\[(.*)\]$", line.strip()):
        section = m.group(1).strip("/")
    elif section is not None and (m := re.match(r"([A-Za-z0-9-]+)=(.*)$", line)):
        print((prefix + section + "/" + m.group(1)).replace("//", "/") + "\t" + m.group(2))' "${e#*|}"
  done
}
mapfile -t KEYS < <(saved_keys)
(( ${#KEYS[@]} > 20 )) || { echo "✘ found only ${#KEYS[@]} saved settings in setup/"; exit 1; }
favorites="$(cat "$SETUP/dock-favorites.txt")"
wall_uri="'file://$WALLPAPER'"

echo "== install.sh (desktop only)"
"$ROOT/bin/install.sh" --yes || bad "install.sh failed"
n=0
for kv in "${KEYS[@]}"; do
  key="${kv%%$'\t'*}" want="${kv#*$'\t'}" got="$(dconf read "${kv%%$'\t'*}")"
  [[ "$got" == "$want" ]] || bad "$key is $got, saved as $want"
  n=$((n + 1))
done
echo "  checked $n saved settings"
[[ "$(gsettings get org.gnome.shell favorite-apps)" == "$favorites" ]] || bad "the dock isn't the saved one"
[[ "$(gsettings get org.gnome.desktop.background picture-uri)" == "$wall_uri" ]] || bad "wallpaper not set"
cmp -s "$SETUP/wallpaper/${WALLPAPER##*/}" "$WALLPAPER" || bad "wallpaper file not copied"
[[ -L "$HOME/.config/fontconfig/fonts.conf" ]] || bad "fontconfig settings not linked"
# Ptyxis's colours: here, as on a new computer, Ptyxis has never been opened, so it has
# no profile yet; install.sh makes one with the saved palette.
ptyxis_profile() { dconf read /org/gnome/Ptyxis/default-profile-uuid | tr -d "'"; }
saved_palette="$(sed -n 's/^# ptyxis-palette=//p' "$SETUP/desktop-settings.dconf")"
profile="$(ptyxis_profile)"
if [[ -n "$saved_palette" ]]; then
  [[ -n "$profile" && "$(dconf read "/org/gnome/Ptyxis/Profiles/$profile/palette")" == "$saved_palette" ]] \
    || bad "Ptyxis has no profile with the saved colours ($saved_palette)"
  [[ "$(dconf read /org/gnome/Ptyxis/profile-uuids)" == "['$profile']" ]] || bad "Ptyxis's profile isn't in its list"
fi

echo "== install.sh again (must change nothing and still pass)"
"$ROOT/bin/install.sh" --yes >/dev/null || bad "install.sh failed the second time"
[[ "$(ptyxis_profile)" == "$profile" && "$(dconf read /org/gnome/Ptyxis/profile-uuids)" == "${profile:+['$profile']}" ]] \
  || bad "install.sh made Ptyxis another profile the second time"

echo "== uninstall.sh"
"$ROOT/bin/uninstall.sh" --yes || bad "uninstall.sh failed"
n=0
for kv in "${KEYS[@]}"; do
  key="${kv%%$'\t'*}"
  [[ "$key" == *deja-dup* ]] && continue    # Backups' settings stay on purpose
  [[ -z "$(dconf read "$key")" ]] || bad "$key wasn't reset: $(dconf read "$key")"
  n=$((n + 1))
done
echo "  checked $n settings are back to Ubuntu's defaults"
[[ -z "$(dconf read /org/gnome/shell/favorite-apps)" ]] || bad "the dock wasn't reset"
[[ -z "$(dconf read /org/gnome/desktop/background/picture-uri)" ]] || bad "the wallpaper setting wasn't reset"
[[ ! -e "$WALLPAPER" ]] || bad "the wallpaper file is still there"
[[ ! -e "$HOME/.config/fontconfig/fonts.conf" ]] || bad "fontconfig link still there"

echo
if (( fails )); then echo "✘ $fails problem(s)"; exit 1; fi
echo "✔ the desktop settings go on and come off as saved"
