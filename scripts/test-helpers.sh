#!/usr/bin/env bash
# Quick checks of the helpers every script shares (lib.sh) and of the app table in
# install-apps.sh. Changes nothing outside a temporary folder; needs no network or sudo.
# Run by GitHub's checks (.github/workflows/check.yml), or by hand:
#   bash scripts/test-helpers.sh
# shellcheck disable=SC2034  # DOTFILES_CHOICES and DOTFILES_SKIP are set here for chosen (lib.sh)

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" NO_COLOR=1 DOT_PLAIN=1 UI_LOG="$T/ui.log"   # no saved choices, no colours
# UTF-8 whatever the terminal's locale: the spinner and panel count their ✔ ⠋ … as one
# character each, which they only are in UTF-8 (without a locale set, they're bytes).
export LC_ALL=C.UTF-8
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
dry_kept() { DRY_RUN=1 fetch_checked "file://$T/src.txt" "$sum" "$T/dry.txt" >/dev/null && [[ -f "$T/dry.txt" ]]; }
t "fetch_checked still downloads and checks in a dry run" dry_kept

echo "Other helpers"
printf 'path=@HOME@/x\n' > "$T/saved"
t "fill_home" same "$(fill_home "$T/saved")" "path=$HOME/x"
git init -q "$T/repo" && git -C "$T/repo" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
t "repo_state of a clean repo without upstream" same "$(repo_state "$T/repo")" ""
touch "$T/repo/new"
t "repo_state with a new file" same "$(repo_state "$T/repo")" "uncommitted"

echo "Progress panel (in a terminal)"
# The pinned step list only shows in a real terminal, which GitHub's checks don't have, so
# this runs two steps in one made by `script`. A step with a spinner after a quick one used
# to fail with "exit code 1" and no message (a panel redraw under set -e).
if have script; then
  cat > "$T/panel.sh" <<EOF
set -uo pipefail
source "$ROOT/lib.sh"
fast() { :; }
slow() { quiet "a quiet command" sleep 0.3; echo "    SPINNER-STEP-FINISHED"; }
run_steps "Fast step|fast" "Step with a spinner|slow"
summary
EOF
  # As if started on its own (UI_DEPTH would make it a nested script, which has no panel).
  panel="$(script -qc "stty rows 40 cols 100; env -u NO_COLOR -u DOT_PLAIN -u UI_LOG -u UI_DEPTH TERM=xterm-256color bash '$T/panel.sh'" /dev/null 2>&1 | tr -d '\r')"
  t "the panel shows (its · marks a step still to come)" grep -q '· Step with a spinner' <<< "$panel"
  t "a spinner step after a quick step finishes" grep -q 'SPINNER-STEP-FINISHED' <<< "$panel"
  # The script's own EXIT trap still runs after the panel's, even with a ' in it.
  printf '%s\n' 'set -uo pipefail' "source \"$ROOT/lib.sh\"" \
    "trap 'echo \"OWN-TRAP: it'\\''s here, code \$?\"' EXIT" \
    'fast() { :; }; run_steps "One step|fast"; summary; exit 3' > "$T/trap.sh"
  traps="$(script -qc "stty rows 40 cols 100; env -u NO_COLOR -u DOT_PLAIN -u UI_LOG -u UI_DEPTH TERM=xterm-256color bash '$T/trap.sh'" /dev/null 2>&1 | tr -d '\r')"
  t "the script's own EXIT trap runs too (with a ' in it, and its exit code)" grep -q "OWN-TRAP: it's here, code 3" <<< "$traps"
  # In a narrow window the spinner line must still fit on one line (a longer one wraps,
  # leaving a copy at every redraw): its label is cut to the width.
  printf 'source "%s/lib.sh"\nquiet "Installing 9 Flatpak apps (already installed ones are skipped)" sleep 0.3\n' "$ROOT" > "$T/narrow.sh"
  script -qc "stty rows 30 cols 40; env -u NO_COLOR -u DOT_PLAIN -u UI_LOG -u UI_DEPTH TERM=xterm-256color bash '$T/narrow.sh'" "$T/narrow.out" >/dev/null 2>&1
  widest="$(python3 -I -c '
import re, sys
raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace").split("\n", 1)[1]
plain = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", raw)
frames = [f for f in plain.split("\r") if re.search("[\u280b-\u283f]", f)]
print(max((len(f.rstrip()) for f in frames), default=0))' "$T/narrow.out")"
  t "the spinner line fits a 40-column window (widest: $widest)" bash -c '(( $1 > 0 && $1 < 40 ))' _ "$widest"
else
  echo "  (skipped: no script command)"
fi

echo "Terminal configs"
# Every custom-shader the Ghostty config names is a file next to it (Ghostty only logs a
# missing or broken shader, so nothing else would notice).
shaders_exist() {
  local s ok=0
  while read -r s; do
    [[ -f "$ROOT/ghostty/.config/ghostty/$s" ]] || { echo "      missing: $s"; ok=1; }
  done < <(sed -n 's/^custom-shader *= *//p' "$ROOT/ghostty/.config/ghostty/config")
  return "$ok"
}
t "Ghostty's shaders are in the ghostty package" shaders_exist

echo "NVIDIA"
# When the driver isn't running, nvidia-smi prints its error message as output; the driver
# version must then come from the installed package (or be empty), never be that message.
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "NVIDIA-SMI has failed because it could not communicate with the NVIDIA driver."\nexit 9\n' > "$T/bin/nvidia-smi"
chmod +x "$T/bin/nvidia-smi"
major="$(PATH="$T/bin:$PATH" nvidia_major)"
t "nvidia_major ignores nvidia-smi's error text (got: ${major:-empty})" bash -c '[[ -z "$1" || "$1" =~ ^[0-9]+$ ]]' _ "$major"

echo "Login screen"
# Its theme, accent and font come from setup/gnome-desktop.dconf; if a name there changed,
# they'd silently go missing.
login_keys() { [[ "$(login_settings | grep -cE '^(color-scheme|accent-color|font-name)=')" == 3 ]]; }
t "the login screen gets the desktop's theme, accent and font" login_keys
profile_ok() { [[ ! -f /usr/share/dconf/profile/gdm || "$(login_profile | grep -cx "system-db:gdm")" == 1 ]]; }
t "its profile is Ubuntu's plus system-db:gdm (where Ubuntu's exists)" profile_ok
t "its background is in the repo" test -f "$SETUP/wallpaper/login-blurred.jpg"

# Functions from scripts that run as soon as they start: load just the function.
# shellcheck source=/dev/null  # (a function cut from the script; shellcheck checks the script itself)
load_fn() { source <(sed -n "/^$2() {/,/^}/p" "$ROOT/$1"); }

echo "Secret check (.githooks/pre-commit)"
git init -q "$T/secrets"
# hook_on "line": does the secret check stop a commit that adds this line?
hook_on() {
  printf '%s\n' "$1" > "$T/secrets/f.txt"
  git -C "$T/secrets" add f.txt
  local rc=0; (cd "$T/secrets" && bash "$ROOT/.githooks/pre-commit" >/dev/null 2>&1) || rc=$?
  git -C "$T/secrets" rm -q --cached f.txt
  return "$rc"
}
# The made-up secrets are put together here, so this file itself never holds one (CI
# runs the secret check on every file).
gh36="ghp_$(printf 'a%.0s' {1..36})" oai="$(printf 'Ab1_-%.0s' {1..8})" K=Key P=word
t "stops a GitHub token" not hook_on "TOKEN=$gh36"
t "stops a token on a line that ends in false" not hook_on "{\"token\": \"$gh36\", \"debug\": false}"
t "stops a real setting on a line that ends in true" not hook_on "{\"api$K\":\"abcdef123456\",\"enabled\":true}"
t "stops an OpenAI sk-proj- key" not hook_on "OPENAI=sk-proj-$oai"
t "stops an OpenAI sk-svcacct- key" not hook_on "x sk-svcacct-$oai"
t "stops a private key" not hook_on "-----BEGIN OPENSSH PRIVATE ${K^^}-----"
t "stops a password setting" not hook_on "pass$P = hunter2hunter2"
t "lets a placeholder through" hook_on "password = xxxxxxxx"
t "lets a variable through" hook_on 'token: ${GITHUB_TOKEN}'
t "lets <placeholder> through" hook_on 'api_key=<your-api-key>'
t "lets @HOME@ through" hook_on 'password: @HOME@'
t "lets true/false settings through" hook_on '"token": true, "debug": false'
t "lets sk- inside a word through" hook_on "risk-management-of-the-whole-project-today"
g30="$(printf 'Ab1_-%.0s' {1..7})"
t "stops a Google access token (rclone's, say)" not hook_on "x {\"access\":\"ya29.$g30\"}"
t "stops a Google refresh token" not hook_on "refresh: 1//0$g30"
t "lets a URL with 1// in it through" hook_on "see https://example.com/v1//$g30"
# hook_file <name>: does the secret check stop a commit that adds a file with this name?
hook_file() {
  mkdir -p "$T/secrets/$(dirname "$1")"; echo "harmless" > "$T/secrets/$1"
  git -C "$T/secrets" add "$1"
  local rc=0; (cd "$T/secrets" && bash "$ROOT/.githooks/pre-commit" >/dev/null 2>&1) || rc=$?
  git -C "$T/secrets" rm -q --cached "$1"
  return "$rc"
}
for f in rclone.conf sub/credentials.json .npmrc .pypirc .pgpass work.ovpn; do
  t "stops a file named $f" not hook_file "$f"
done
t "lets an ordinary file through" hook_file notes/rclone.md

echo "Saved files put back (install.sh put_file)"
load_fn install.sh put_file
mkdir -p "$T/put"; echo saved > "$T/put/src"; echo mine > "$T/put/conf"
put_file "$T/put/src" "$T/put/conf" >/dev/null
echo changed-by-the-app > "$T/put/conf"
put_file "$T/put/src" "$T/put/conf" >/dev/null
t "the file is the saved one" same "$(cat "$T/put/conf")" saved
t "the first .orig (yours from before) is kept on a second run" same "$(cat "$T/put/conf.orig")" mine
t "the file it replaced the second time is in .prev" same "$(cat "$T/put/conf.prev")" changed-by-the-app

echo "Display settings (install.sh monitors_for_here)"
load_fn install.sh monitors_for_here
mkdir -p "$T/mon"
cat > "$T/mon/two.xml" <<'EOF'
<monitors><configuration>
<monitorspec><connector>DP-1</connector><vendor>DEL</vendor><product>U2720Q</product><serial>@SERIAL@</serial></monitorspec>
<monitorspec><connector>DP-2</connector><vendor>DEL</vendor><product>U2720Q</product><serial>@SERIAL@</serial></monitorspec>
</configuration></monitors>
EOF
# screens "(('connector', 'maker', 'model', 'serial'), [..." ...: what GNOME reports as connected
screens() { printf '#!/bin/sh\necho "(uint32 1, [%s])"\n' "$*" > "$T/bin/gdbus"; chmod +x "$T/bin/gdbus"; }
serials() { PATH="$T/bin:$PATH" monitors_for_here "$1" | grep -o '<serial>[^<]*' | sed 's/<serial>//' | tr '\n' ' '; }
screens "(('DP-1', 'DEL', 'U2720Q', 'AAA'), [()]), (('DP-2', 'DEL', 'U2720Q', 'BBB'), [()])"
t "two identical screens each get their own serial" same "$(serials "$T/mon/two.xml")" "AAA BBB "
screens "(('HDMI-1', 'DEL', 'U2720Q', 'AAA'), [()]), (('HDMI-2', 'DEL', 'U2720Q', 'BBB'), [()])"
t "identical screens that can't be told apart: left alone" not bash -c \
  'source <(sed -n "/^monitors_for_here() {/,/^}/p" "$1/install.sh"); have() { command -v "$1" >/dev/null; }; PATH="$2:$PATH" monitors_for_here "$3" >/dev/null' \
  _ "$ROOT" "$T/bin" "$T/mon/two.xml"
screens "(('eDP-2', 'EDO', 'LEN151WQXGA', 'S1'), [()]), (('HDMI-1', 'MSI', 'MSI MP2412', 'S2'), [()])"
t "a screen on another connector, the only one of its model, still matches" \
  same "$(serials "$SETUP/apps/monitors.xml")" "S1 S2 S1 "

echo "Snapshots (dot save, dot push)"
# A stand-in dconf: `dump` prints one setting, except for a folder with nothing set.
printf '#!/bin/sh\n[ "$1" = dump ] && [ "$2" = /org/gnome/desktop/wm/keybindings/ ] && exit 0\n[ "$1" = dump ] && printf "[/]\\nk=1\\n"\nexit 0\n' > "$T/bin/dconf"
chmod +x "$T/bin/dconf"
dump_ok() { PATH="$T/bin:$PATH" bash "$ROOT/scripts/dump-desktop-settings.sh" > "$T/desktop.dconf" && grep -q '^\[org/gnome/deja-dup\]' "$T/desktop.dconf"; }
t "an empty dconf folder doesn't stop the desktop settings halfway" dump_ok
cp -r "$SETUP" "$T/snap-setup"; before="$(sha256sum < "$T/snap-setup/desktop-settings.dconf")"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/dconf"
snap_rc=0; PATH="$T/bin:$PATH" bash "$ROOT/scripts/snapshot.sh" "$T/snap-setup" >/dev/null 2>&1 || snap_rc=$?
t "a failed read of the desktop settings makes snapshot.sh fail" same "$snap_rc" 1
t "... and leaves the saved desktop-settings.dconf as it was" same "$(sha256sum < "$T/snap-setup/desktop-settings.dconf")" "$before"
t "... with no half-written file left" not test -e "$T/snap-setup/desktop-settings.dconf.new"
mv "$T/bin/dconf" "$T/bin/dconf.off"   # (later checks use no dconf)

echo "What the dotfiles added (dot uninstall removes only these)"
ADDED_FILE="$T/state/added" WEEKLY_JOB="$T/no-weekly-job"   # (this computer may have the real one)
t "without a record, everything counts as added (as before)" was_added app:chrome
added_init
t "a fresh computer's record isn't legacy" not grep -qx legacy "$ADDED_FILE"
t "something not recorded wasn't added" not was_added app:chrome
mark_added app:chrome; mark_added app:chrome
t "something recorded was added" was_added app:chrome
t "recorded once" same "$(grep -cx app:chrome "$ADDED_FILE")" 1
t "a dry run records nothing" bash -c 'DRY_RUN=1; source "$1/lib.sh"; ADDED_FILE="$2"; mark_added pkg:vlc; ! grep -qx pkg:vlc "$2"' _ "$ROOT" "$ADDED_FILE"
ADDED_FILE="$T/state/legacy" old_wallpaper="$T/legacy-home/${WALLPAPER#"$HOME"/}"   # its wallpaper is there
mkdir -p "$(dirname "$old_wallpaper")"; touch "$old_wallpaper"
WALLPAPER="$old_wallpaper" added_init
t "a computer set up before the record is legacy: everything counts" was_added app:steam
ADDED_FILE="$T/state/none"

echo "Why an extension didn't install (install.sh download_extension)"
load_fn install.sh download_extension
# A stand-in curl: exits with $CURL_RC, or answers HTTP $CURL_CODE.
printf '#!/bin/sh\n[ "${CURL_RC:-0}" = 0 ] || exit "$CURL_RC"\nprintf "%%s" "$CURL_CODE"\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"
why() { EXTENSIONS_SITE=https://extensions.gnome.org PATH="$T/bin:$PATH" download_extension x@y 49 "$T/ext.zip"; }
t "no internet says so" same "$(CURL_RC=6 why)" "couldn't reach extensions.gnome.org (no internet?)"
t "no version for this GNOME says so" same "$(CURL_CODE=404 why)" "extensions.gnome.org has no version of it for GNOME 49 (yet)"
t "a site error says so" same "$(CURL_CODE=503 why)" "extensions.gnome.org answered with an error (HTTP 503); try again later"
mv "$T/bin/curl" "$T/bin/curl.off"

echo "Other fixes"
trap_kept() {
  bash -c 'source "$1/lib.sh"; trap "echo stop" TERM; UI_TTY=1
    quiet test true >/dev/null 2>&1 </dev/null; [[ -n "$(trap -p TERM)" ]]' _ "$ROOT"
}
t "quiet() keeps the progress panel's TERM trap" trap_kept
fix_fails() {
  bash -c 'source "$1/lib.sh"; source <(sed -n "/^fix_step() {/,/^}/p" "$1/check.sh"); YES_ALL=1
    half() { false; echo "    KEPT-GOING"; }
    fix_step "A fix" "Fix it?" half; [[ "${FAILED[*]}" == "A fix" ]]' _ "$ROOT" | not grep -q KEPT-GOING
}
t "a dot check fix stops at its first error and is marked failed" fix_fails
# SUDO=false: the edit of the source file fails (for any user, root too).
mkdir -p "$T/src"; printf 'Types: deb\nEnabled: no\n' > "$T/src/app.sources"
src_rc=0; (cd "$ROOT" && SOURCES_DIR="$T/src" SUDO=false ./post-upgrade.sh --sources-only >/dev/null 2>&1) || src_rc=$?
t "post-upgrade.sh --sources-only fails when it can't switch a source on" same "$src_rc" 1
sed -n '/^# Remember what was picked/,/^fi$/p' "$ROOT/bootstrap.sh" > "$T/choices.sh"
mkdir -p "$HOME/.config/dotfiles"; echo terminal > "$HOME/.config/dotfiles/choices"
DOTFILES_CHOICES='' DOTFILES_SKIP='' bash "$T/choices.sh" >/dev/null
t "bootstrap.sh with no picks removes earlier choices" not test -e "$HOME/.config/dotfiles/choices"
load_fn install.sh reminder_folder
REMINDER_DROPIN="$T/dropin.conf"
reminder_in() { DOTFILES="$1" reminder_folder >/dev/null; }
reminder_in "$T/my 100% code/dotfiles"
t "dotfiles elsewhere: the reminder's drop-in runs them there" \
  grep -qxF "ExecStart=\"$T/my 100%% code/dotfiles/check.sh\" --notify" "$REMINDER_DROPIN"
reminder_in "$HOME/dotfiles"
t "back in ~/dotfiles: the drop-in is removed" not test -e "$REMINDER_DROPIN"

echo "The dot command"
mkdir -p "$T/dotcopy"; cp "$ROOT/dot" "$ROOT/lib.sh" "$T/dotcopy/"
for s in install.sh install-apps.sh fresh-install.sh post-upgrade.sh uninstall.sh check.sh; do
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$T/dotcopy" > "$T/dotcopy/$s"; chmod +x "$T/dotcopy/$s"
done
dot_rc() { local rc=0; "$T/dotcopy/dot" "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
for c in install apps fresh upgrade uninstall check; do
  t "dot $c --help explains it without starting the script" \
    same "$(dot_rc "$c" --yes --help)|$(test -e "$T/dotcopy/ran" && echo ran)" "0|"
done
t "dot help lists every command" same "$("$T/dotcopy/dot" help | grep -cE '^  (push|pull|check|edit|cd|install|apps|ssh|upgrade|fresh|uninstall|help)\b')" 12
t "an unknown command exits 2" same "$(dot_rc frobnicate)" 2
t "an unknown option exits 2" same "$(dot_rc push --frobnicate)" 2
t "an old name says what replaced it" grep -q "dot push" < <("$T/dotcopy/dot" notes 2>&1)
t "help for a command that doesn't exist exits 2" same "$(dot_rc help frobnicate)" 2
# dot's functions, without running it (shellcheck checks dot itself)
# shellcheck source=/dev/null
source <(sed -n '/^# --- The commands/,/^# --- Run/p' "$ROOT/dot")
t "a typo gets the closest command" same "$(suggest psuh)|$(suggest chek)|$(suggest instal)" "dot push|dot check|dot install"
t "a start that fits several lists them" same "$(suggest pu)" "dot push or dot pull"
t "nothing close: no suggestion" same "$(suggest zzzzz)" ""
t "distance counts edits" same "$(distance kitten sitting)|$(distance push push)" "3|0"
t "auto message: one area" same "$(printf 'setup/gnome-desktop.dconf\nsetup/desktop-settings.dconf\n' | auto_message)" "Update desktop settings"
t "auto message: two areas" same "$(printf 'bash/.bashrc\nsetup/flatpaks.txt\n' | auto_message)" "Update bash config and Flatpak apps"
t "auto message: many areas" same "$(printf 'bash/.bashrc\nsetup/flatpaks.txt\nsetup/dock-favorites.txt\nREADME.md\n' | auto_message)" "Update bash config, Flatpak apps and 2 more"
t "auto message: nothing" same "$(auto_message </dev/null)" "Update settings"
t "the menu lists only commands with a label" same "$(menu_items setup | cut -d'|' -f2 | tr '\n' ' ')" "install apps ssh upgrade "
t ".bashrc's completion finds every command" same \
  "$(sed -n 's/^  "\([a-z]\{1,\}\)|.*/\1/p' "$ROOT/dot" | tr '\n' ' ')" "$(names | tr '\n' ' ')"

echo "Setting up from a release"
# A stand-in GitHub repo with a release tag, and bootstrap.sh's part that downloads it.
git init -q -b main "$T/origin" && git -C "$T/origin" -c user.name=t -c user.email=t@e commit -q --allow-empty -m one
git -C "$T/origin" tag v0.1.0 && git -C "$T/origin" -c user.name=t -c user.email=t@e commit -q --allow-empty -m two
sed -n '/^# DOTFILES_REF: set up from/,/^exec /p' "$ROOT/bootstrap.sh" | sed '$d' > "$T/get.sh"
get() { REPO="file://$T/origin" DIR="$T/clone" DOTFILES_REF="${1:-}" bash -e "$T/get.sh" >/dev/null 2>&1; }
on() { echo "$(git -C "$T/clone" symbolic-ref -q --short HEAD)|$(git -C "$T/clone" log -1 --format=%s)"; }
get v0.1.0
t "DOTFILES_REF sets up from that release, on main" same "$(on)" "main|one"
get v0.1.0
t "... again on a computer that already has it" same "$(on)" "main|one"
pushed() { repo_ready "$T/clone" 2>/dev/null; }   # (dot's functions were loaded above)
t "dot push waits for dot pull while GitHub has newer commits" not pushed
get
t "without DOTFILES_REF: main, up to date" same "$(on)" "main|two"
git -C "$T/clone" -c advice.detachedHead=false checkout -q v0.1.0
get
t "a release from an older bootstrap.sh (not on a branch) goes back to main" same "$(on)" "main|two"
git -C "$T/clone" -c advice.detachedHead=false checkout -q v0.1.0
t "dot push won't commit when not on a branch" not pushed
git -C "$T/clone" checkout -q main
git -C "$T/clone" -c user.name=t -c user.email=t@e commit -q --allow-empty -m mine
t "DOTFILES_REF stops when main has commits not on GitHub" not get v0.1.0
t "... and leaves them" same "$(on)" "main|mine"
# The website offers the newest v1.2.3 tag (by version, not by name: v1.10.0 > v1.9.0).
for v in v1.2.0 v1.10.0 v1.9.0 test-tag; do git -C "$T/origin" tag "$v"; done
newest="$(python3 -I -B - "$ROOT/scripts/build-site.py" "$T/origin" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("build_site", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.ROOT = pathlib.Path(sys.argv[2]); print(m.latest_release())
PY
)"
t "build-site.py finds the latest release" same "$newest" v1.10.0

echo "dot check: the record and backups"
load_fn check.sh adopt_record
ADDED_FILE="$T/state/adopt"; printf 'legacy\n' > "$ADDED_FILE"
t "a legacy record is noticed" added_is_legacy
adopted() (   # ( ): the stand-ins below stay in here
  added_candidates() { printf 'app:chrome|Google Chrome\npkg:vlc|vlc (Ubuntu app)\n'; }
  ui_gum() { false; }; ask() { [[ "$1" != *vlc* ]]; }   # "you had VLC before"
  adopt_record >/dev/null
)
adopted
t "your answers replace it: only what the dotfiles added" same "$(grep -v '^#' "$ADDED_FILE")" app:chrome
t "... and it's no longer legacy" not added_is_legacy
t "added_candidates runs on this computer" eval 'added_candidates >/dev/null'
load_fn check.sh dotfiles_backups
mkdir -p "$HOME/.config/qBittorrent"
touch "$HOME/.bashrc.orig" "$HOME/.bashrc.orig.20261122-101010" "$HOME/.config/qBittorrent/qBittorrent.conf.prev"
t "dot check lists the backups install.sh made" same "$(dotfiles_backups | sed "s|$HOME/||" | sort | tr '\n' ' ')" \
  ".bashrc.orig .bashrc.orig.20261122-101010 .config/qBittorrent/qBittorrent.conf.prev "

echo "The weekly reminder (check.sh --notify)"
# notify-send is a stand-in, so no real notification pops up.
printf '#!/bin/sh\nexit 0\n' > "$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
remind() { PATH="$T/bin:$PATH" ADDED_FILE="$1" timeout 120 bash "$ROOT/check.sh" --notify 2>/dev/null; }
mkdir -p "$T/state" && printf 'legacy\n' > "$T/state/remind-legacy"
for day in 1 2 3; do touch "$HOME/.bashrc.orig.2026010$day-000000"; done   # 6, with the 3 from above
reminder="$(remind "$T/state/remind-legacy")"
t "it mentions a legacy record" grep -q "which apps you had before" <<< "$reminder"
t "it mentions backups once they pile up (6)" grep -q "6 backups of files the dotfiles replaced" <<< "$reminder"
rm -f "$HOME"/.bashrc.orig.2026010?-000000
printf '# answered\n' > "$T/state/remind-answered"
reminder="$(remind "$T/state/remind-answered")"
t "... but not once the record is answered" not grep -q "which apps you had before" <<< "$reminder"
t "... nor for a few backups (3)" not grep -q "backups of files the dotfiles replaced" <<< "$reminder"

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
