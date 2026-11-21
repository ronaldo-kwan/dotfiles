#!/usr/bin/env bash
# Quick checks of the helpers every script shares (lib.sh) and of the app table in
# install-apps.sh. Changes nothing outside a temporary folder; needs no network or sudo.
# Run by GitHub's checks (.github/workflows/check.yml), or by hand:
#   bash scripts/test-helpers.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" NO_COLOR=1 DOT_PLAIN=1 UI_LOG="$T/ui.log"   # no saved choices, no colours
unset DOTFILES_CHOICES DOTFILES_SKIP DRY_RUN
mkdir -p "$HOME"
# shellcheck source=../lib.sh
source "$ROOT/lib.sh"
# shellcheck source=../install-apps.sh
source "$ROOT/install-apps.sh"   # only loads APPS, APP_PARTS and the checks

fails=0 n=0
# t "what" command...: one check; passes when the command succeeds
t() {
  local what="$1"; shift
  n=$((n + 1))
  if "$@"; then printf '  ✔ %s\n' "$what"; else printf '  ✘ %s\n' "$what"; fails=$((fails + 1)); fi
}
same() { [[ "$1" == "$2" ]] || { printf '      expected: %q\n      got:      %q\n' "$2" "$1"; return 1; }; }
not() { ! "$@"; }

echo "Choices"
DOTFILES_CHOICES="" DOTFILES_SKIP=""
t "nothing chosen means everything" chosen app:steam
DOTFILES_CHOICES="terminal pkg:vlc" DOTFILES_SKIP=""
t "a chosen group" chosen terminal
t "an unchosen group" not chosen desktop
t "chosen_any finds pkg:" chosen_any pkg:
t "entry_chosen pkg:* = any Ubuntu app" entry_chosen 'pkg:*'
t "entry_chosen of an unchosen app" not entry_chosen app:chrome
DOTFILES_CHOICES="" DOTFILES_SKIP="app:steam"
t "a skipped app" not chosen app:steam
t "everything else with a skip list" chosen app:chrome

echo "Lists in setup/"
SETUP_REAL="$SETUP" SETUP="$T/setup"; mkdir -p "$SETUP"
printf '# a comment\nvlc   # the player\n\n-snapd   # kept off on purpose\n  gimp\n' > "$SETUP/apt-packages.txt"
t "list_of drops comments, blanks and -name" same "$(list_of apt-packages.txt | tr '\n' ' ')" "vlc gimp "
DOTFILES_CHOICES="pkg:gimp" DOTFILES_SKIP=""
t "chosen_from keeps only chosen entries" same "$(chosen_from apt-packages.txt pkg:)" "gimp"
SETUP="$SETUP_REAL"
DOTFILES_CHOICES="" DOTFILES_SKIP=""

echo "Config files (stow packages)"
mapfile -d '' -t files < <(config_files "${PACKAGES[@]}")
t "config_files lists every file in the packages" \
  same "${#files[@]}" "$(for p in "${PACKAGES[@]}"; do find "$DOTFILES/$p" -type f; done | wc -l)"
t "each is <package>/<path in home>, and exists" \
  bash -c 'for f in "${@:2}"; do [[ -f "$1/$f" && "$f" == */* ]] || exit 1; done' _ "$DOTFILES" "${files[@]}"
t "bash/.bashrc is linked as ~/.bashrc" bash -c 'printf "%s\n" "${@:2}" | grep -qx "bash/.bashrc"' _ x "${files[@]}"

echo "Dry runs"
t "run only prints in a dry run" same "$(DRY_RUN=1 run touch "$T/x"; [[ -e "$T/x" ]] && echo made)" "    would run: touch $T/x"
t "run runs otherwise" bash -c 'source "$1/lib.sh"; run touch "$2/y"; [[ -e "$2/y" ]]' _ "$ROOT" "$T"
t "run_quiet hides output when it runs" same "$(run_quiet echo hello)" ""
t "did is silent in a dry run" same "$(DRY_RUN=1 did "made it")" ""
t "did says what changed otherwise" same "$(did "made it")" "    made it"
t "copy_into only says so in a dry run" \
  same "$(DRY_RUN=1 copy_into "$T/c" "$ROOT/LICENSE"; [[ -e "$T/c" ]] && echo made)" "    would copy 1 file(s) into $T/c"

echo "apt-get labels"
labels() { apt_wait() { :; }; quiet() { echo "$1"; }; apt_get "$@"; }
t "update"       same "$(labels update)" "Refreshing package lists"
t "full-upgrade" same "$(labels -y full-upgrade)" "Upgrading all packages"
t "install"      same "$(labels install -y /tmp/x/chrome.deb vlc)" "Installing chrome.deb vlc"
t "remove"       same "$(labels remove -y firefox)" "Removing firefox"
t "a dry run prints the command" same "$(DRY_RUN=1 apt_get install -y gum)" "    would run: sudo apt-get install -y gum"

echo "Downloads"
printf 'hello\n' > "$T/src.txt"
sum="$(sha256sum "$T/src.txt" | cut -d' ' -f1)"
kept() { fetch_checked "file://$T/src.txt" "$sum" "$T/ok.txt" && same "$(cat "$T/ok.txt")" hello; }
refused() {
  not fetch_checked "file://$T/src.txt" 0000 "$T/bad.txt" 2>/dev/null \
    && [[ ! -e "$T/bad.txt" ]] && not compgen -G "$T/bad.txt.*" >/dev/null   # no file, no leftover
}
t "fetch_checked keeps a matching file" kept
t "fetch_checked refuses a changed file" refused

echo "Other helpers"
printf 'path=@HOME@/x\n' > "$T/saved"
t "fill_home" same "$(fill_home "$T/saved")" "path=$HOME/x"
git init -q "$T/repo" && git -C "$T/repo" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
t "repo_state of a clean repo without upstream" same "$(repo_state "$T/repo")" ""
touch "$T/repo/new"
t "repo_state with a new file" same "$(repo_state "$T/repo")" "uncommitted"

echo "App table (install-apps.sh)"
t "every app: entry has its APP_PARTS" bash -c '
  for e in "${@:2}"; do c="${e%%|*}"; [[ "$c" != app:* ]] || [[ " $1 " == *" $c "* ]] || { echo "      missing APP_PARTS for $c"; exit 1; }; done' \
  _ "${!APP_PARTS[*]}" "${APPS[@]}"
t "every APP_PARTS entry is in APPS" bash -c '
  for c in $1; do printf "%s\n" "${@:2}" | grep -q "^$c|" || { echo "      $c is in APP_PARTS but not APPS"; exit 1; }; done' \
  _ "${!APP_PARTS[*]}" "${APPS[@]}"
t "every check and install function in APPS exists" bash -c '
  for e in "${@:2}"; do IFS="|" read -r _ _ check fn _ <<< "$e"
    for f in "$fn" $([[ "$check" == check_* ]] && echo "$check"); do
      grep -q "^$f() {" "$1" || { echo "      no function $f"; exit 1; }; done; done' \
  _ "$ROOT/install-apps.sh" "${APPS[@]}"
t "APP_PACKAGES has each app's packages" bash -c '[[ " $* " == *" google-chrome-stable "* && " $* " == *" steam-launcher "* ]]' _ "${APP_PACKAGES[@]}"
t "every DCONF_FILES file is in setup/" bash -c 'for e in "${@:2}"; do [[ -f "$1/${e%%|*}" ]] || exit 1; done' _ "$SETUP" "${DCONF_FILES[@]}"

echo
if (( fails )); then echo "✘ $fails of $n checks failed"; exit 1; fi
echo "✔ all $n checks passed"
