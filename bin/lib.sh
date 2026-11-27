#!/usr/bin/env bash
# Shared helpers and settings for every script here (install.sh, install-apps.sh,
# uninstall.sh, fresh-install.sh, post-upgrade.sh, check.sh, dot, scripts/).
# Source it after setting -uo pipefail:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck disable=SC2034  # the settings below are used by the scripts that source this

# Loaded once per script (install-apps.sh loads it too when check.sh or uninstall.sh
# reads its app list). Not exported: scripts started from this one load it themselves.
[[ -n "${DOTFILES_LIB_LOADED:-}" ]] && return 0
DOTFILES_LIB_LOADED=1

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # lib.sh is in bin/
# Where bootstrap.sh puts the dotfiles, and where the weekly reminder's unit looks.
# (bootstrap.sh, bash/.bashrc and the unit can't load this file, so they spell it out too.)
DEFAULT_DOTFILES="$HOME/code/github/dotfiles"
SETUP="$DOTFILES/setup"
STOW_DIR="$DOTFILES/home"   # the Stow packages: folders whose files are linked into your home folder
FAILED=()
# Terminal tools from apt (installed by fresh-install.sh, checked by check.sh). The last
# four check the dotfiles' own scripts (scripts/lint.sh, and so the checks before each push).
TOOLS=(git gh gum curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
       shellcheck pyflakes3 nodejs npm)
# Stow packages: folders here whose files are linked into your home folder
PACKAGES=(bash git starship ghostty btop lazygit bat eza fzf fastfetch terminal-default vscode claude systemd fontconfig)

# Places outside the dotfiles folder that install.sh fills, and check.sh, dot and uninstall.sh look at
VAULT="$HOME/Documents/Obsidian Vault"   # your notes: the private GitHub repo obsidian-vault
WALLPAPER="$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night-16x9.jpg"
NERD_FONT_DIR="$HOME/.local/share/fonts/RobotoMonoNerdFont"   # the terminal's font
MONO_FONT_DIR="$HOME/.local/share/fonts/RobotoMono"           # the desktop's monospace font
BRAVE_PREFS="$HOME/.config/BraveSoftware/Brave-Origin/Default/Preferences"   # Brave Origin's settings (scripts/brave-settings.py)
# Only when the dotfiles are somewhere else (not DEFAULT_DOTFILES): points the weekly reminder there
REMINDER_DROPIN="$HOME/.config/systemd/user/dotfiles-reminder.service.d/dotfiles-folder.conf"
# The desktop settings in setup/ and where in dconf each goes: install.sh loads them,
# uninstall.sh resets every key in them.
DCONF_FILES=("gnome-desktop.dconf|/org/gnome/"
  "gnome-shortcuts.dconf|/org/gnome/settings-daemon/plugins/media-keys/"
  "gnome-extension-settings.dconf|/org/gnome/shell/extensions/"
  "desktop-settings.dconf|/")

have() { command -v "$1" >/dev/null 2>&1; }

# list_of <file in setup/>: its entries, one per line, without comments, blank lines and
# "-name" lines (apt-packages.txt: on purpose not for new computers).
list_of() { sed 's/#.*//' "$SETUP/$1" | awk 'NF && $1 !~ /^-/ {print $1}'; }

# config_files <stow package>...: each of their files as "<package>/<path in your home
# folder>", NUL-separated. The file is $DOTFILES/<that>; its link is ~/<that without the package>.
config_files() { local p; for p in "$@"; do find "$STOW_DIR/$p" -type f -printf "$p/%P\\0"; done; }

# Is there a systemd user session (for the weekly reminder)? Not in containers or CI.
has_user_systemd() { have systemctl && systemctl --user show-environment >/dev/null 2>&1; }

# Does this computer have an NVIDIA graphics card?
# Asked once per run (lspci takes about 45 ms, and dot check asks 13 times): the card
# can't change while a script runs.
HAS_NVIDIA=""
has_nvidia() {
  if [[ -z "$HAS_NVIDIA" ]]; then
    if grep -qiE '(vga|3d|display).*nvidia' <<< "$(lspci 2>/dev/null)"; then HAS_NVIDIA=yes; else HAS_NVIDIA=no; fi
  fi
  [[ "$HAS_NVIDIA" == yes ]]
}

# --- Flatpak apps in the background (fresh-install.sh) -----------------------------------
# A new computer's Flatpak apps take minutes to download. fresh-install.sh starts them as
# soon as Flathub is added, so they install while apt installs everything else (Flatpak
# and apt don't share a lock). install.sh's Flatpak step leaves them be on its first run,
# and on the second (FLATPAKS_WAIT=1) waits for them, then installs as usual: whatever
# didn't make it, with its errors shown. install-apps.sh waits before it looks for the
# Flatpak Firefox. Their output goes to $FLATPAKS_BG.log.
FLATPAKS_BG="${FLATPAKS_BG:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/dotfiles-flatpaks}"   # .pid and .log
flatpaks_in_background() {   # flatpaks_in_background <app ID>...
  [[ "$DRY_RUN" == 1 ]] && { printf '    would install in the background: %s\n' "$*"; return 0; }
  flatpak install -y --noninteractive flathub "$@" > "$FLATPAKS_BG.log" 2>&1 < /dev/null &
  echo "$!" > "$FLATPAKS_BG.pid"
  disown 2>/dev/null || true
  echo "    installing ${#} Flatpak apps in the background, alongside the next steps"
}
# flatpaks_installing: still at it? (The ID is checked to still be that flatpak install.)
flatpaks_installing() {
  local pid; pid="$(cat "$FLATPAKS_BG.pid" 2>/dev/null)"
  [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" == *"flatpak install "* ]]
}
flatpaks_wait() {   # until the background install has finished (with a spinner)
  flatpaks_installing || return 0
  quiet "Waiting for the Flatpak apps (installing since the terminal tools)" flatpaks_wait_quietly
}
flatpaks_wait_quietly() { while flatpaks_installing; do sleep 1; done; }

# --- Choices: what to set up (picked on the website, or everything) ----------------------
# DOTFILES_CHOICES lists what to set up, separated by spaces. Groups: terminal desktop
# notes safety updates firewall nvidia firmware claude-md nosnapfirefox; single apps:
# app:chrome app:brave-origin app:code app:claude app:claude-code app:chatgpt app:protonvpn app:obs
# app:onlyoffice app:steam,
# pkg:<Ubuntu package> and flatpak:<Flatpak ID>. Empty or unset means everything.
# DOTFILES_SKIP is the opposite: everything except these (shorter when you untick little).
# bootstrap.sh saves it in ~/.config/dotfiles/choices, so later runs (dot install,
# dot apps, dot check) keep following it.
CHOICES_FILE="$HOME/.config/dotfiles/choices"
# In the file, a line "-name" means skip it.
if [[ -z "${DOTFILES_CHOICES:-}${DOTFILES_SKIP:-}" && -r "$CHOICES_FILE" ]]; then
  DOTFILES_CHOICES="$(grep -v '^#' "$CHOICES_FILE" | grep -v '^-' | tr '\n' ' ')"
  DOTFILES_SKIP="$(grep '^-' "$CHOICES_FILE" | sed 's/^-//' | tr '\n' ' ')"
fi
# Tidy spacing: the words, one space between. (read -a splits without expanding * or ?.)
read -ra _words <<< "${DOTFILES_CHOICES:-}"; DOTFILES_CHOICES="${_words[*]}"
read -ra _words <<< "${DOTFILES_SKIP:-}"; DOTFILES_SKIP="${_words[*]}"
unset _words
export DOTFILES_CHOICES DOTFILES_SKIP
chosen() {
  [[ " $DOTFILES_SKIP " == *" $1 "* ]] && return 1
  [[ -z "$DOTFILES_CHOICES" || " $DOTFILES_CHOICES " == *" $1 "* ]]
}
# need <choice>: in a step, skip it (with a note) unless it was chosen
need() { chosen "$1" && return 0; skip "not chosen"; return 1; }
# Is any choice starting with <prefix> (e.g. "pkg:") picked?
chosen_any() { [[ -z "$DOTFILES_CHOICES" || " $DOTFILES_CHOICES" == *" $1"* ]]; }
# chosen_from <file in setup/> <prefix>: its entries that were chosen as <prefix><entry>
# (flatpaks.txt with flatpak:, apt-packages.txt with pkg:).
chosen_from() {
  local e
  while read -r e; do chosen "$2$e" && echo "$e"; done < <(list_of "$1")
  return 0
}

# The stow packages for what was chosen (git always: name, email and signing).
chosen_packages() {
  local p
  for p in "${PACKAGES[@]}"; do
    case "$p" in
      bash|starship|ghostty|btop|lazygit|bat|eza|fzf|fastfetch|terminal-default) chosen terminal && echo "$p" ;;
      vscode)  chosen app:code && echo "$p" ;;
      claude)  chosen claude-md && echo "$p" ;;
      systemd) chosen safety && echo "$p" ;;
      fontconfig) chosen desktop && echo "$p" ;;
      *) echo "$p" ;;
    esac
  done
  return 0
}

# --- Look: colours, title box, steps, spinner, summary ------------------------------
# Colours and symbols only in a terminal; plain text in logs, CI and pipes (and with NO_COLOR).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  UI_TTY=1 C_B=$'\e[1m' C_N=$'\e[0m'
  if [[ "${COLORTERM:-}" == *truecolor* || "${COLORTERM:-}" == *24bit* ]]; then
    # Catppuccin Mocha: mauve, green, red, yellow, blue, overlay
    C_ACC=$'\e[38;2;203;166;247m' C_OK=$'\e[38;2;166;227;161m' C_ERR=$'\e[38;2;243;139;168m'
    C_WARN=$'\e[38;2;249;226;175m' C_INFO=$'\e[38;2;137;180;250m' C_DIM=$'\e[38;2;127;132;156m'
  else
    C_ACC=$'\e[35m' C_OK=$'\e[32m' C_ERR=$'\e[31m' C_WARN=$'\e[33m' C_INFO=$'\e[34m' C_DIM=$'\e[2m'
  fi
else
  UI_TTY=0 C_B='' C_N='' C_ACC='' C_OK='' C_ERR='' C_WARN='' C_INFO='' C_DIM=''
fi

# Scripts started by another script (install.sh from fresh-install.sh) are "nested":
# no title box, lighter step lines, and a one-line summary.
if [[ "${UI_PID:-}" != "$$" ]]; then
  UI_PID=$$ UI_NESTED="${UI_DEPTH:-0}" UI_T0=$SECONDS
  export UI_DEPTH=$(( UI_NESTED + 1 ))
  # One log for the whole run (shared with nested scripts): full output of quiet commands.
  UI_LOG="${UI_LOG:-$HOME/.cache/dotfiles/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log}"
  export UI_LOG
  STEP_N=0 STEP_TOTAL="${STEP_TOTAL:-0}" STEP_TITLE='' STEP_T0=$SECONDS
  RESULTS=()
  UI_MARK="${TMPDIR:-/tmp}/dotfiles-skipped-$$"
fi

# --- gum: arrow-key menus, checklists and Yes/No buttons ------------------------------
# Used when it's installed and you're at a terminal; otherwise plain prompts, as before.
# DOT_PLAIN=1 turns gum and the progress panel off.
ui_gum() { [[ -t 0 && -t 1 && -z "${NO_COLOR:-}" && -z "${DOT_PLAIN:-}" ]] && have gum; }
# Catppuccin Mocha for gum's widgets (mauve cursor, green ticks)
export GUM_CHOOSE_CURSOR="› " GUM_CHOOSE_CURSOR_FOREGROUND="#cba6f7" \
  GUM_CHOOSE_SELECTED_FOREGROUND="#a6e3a1" GUM_CHOOSE_HEADER_FOREGROUND="#cdd6f4" \
  GUM_CHOOSE_ITEM_FOREGROUND="#cdd6f4" GUM_CONFIRM_PROMPT_FOREGROUND="#cdd6f4" \
  GUM_CONFIRM_SELECTED_BACKGROUND="#cba6f7" GUM_CONFIRM_SELECTED_FOREGROUND="#1e1e2e" \
  GUM_CONFIRM_UNSELECTED_BACKGROUND="#313244" GUM_CONFIRM_UNSELECTED_FOREGROUND="#cdd6f4" \
  GUM_INPUT_CURSOR_FOREGROUND="#cba6f7" GUM_INPUT_PROMPT_FOREGROUND="#cba6f7" \
  GUM_INPUT_PLACEHOLDER_FOREGROUND="#7f849c"

fmt_time() { local t="$1"; if (( t < 60 )); then printf '%ss' "$t"; else printf '%dm %02ds' $((t / 60)) $((t % 60)); fi; }

# header "Title" "line"...: the box at the start of a script.
header() {
  [[ "$UI_NESTED" == 0 ]] || return 0
  local title="$1" l w; shift
  UI_TITLE="$title"
  w=${#title}; for l in "$@"; do (( ${#l} > w )) && w=${#l}; done
  local bar; bar="$(printf '%*s' $((w + 4)) '' | sed 's/ /─/g')"
  printf '\n%s╭%s╮%s\n' "$C_ACC" "$bar" "$C_N"
  printf '%s│%s  %s%s%s%*s  %s│%s\n' "$C_ACC" "$C_N" "$C_B" "$title" "$C_N" $((w - ${#title})) '' "$C_ACC" "$C_N"
  for l in "$@"; do
    printf '%s│%s  %s%*s  %s│%s\n' "$C_ACC" "$C_N" "$l" $((w - ${#l})) '' "$C_ACC" "$C_N"
  done
  printf '%s╰%s╯%s\n' "$C_ACC" "$bar" "$C_N"
}

# Lines inside a step
say()  { printf '\n%s%s%s\n' "$C_B" "$*" "$C_N"; }
note() { printf '    %s•%s %s\n' "$C_INFO" "$C_N" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_WARN" "$C_N" "$*"; }
skip() { printf '    %s↷ skipped:%s %s\n' "$C_WARN" "$C_N" "$*"; : > "$UI_MARK" 2>/dev/null || true; }

# step_begin "title" / step_end ok|already|skip|notneeded|fail [detail]
step_begin() {
  STEP_TITLE="$1"; STEP_N=$((STEP_N + 1)); STEP_T0=$SECONDS
  rm -f "$UI_MARK"
  local count=''; (( STEP_TOTAL > 0 )) && count="[$STEP_N/$STEP_TOTAL] "
  if [[ "$UI_NESTED" == 0 ]]; then
    printf '\n%s%s%s%s%s%s\n' "$C_ACC" "$C_B" "$count" "$C_N$C_B" "$STEP_TITLE" "$C_N"
  else
    printf '\n  %s%s%s%s\n' "$C_DIM" "$count" "$C_N" "$STEP_TITLE"
  fi
  if [[ "$UI_NESTED" == 0 ]]; then ui_panel_step running "$STEP_TITLE"; else ui_panel_step running "$count$STEP_TITLE"; fi
}
step_end() {
  local st="$1" detail="${2:-}" t=$((SECONDS - STEP_T0)) icon col word quiet_end=0
  # A step that only skipped things already said why ("↷ skipped: ..."), so no second line.
  if [[ "$st" == ok && -e "$UI_MARK" ]]; then st=skip quiet_end=1; fi
  rm -f "$UI_MARK"
  case "$st" in
    ok)        icon='✔' col="$C_OK"   word="done" ;;
    already)   icon='✔' col="$C_DIM"  word="already done" ;;
    skip)      icon='↷' col="$C_WARN" word="skipped" ;;
    notneeded) icon='–' col="$C_DIM"  word="not needed" ;;
    *)         icon='✘' col="$C_ERR"  word="failed" ;;
  esac
  local when=''; (( t >= 2 )) && when=" $(fmt_time "$t")"
  if [[ "$quiet_end" == 0 ]]; then
    printf '    %s%s %s%s%s%s%s%s\n' "$col" "$icon" "$word" "${detail:+ ($detail)}" "$C_N" "$C_DIM" "$when" "$C_N"
  fi
  RESULTS+=("$st|$STEP_TITLE|$t")
  [[ "$st" == fail ]] && FAILED+=("$STEP_TITLE")
  ui_panel_step "$st" "$STEP_TITLE" "$t"
  return 0
}

# run_step "title" command...: run one step in a subshell with "stop on error".
# If it fails, it's marked ✘ and listed at the end; later steps still run.
run_step() {
  step_begin "$1"; shift
  ( set -e; "$@" )
  local rc=$?
  if (( rc == 0 )); then step_end ok; else step_end fail "exit code $rc"; fi
}

# run_steps "title|function"...: run a script's steps in order, with the progress panel.
run_steps() {
  local s titles=()
  for s in "$@"; do titles+=("${s%%|*}"); done
  STEP_TOTAL=${#titles[@]}
  ui_plan "${titles[@]}"
  for s in "$@"; do run_step "${s%%|*}" "${s#*|}"; done
}

# quiet "label" command...: run a noisy command (apt, flatpak) with a spinner instead of
# its output. The output goes to the log; if it fails, the last lines are shown.
quiet() {
  local label="$1"; shift
  [[ "${DRY_RUN:-0}" == 1 ]] && { run "$@"; return 0; }
  local t0=$SECONDS rc=0 pid i=0 frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  mkdir -p "$(dirname "$UI_LOG")"
  printf '\n### %s  %s\n' "$(date '+%F %T')" "$*" >> "$UI_LOG"
  local from; from=$(( $(stat -c %s "$UI_LOG") + 1 ))   # where this command's output starts
  if [[ "$UI_TTY" == 1 ]]; then
    "$@" >> "$UI_LOG" 2>&1 < /dev/null &
    pid=$!
    # The traps it had (the progress panel's: put the terminal back), restored after.
    local prev_int prev_term; prev_int="$(trap -p INT)" prev_term="$(trap -p TERM)"
    trap 'printf "\e[?25h"; kill "$pid" 2>/dev/null' INT TERM
    printf '\e[?25l'
    # The spinner line is redrawn in place, so it must fit on one line: a longer one wraps,
    # and each redraw leaves a copy behind. Cut to the window's width (measured again each
    # second, in case it's resized); the ✔/✘ line at the end has the whole label.
    local cols='' shown="$label" max
    while kill -0 "$pid" 2>/dev/null; do
      if (( i == 0 )); then
        ui_panel_draw     # once a second: the panel's timer
        read -r _ cols < <(term_size) || true; [[ "$cols" =~ ^[0-9]+$ ]] || cols="${COLUMNS:-80}"
        max=$(( cols - 17 )); (( max < 10 )) && max=10   # room for indent, spinner and time
        shown="$label"; (( ${#shown} > max )) && shown="${shown:0:max-1}…"
      fi
      printf '\r    %s%s%s %s %s%s%s\e[K' "$C_ACC" "${frames:i:1}" "$C_N" "$shown" "$C_DIM" "$(fmt_time $((SECONDS - t0)))" "$C_N"
      i=$(( (i + 1) % 10 ))
      sleep 0.1
    done
    wait "$pid" || rc=$?
    printf '\r\e[K\e[?25h'
    trap - INT TERM
    [[ -n "$prev_int" ]] && eval "$prev_int"
    [[ -n "$prev_term" ]] && eval "$prev_term"
  else
    printf '    … %s\n' "$label"
    "$@" >> "$UI_LOG" 2>&1 < /dev/null || rc=$?
  fi
  if (( rc == 0 )); then
    printf '    %s✔%s %s %s%s%s\n' "$C_OK" "$C_N" "$label" "$C_DIM" "$(fmt_time $((SECONDS - t0)))" "$C_N"
  else
    printf '    %s✘ %s failed%s (exit code %s). Last lines of the log:\n' "$C_ERR" "$label" "$C_N" "$rc"
    tail -c "+$from" "$UI_LOG" | grep -v '^\s*$' | tail -n 12 | sed "s/^/      ${C_DIM}│${C_N} /"
    printf '      Full log: %s\n' "${UI_LOG/#$HOME/\~}"
  fi
  return "$rc"
}

# summary: the table of steps at the end. Returns 1 if anything failed.
summary() {
  ui_panel_stop
  local r st title t icon col n_ok=0 n_skip=0 n_fail=0 w=0 total=$((SECONDS - UI_T0))
  for r in "${RESULTS[@]}"; do IFS='|' read -r _ title _ <<< "$r"; (( ${#title} > w )) && w=${#title}; done
  (( w > 46 )) && w=46
  if [[ "$UI_NESTED" == 0 ]]; then printf '\n%s%s── Summary %s%s\n' "$C_ACC" "$C_B" "$(printf '%*s' $((w + 2)) '' | sed 's/ /─/g')" "$C_N"; fi
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r st title t <<< "$r"
    case "$st" in
      ok) icon='✔' col="$C_OK"; n_ok=$((n_ok + 1)) ;;
      already) icon='✔' col="$C_DIM"; n_ok=$((n_ok + 1)) ;;
      skip) icon='↷' col="$C_WARN"; n_skip=$((n_skip + 1)) ;;
      notneeded) icon='–' col="$C_DIM" ;;
      *) icon='✘' col="$C_ERR"; n_fail=$((n_fail + 1)) ;;
    esac
    [[ "$UI_NESTED" == 0 ]] || continue
    (( ${#title} > w )) && title="${title:0:w-1}…"
    local word; case "$st" in ok) word='';; already) word='already done';; skip) word='skipped';; notneeded) word='not needed';; *) word='FAILED';; esac
    [[ -z "$word" ]] && (( t >= 2 )) && word="$(fmt_time "$t")"
    printf '  %s%s%s %s%*s  %s%s%s\n' "$col" "$icon" "$C_N" "$title" $((w - ${#title})) '' "$C_DIM" "$word" "$C_N"
  done
  if [[ "$UI_NESTED" != 0 ]]; then
    printf '\n  %s%s:%s %s done, %s skipped, %s failed %s(%s)%s\n' "$C_DIM" "$(basename "$0")" "$C_N" "$n_ok" "$n_skip" "$n_fail" "$C_DIM" "$(fmt_time "$total")" "$C_N"
  elif (( n_fail )); then
    local steps="steps"; (( n_fail == 1 )) && steps="step"
    printf '\n%s%s✘ %s %s failed.%s Fix the cause (see its messages above) and run it again;\n  finished parts are skipped.' "$C_ERR" "$C_B" "$n_fail" "$steps" "$C_N"
    printf ' Took %s.\n' "$(fmt_time "$total")"
  else
    printf '\n%s%s✔ All done%s in %s.\n' "$C_OK" "$C_B" "$C_N" "$(fmt_time "$total")"
  fi
  if [[ "$UI_NESTED" == 0 && -s "$UI_LOG" ]]; then printf '  %sFull output of installs: %s%s\n' "$C_DIM" "${UI_LOG/#$HOME/\~}" "$C_N"; fi
  (( n_fail == 0 ))
}
show_failures() { summary; }

# --- Questions ----------------------------------------------------------------------
# YES_ALL=1 answers Yes to every question, so a run needs no one at the keyboard.
# It's chosen once at the start (choose_answer_mode, or -y / --yes / --all) and passed
# on to scripts started from that one, so they don't ask again.
YES_ALL="${YES_ALL:-}"

# yes_flag "$@": -y, --yes or --all among the arguments means Yes to everything.
yes_flag() {
  local a
  for a in "$@"; do
    case "$a" in -y|--yes|--all) YES_ALL=1; export YES_ALL ;; esac
  done
}

# choose_answer_mode: the one question at the start (skipped if already chosen).
choose_answer_mode() {
  [[ -n "$YES_ALL" ]] && return 0
  local a
  if ui_gum; then
    echo
    a="$(gum choose --header "How should questions be answered?" \
      "Yes to everything: it runs by itself" "Let me choose")" || { echo "Nothing changed."; exit 0; }
    [[ "$a" == Let* ]] && a=n || a=y
  else
    printf '\n  %sHow should questions be answered?%s\n' "$C_B" "$C_N"
    printf '    %sY%s  Yes to everything: it runs by itself  %s(Enter)%s\n' "$C_ACC$C_B" "$C_N" "$C_DIM" "$C_N"
    printf '    %sn%s  Let me choose (asks before each step)\n' "$C_ACC$C_B" "$C_N"
    read -rp "  ${C_ACC}›${C_N} " a
  fi
  if [[ "$a" =~ ^[Nn]$ ]]; then
    YES_ALL=0; printf '  %s✔%s You choose as it goes %s(Enter = yes)%s\n' "$C_OK" "$C_N" "$C_DIM" "$C_N"
  else
    YES_ALL=1; printf '  %s✔%s Yes to everything: you can leave it running\n' "$C_OK" "$C_N"
  fi
  export YES_ALL
}

# ask "Question?": true for yes. With YES_ALL=1 it shows the question with the answer
# and doesn't wait; with gum it's Yes/No buttons (Yes first); otherwise [Y/n].
ask() {
  if [[ "$YES_ALL" == 1 ]]; then
    printf '    %s?%s %s %s› yes%s\n' "$C_INFO" "$C_N" "$1" "$C_DIM" "$C_N"; return 0
  fi
  if ui_gum; then
    local rc=0; gum confirm --default=true "$1" < /dev/tty || rc=$?
    printf '    %s?%s %s %s› %s%s\n' "$C_INFO" "$C_N" "$1" "$C_DIM" "$( ((rc == 0)) && echo yes || echo no)" "$C_N"
    return "$rc"
  fi
  local a; read -rp "    ${C_INFO}?${C_N} $1 ${C_DIM}[Y/n]${C_N} " a; [[ ! "$a" =~ ^[Nn]$ ]]
}
# ask_no "Question?": the same, but Enter means no (and so does no terminal): for what can't
# be quietly undone, like pushing to GitHub. YES_ALL=1 still says yes.
ask_no() {
  if [[ "$YES_ALL" == 1 ]]; then
    printf '    %s?%s %s %s› yes%s\n' "$C_INFO" "$C_N" "$1" "$C_DIM" "$C_N"; return 0
  fi
  if ui_gum; then
    local rc=0; gum confirm --default=false "$1" < /dev/tty || rc=$?
    printf '    %s?%s %s %s› %s%s\n' "$C_INFO" "$C_N" "$1" "$C_DIM" "$( ((rc == 0)) && echo yes || echo no)" "$C_N"
    return "$rc"
  fi
  local a=""; [[ -t 0 ]] && read -rp "    ${C_INFO}?${C_N} $1 ${C_DIM}[y/N]${C_N} " a; [[ "$a" =~ ^[Yy] ]]
}
# ask_or_quit "Question?": the first question of a script; No ends it without changes.
ask_or_quit() { ask "$1" || { echo "Nothing changed."; exit 0; }; }

# keep_sudo: ask for the password once, then keep sudo signed in until this script
# ends, so a long run (big downloads) doesn't stop halfway to ask again.
# Not asked when sudo already works without one (sudo without a password, or signed in a
# moment ago): Ubuntu 26.04's sudo (sudo-rs) asks on `sudo -v` even then.
keep_sudo() {
  [[ -n "${SUDO_KEPT:-}" ]] && return 0
  sudo -n true 2>/dev/null || sudo -v || return 1
  SUDO_KEPT=1
  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do sudo -n true; sleep 50; done ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# installed <package>: is this apt package installed? (A pattern like 'nvidia-driver-*'
# means any package it matches; name:arch, like libnvidia-gl-580:i386, works too.)
# Looked up in DPKG_INSTALLED: every installed package, read with one dpkg-query (about
# 40 ms; one dpkg-query per package was 12 ms each, and dot check asks about 100). It's
# read again whenever dpkg's database has changed since, so installs and removals show
# up at once, whether these scripts made them, a subshell did, or you did by hand.
# DPKG_STATUS_FILE is for tests.
declare -A DPKG_INSTALLED=()
DPKG_READ_FD=""   # a stamp file from just before the last read (see dpkg_read)
DPKG_STATUS_FILE="${DPKG_STATUS_FILE:-/var/lib/dpkg/status}"   # dpkg's database
installed() {
  # A tie counts as changed: file times only move every few milliseconds.
  [[ -n "$DPKG_READ_FD" && /dev/fd/$DPKG_READ_FD -nt "$DPKG_STATUS_FILE" ]] || dpkg_read
  if [[ "$1" != *[*?[]* ]]; then [[ -n "${DPKG_INSTALLED[$1]:-}" ]]; return; fi
  local k
  # shellcheck disable=SC2053  # $1 is a pattern on purpose
  for k in "${!DPKG_INSTALLED[@]}"; do [[ "$k" == $1 ]] && return 0; done
  return 1
}
# The stamp is an empty file, deleted at once but kept open (bash reads its time through
# /dev/fd), so nothing is left behind. A new one per read: a subshell that reads again
# mustn't move the stamp of the shell it came from, whose list it can't update.
dpkg_read() {
  local f k list
  [[ -n "$DPKG_READ_FD" ]] && exec {DPKG_READ_FD}>&-
  DPKG_READ_FD=""
  f="$(mktemp)" && exec {DPKG_READ_FD}>"$f"; rm -f "$f"
  DPKG_INSTALLED=()
  mapfile -t list < <(dpkg-query -W -f='${Status}\t${Package}\t${Architecture}\n' 2>/dev/null \
    | awk -F'\t' '$1 ~ /install ok installed/ { print $2; print $2 ":" $3 }')
  for k in "${list[@]}"; do DPKG_INSTALLED[$k]=1; done
}

# --- Dry runs and changes ----------------------------------------------------------------
# DRY_RUN=1 (install.sh, install-apps.sh, uninstall.sh): show what would change, change
# nothing. Downloads are still made into a temporary folder and checked.
DRY_RUN="${DRY_RUN:-0}"; export DRY_RUN   # scripts started from this one do the same
# run <command>...: run it, or only print it in a dry run.
run() { if [[ "$DRY_RUN" == 1 ]]; then printf '    would run: %s\n' "$*"; else "$@"; fi; }
# run_quiet <command>...: the same, without the command's own output.
run_quiet() { if [[ "$DRY_RUN" == 1 ]]; then run "$@"; else "$@" >/dev/null 2>&1; fi; }
# did "what": a line saying what a step just changed; silent in a dry run, where the
# "would ..." lines say it instead.
did() { [[ "$DRY_RUN" == 1 ]] || printf '    %s\n' "$*"; }
# copy_into <folder> <file>...: copy files into a folder (made if needed), or say so.
copy_into() {
  local d="$1"; shift
  if [[ "$DRY_RUN" == 1 ]]; then printf '    would copy %s file(s) into %s\n' "$#" "${d/#$HOME/\~}"; return 0; fi
  mkdir -p "$d" && cp "$@" "$d/"
}

# fetch_checked <URL> <sha256> <file> [label]: download it and keep it only if its checksum
# matches, so a file that changed (or was changed) is never used. Pinned downloads. Shows
# a spinner with the time while it downloads (a slow connection can take minutes), and
# downloads in dry runs too, since checking the file is the point.
fetch_checked() {
  local url="$1" sum="$2" file="$3" label="${4:-Downloading ${1##*/}}" tmp
  tmp="$(mktemp "$file.XXXXXX")" || return 1
  if ! DRY_RUN=0 quiet "$label" curl -fsSL --retry 3 -o "$tmp" "$url"; then rm -f "$tmp"; return 1; fi
  if [[ "$(sha256sum "$tmp" | cut -d' ' -f1)" != "$sum" ]]; then
    rm -f "$tmp"
    echo "    ${url##*/}: not the expected file (its checksum differs), so it isn't used" >&2
    return 1
  fi
  mv "$tmp" "$file"
}

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

# apt_get <apt-get arguments>: sudo apt-get with a spinner and a short label (full output
# in the log), after other updates finish. It never stops to ask: config files you changed
# are kept, and DPkg::Lock::Timeout makes apt wait (up to 5 minutes) if something starts
# in between. apt_get_as "label" <arguments> is the same with your own label.
apt_get() {
  local label a pkgs=()
  for a in "$@"; do
    [[ "$a" == -* || " install remove update full-upgrade autoremove " == *" $a "* ]] || pkgs+=("${a##*/}")
  done
  case " $* " in
    *" update "*)       label="Refreshing package lists" ;;
    *" full-upgrade "*) label="Upgrading all packages" ;;
    *" autoremove "*)   label="Removing packages nothing needs any more" ;;
    *" remove "*)       label="Removing ${pkgs[*]}" ;;
    *)                  label="Installing ${pkgs[*]}" ;;
  esac
  (( ${#label} > 60 )) && label="${label:0:57}..."
  apt_get_as "$label" "$@"
}
apt_get_as() {
  local label="$1"; shift
  apt_wait
  if [[ "$DRY_RUN" == 1 ]]; then run sudo apt-get "$@"; return 0; fi
  quiet "$label" sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# repo_state <dir>: prints "uncommitted", "unpushed", "uncommitted and unpushed", or nothing
# diff_lines <max lines> <how to see all>: a unified diff (stdin) as the lines that changed,
# file by file ("  file:", "    - old", "    + new"), cut to <max lines>. Used by dot push's
# and dot check's previews, so you see what a save would change before saying yes.
diff_lines() {
  local max="$1" all="$2" out n red='' green=''
  [[ -n "$C_N" ]] && red=$'\e[31m' green=$'\e[32m'
  out="$(awk -v r="$red" -v g="$green" -v d="$C_DIM" -v o="$C_N" '
    /^diff / { f = $NF; sub(/^[ab]\//, "", f); print "  " d f ":" o; next }
    /^(index|---|\+\+\+|@@|new file|deleted file|similarity|rename|old mode|new mode|Only in)/ { next }
    /^Binary files/ { print "    " d "(binary file)" o; next }
    /^-/ { print "    " r "- " substr($0, 2, 110) o; next }
    /^\+/ { print "    " g "+ " substr($0, 2, 110) o; next }')"
  [[ -n "$out" ]] || return 0
  n=$(wc -l <<<"$out")
  head -n "$max" <<<"$out"
  (( n > max )) && printf '  %s… and %s more lines (%s to see all)%s\n' "$C_DIM" $((n - max)) "$all" "$C_N"
  return 0
}

repo_state() {
  local d="$1" s=()
  [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]] && s+=(uncommitted)
  [[ -n "$(git -C "$d" log --oneline '@{u}..' 2>/dev/null)" ]] && s+=(unpushed)
  (( ${#s[@]} )) || return 0
  printf '%s\n' "${s[*]}" | sed 's/ / and /'
}

# Is this a system these dotfiles are made for? Ubuntu 26.04 with GNOME carries on without
# a word. Another Ubuntu version, an Ubuntu-based system (Mint, Pop!_OS) or another desktop
# says why and asks first (Enter = no; DOTFILES_ANY_SYSTEM=1 carries on, --yes doesn't, since
# the website's commands have it). Anything else stops before
# changing anything. OS_RELEASE_FILE is for tests. bootstrap.sh has its own copy, since it
# runs before the repo is downloaded; .github/workflows/check.yml tests that both agree.
check_system() {
  [[ -n "${DOTFILES_SYSTEM_CHECKED:-}" ]] && return 0   # bootstrap.sh already checked
  local id like ver name problems=() a
  # shellcheck source=/dev/null
  IFS='|' read -r id like ver name < <(. "${OS_RELEASE_FILE:-/etc/os-release}" 2>/dev/null
    echo "${ID:-}|${ID_LIKE:-}|${VERSION_ID:-}|${PRETTY_NAME:-this system}")
  if [[ "$id" != ubuntu && " $like " != *" ubuntu "* ]]; then
    printf '\n✘ These dotfiles are for Ubuntu 26.04 with GNOME; this is %s.\n  Nothing was changed.\n' "$name"
    exit 1
  fi
  [[ "$id" != ubuntu ]] && problems+=("$name is based on Ubuntu, but these dotfiles are made for Ubuntu 26.04 itself.")
  [[ "$id" == ubuntu && "$ver" != 26.04 ]] && problems+=("This is Ubuntu $ver; these dotfiles are made and tested for 26.04. App sources and GNOME extensions may not work.")
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "${XDG_CURRENT_DESKTOP^^}" != *GNOME* ]]; then
    problems+=("The desktop is $XDG_CURRENT_DESKTOP, not GNOME: the desktop look, extensions and dock won't apply.")
  elif [[ -z "${XDG_CURRENT_DESKTOP:-}" ]] && ! command -v gnome-shell >/dev/null 2>&1; then
    problems+=("GNOME isn't installed: the desktop look, extensions and dock won't apply.")
  fi
  (( ${#problems[@]} )) || return 0
  echo
  for a in "${problems[@]}"; do printf '! %s\n' "$a"; done
  [[ -n "${DOTFILES_ANY_SYSTEM:-}" ]] && { echo "  Carrying on (DOTFILES_ANY_SYSTEM is set)."; return 0; }
  a=""; if [[ -t 0 ]]; then read -rp "Carry on anyway? [y/N] " a || true; fi
  [[ "$a" =~ ^[Yy] ]] || { echo "Nothing was changed."; exit 0; }
}

# repo_behind <dir>: how many commits GitHub has that this computer doesn't. Fetches first
# (quietly, 10 seconds at most), unless repo_prefetch already did; prints 0 when offline or
# without an upstream.
repo_behind() {
  [[ -n "${FETCH_PID[$1]:-}" ]] || repo_fetch "$1"
  git -C "$1" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0
}
# repo_fetch <dir>: git fetch, quietly; fails if it couldn't (offline, say). At most
# FETCH_TIMEOUT seconds (10: dot check and dot push only need to know what's new).
repo_fetch() { GIT_TERMINAL_PROMPT=0 timeout "${FETCH_TIMEOUT:-10}" git -C "$1" fetch --quiet >/dev/null 2>&1; }
# repo_prefetch <dir>...: start fetching each repo in the background, all at once, so the
# waits on GitHub overlap with each other and with the rest of the work. Call repo_wait
# <dir> before repo_state or repo_behind on it (in this shell, not in a $(...): a subshell
# can't wait for it).
declare -A FETCH_PID=() FETCH_RC=()
repo_prefetch() {
  local d
  for d in "$@"; do
    [[ -d "$d/.git" ]] || continue
    repo_fetch "$d" & FETCH_PID[$d]=$!
  done
}
# repo_wait <dir>: until its fetch is done; fails if the fetch did (asked again: the same answer).
repo_wait() {
  [[ -n "${FETCH_PID[$1]:-}" ]] || return 0
  [[ -n "${FETCH_RC[$1]:-}" ]] || { wait "${FETCH_PID[$1]}" 2>/dev/null; FETCH_RC[$1]=$?; }
  return "${FETCH_RC[$1]}"
}

# gh_key_admin: can the GitHub CLI's sign-in add or remove SSH keys on your account?
# dot ssh needs that briefly; left in place, a leaked gh token could add someone else's key.
GH_KEY_SCOPES="admin:public_key,admin:ssh_signing_key"
gh_key_admin() {
  have gh || return 1
  local scopes; scopes="$(gh api -i user 2>/dev/null | tr -d '\r' | grep -i '^x-oauth-scopes:')"
  [[ "$scopes" == *admin:public_key* || "$scopes" == *admin:ssh_signing_key* ]]
}

# --- Git name and email -----------------------------------------------------------------
# Kept per person in ~/.config/git/user.gitconfig (git/.gitconfig includes it), so someone
# else using these dotfiles doesn't commit under your name. Asked once per computer; the
# suggestion is git's current setting, or setup/git-identity. Without a terminal (CI,
# pipes) it's skipped, and git asks at the first commit.
GIT_USER_FILE="$HOME/.config/git/user.gitconfig"
git_identity() {
  [[ -f "$GIT_USER_FILE" ]] && return 0
  # Given on the website (DOTFILES_GIT_NAME / DOTFILES_GIT_EMAIL): use them, no question.
  if [[ -n "${DOTFILES_GIT_NAME:-}" && -n "${DOTFILES_GIT_EMAIL:-}" ]]; then
    mkdir -p "$(dirname "$GIT_USER_FILE")"
    git config --file "$GIT_USER_FILE" user.name "$DOTFILES_GIT_NAME"
    git config --file "$GIT_USER_FILE" user.email "$DOTFILES_GIT_EMAIL"
    printf '  %s✔%s Commits will be by %s <%s>\n' "$C_OK" "$C_N" "$DOTFILES_GIT_NAME" "$DOTFILES_GIT_EMAIL"
    return 0
  fi
  [[ -t 0 && -t 1 ]] && have git || return 0
  local name email def_name def_email
  def_name="$(git config --get user.name 2>/dev/null)"; def_email="$(git config --get user.email 2>/dev/null)"
  if [[ -z "$def_email" && -f "$SETUP/git-identity" ]]; then
    def_name="$(sed -n 's/^name=//p' "$SETUP/git-identity")"
    def_email="$(sed -n 's/^email=//p' "$SETUP/git-identity")"
  fi
  printf '\n  %sYour name and email for git commits%s %s(asked once on this computer; Enter keeps it)%s\n' "$C_B" "$C_N" "$C_DIM" "$C_N"
  if ui_gum; then
    name="$(gum input --prompt "  Name  › " --value "$def_name")" || return 0
    email="$(gum input --prompt "  Email › " --value "$def_email")" || return 0
  else
    read -rep "    Name:  " -i "$def_name" name
    read -rep "    Email: " -i "$def_email" email
  fi
  if [[ -z "$name" || -z "$email" ]]; then warn "skipped: git will ask when you first commit"; return 0; fi
  mkdir -p "$(dirname "$GIT_USER_FILE")"
  git config --file "$GIT_USER_FILE" user.name "$name"
  git config --file "$GIT_USER_FILE" user.email "$email"
  printf '  %s✔%s Commits will be by %s <%s>\n' "$C_OK" "$C_N" "$name" "$email"
}

# --- Live progress panel ---------------------------------------------------------------
# The step list pinned at the top of the terminal, updating in place, while the output
# scrolls underneath (a terminal scroll region). Prompts still work: they show in the
# scrolling part. Only for the top script, in a terminal tall enough; DOT_PLAIN=1 turns
# it off. Its state lives in small files ($UI_PANEL_FILE, exported) so nested scripts
# (install.sh inside fresh-install.sh) can show their current step under the parent's.
UI_PANEL_FILE="${UI_PANEL_FILE:-}"
UI_PANEL_ROWS=0
term_size() { stty size < /dev/tty 2>/dev/null; }   # prints "rows columns"

# ui_plan "title"...: the steps this script will run; starts the panel.
ui_plan() {
  [[ "$UI_NESTED" == 0 && "$UI_TTY" == 1 && -z "${DOT_PLAIN:-}" && -t 1 ]] || return 0
  local rows='' cols='' t prev
  read -r rows cols < <(term_size)
  [[ "$rows" =~ ^[0-9]+$ ]] && (( rows >= $# + 12 )) || return 0
  UI_PANEL_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-panel.XXXXXX")" || return 0
  export UI_PANEL_FILE
  for t in "$@"; do printf 'pending|%s|0|0\n' "$t"; done > "$UI_PANEL_FILE"
  printf '%s|%s\n' "${UI_TITLE:-$(basename "$0" .sh)}" "$(date +%s)" > "$UI_PANEL_FILE.head"
  : > "$UI_PANEL_FILE.sub"
  UI_PANEL_ROWS=$(( $# + 2 ))
  # Move what's on screen into the scrollback, then pin the panel at the top.
  printf '%*s' "$rows" '' | tr ' ' '\n'
  printf '\e[H\e[2J\e[%d;%dr\e[%d;1H' $((UI_PANEL_ROWS + 1)) "$rows" $((UI_PANEL_ROWS + 1))
  ui_panel_draw
  trap 'ui_panel_resize' WINCH
  # The script's own EXIT trap (install-apps.sh's clean-up) still runs, after the panel
  # stops, with the exit code it would have seen. trap -p prints it shell-quoted
  # (trap -- '...' EXIT); `set --` undoes that quoting exactly, where cutting the quotes
  # off by hand broke on a trap with a ' in it.
  prev="$(trap -p EXIT)" UI_PREV_EXIT=''
  if [[ -n "$prev" ]]; then eval "set -- $prev"; UI_PREV_EXIT="$3"; fi
  trap 'UI_RC=$?; ui_panel_stop; (exit "$UI_RC"); eval "$UI_PREV_EXIT"' EXIT
  trap 'ui_panel_stop; exit 130' INT TERM
}

# ui_panel_step <state> <title> [seconds]: update a step (running/ok/skip/fail/...).
# From a nested script, the title is shown as the parent's current sub-step instead.
ui_panel_step() {
  [[ -n "$UI_PANEL_FILE" && -f "$UI_PANEL_FILE" ]] || return 0
  if [[ "$UI_NESTED" != 0 ]]; then
    [[ "$1" == running ]] && printf '%s' "$2" > "$UI_PANEL_FILE.sub"
    ui_panel_draw; return 0
  fi
  local st="$1" t="$2" d="${3:-0}" i s name start lines=()
  mapfile -t lines < "$UI_PANEL_FILE"
  for i in "${!lines[@]}"; do
    IFS='|' read -r s name start _ <<< "${lines[$i]}"
    [[ "$name" == "$t" ]] || continue
    if [[ "$st" == running && "$s" == pending ]]; then lines[i]="running|$t|$(date +%s)|0"; break; fi
    if [[ "$st" != running && "$s" == running ]]; then lines[i]="$st|$t|$start|$d"; break; fi
  done
  printf '%s\n' "${lines[@]}" > "$UI_PANEL_FILE"
  [[ "$st" == running ]] || : > "$UI_PANEL_FILE.sub"
  ui_panel_draw
}

# ui_panel_draw: redraw the pinned rows (keeps the cursor where it was).
ui_panel_draw() {
  [[ -n "$UI_PANEL_FILE" && -f "$UI_PANEL_FILE" ]] || return 0
  local cols='' now title t0 sub st name start d icon col right left row=1 frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' out
  read -r _ cols < <(term_size); [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  now=$(date +%s)
  IFS='|' read -r title t0 < "$UI_PANEL_FILE.head"
  sub="$(< "$UI_PANEL_FILE.sub")"
  # line <row> <left text> <left colour> <right text>: one row, cut to the window width
  line() {
    local l="$2" r="$4" max=$(( cols - ${#4} - 4 ))
    (( ${#l} > max )) && l="${l:0:max-1}…"
    out+=$(printf '\e[%d;1H\e[2K %s%s%s%*s%s%s%s' "$1" "$3" "$l" "$C_N" $(( cols - ${#l} - ${#r} - 2 )) '' "$C_DIM" "$r" "$C_N")
  }
  out=$'\e7'
  line $((row++)) "$title" "$C_ACC$C_B" "$(fmt_time $((now - t0)))"
  while IFS='|' read -r st name start d; do
    case "$st" in
      pending)   icon='·' col="$C_DIM";  right='' ;;
      running)   icon="${frames:now%10:1}" col="$C_B"; right="$(fmt_time $((now - start)))"
                 [[ -n "$sub" ]] && name+=" › $sub" ;;
      # (Not right="$( ((d >= 2)) && ...)": that assignment fails for a short step, which
      # stops a step that's drawing the panel from its spinner, under set -e.)
      ok)        icon='✔' col="$C_OK";   right=''; if (( d >= 2 )); then right="$(fmt_time "$d")"; fi ;;
      already)   icon='✔' col="$C_DIM";  right='already done' ;;
      skip)      icon='↷' col="$C_WARN"; right='skipped' ;;
      notneeded) icon='–' col="$C_DIM";  right='not needed' ;;
      *)         icon='✘' col="$C_ERR";  right='failed' ;;
    esac
    line $((row++)) " $icon $name" "$col" "$right"
  done < "$UI_PANEL_FILE"
  out+=$(printf '\e[%d;1H\e[2K%s%s%s' "$row" "$C_DIM" "$(printf '%*s' "$cols" '' | sed 's/ /─/g')" "$C_N")
  unset -f line
  printf '%s\e8' "$out"
}

ui_panel_resize() {
  local rows=''
  read -r rows _ < <(term_size)
  if [[ ! "$rows" =~ ^[0-9]+$ ]] || (( rows < UI_PANEL_ROWS + 10 )); then ui_panel_stop; return; fi
  printf '\e7\e[%d;%dr\e8' $((UI_PANEL_ROWS + 1)) "$rows"
  ui_panel_draw
}

# ui_panel_stop: leave the final panel on screen and give the whole terminal back.
ui_panel_stop() {
  [[ "$UI_NESTED" == 0 && -n "$UI_PANEL_FILE" && -f "$UI_PANEL_FILE" ]] || return 0
  ui_panel_draw
  printf '\e7\e[r\e8\e[?25h'
  rm -f "$UI_PANEL_FILE" "$UI_PANEL_FILE.head" "$UI_PANEL_FILE.sub"
  UI_PANEL_FILE=''
  trap - WINCH
}

# --- Clock check -------------------------------------------------------------------
# apt refuses update sources whose release files look like they're "from the future",
# which happens when the clock is wrong (for example a VM resumed from a saved state).
# It can also be wrong on a real computer: dual-booting Windows, or a flat clock battery.
# Compares this computer's clock with GitHub's; fails if they differ by over 5 minutes.
# Uses curl, or wget (on a fresh Ubuntu curl isn't installed yet).
CLOCK_OFF=""
CLOCK_SERVER=""   # the real time (seconds since 1970), from the last check
check_clock() {
  local server="" now diff
  if have curl; then
    server="$(curl -fsSI --max-time 10 https://github.com 2>/dev/null | tr -d '\r' \
      | awk -F': ' 'tolower($1)=="date"{print $2; exit}')"
  elif have wget; then
    server="$(wget -qS --spider --timeout=10 https://github.com 2>&1 | tr -d '\r' \
      | sed 's/^ *//' | awk -F': ' 'tolower($1)=="date"{print $2; exit}')"
  fi
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
  printf '\n%sClock%s\n' "$C_B" "$C_N"
  warn "This computer's clock is $CLOCK_OFF the real time."
  echo "    Installs would fail with \"Release file ... is not valid yet\"."
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    if command -v chronyc >/dev/null; then
      echo "    would offer to fix it with chrony: sudo chronyc makestep"
    else
      echo "    would offer to fix it: sudo systemctl restart systemd-timesyncd"
    fi
    echo "    (and if that doesn't work, set the clock from the internet time)"
    return 0
  fi
  if ask "Fix the clock now?"; then
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
  ask "Continue anyway? Installs will probably fail." || { echo "Stopped. Nothing was installed."; exit 1; }
}

# --- Fonts ----------------------------------------------------------------------------
# The two fonts install.sh downloads, each pinned to one version and its checksum (moving
# to a newer one: docs/maintenance.md). dot check compares what's installed with these.
NERD_FONT_VERSION="v3.5.1"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONT_VERSION/RobotoMono.tar.xz"
NERD_FONT_SHA256="61f53438b240a00c87c92dc2c372db0bbb264473b36a8144ea62babf787f8383"
NERD_FONT_PIN="$NERD_FONT_DIR/.pinned-sha256"   # written by install.sh: which archive it came from
ROBOTO_MONO_URL="https://raw.githubusercontent.com/google/fonts/333480ba7b601a89b75e5e84352c6cdf48086593/ofl/robotomono"
ROBOTO_MONO_FILES=(   # file|sha256
  "RobotoMono[wght].ttf|66a80e79d17e4c7cabd162e2916578a4cc08fd19eef6e2a643305eae9c567b2b"
  "RobotoMono-Italic[wght].ttf|49ac343bb7b070071e53f0a8a501d68d140ed98ebd0a43b6b8fb96cf22f09ff7")
# Is the pinned version installed (and seen by fontconfig)?
nerd_font_current() { [[ "$(cat "$NERD_FONT_PIN" 2>/dev/null)" == "$NERD_FONT_SHA256" ]] && has_nerd_font; }
roboto_mono_current() {
  local f file
  for f in "${ROBOTO_MONO_FILES[@]}"; do
    file="$MONO_FONT_DIR/${f%%|*}"
    [[ -f "$file" && "$(sha256sum "$file" | cut -d' ' -f1)" == "${f#*|}" ]] || return 1
  done
  has_roboto_mono
}

# Does bat know its Catppuccin theme? (It reads themes from a cache that `batcat cache
# --build` makes from ~/.config/bat/themes.)
bat_theme_ok() { [[ "$(batcat --list-themes 2>/dev/null)" == *"Catppuccin Mocha"* ]]; }

# Is a font family installed? (Not `fc-list | grep -q`: with pipefail that fails when
# grep stops reading fc-list's long output early.)
has_font() { [[ "$(fc-list : family 2>/dev/null)" == *"$1"* ]]; }
# The terminal's font (Ghostty, Ptyxis, VS Code): Roboto Mono with Nerd Font icons.
has_nerd_font() { has_font "RobotoMono Nerd Font"; }
# Plain Roboto Mono: the desktop's monospace font (fontconfig and GNOME settings).
# Ubuntu has no package for it; Roboto itself comes from fonts-roboto (apt-packages.txt).
has_roboto_mono() { has_font "Roboto Mono"; }   # (the Nerd Font is "RobotoMono", no space)

# --- What the dotfiles added (for dot uninstall) -------------------------------------------
# One line per thing install.sh, install-apps.sh or fresh-install.sh installed or switched
# on that wasn't there before: app:<choice>, pkg:<package>, flatpak:<ID>, extension:<uuid>,
# firewall, snapfirefox (removed). dot uninstall removes only these, so an app, extension
# or firewall you had before stays. Not in ~/.config/dotfiles, which uninstall deletes first.
# A computer set up before this record existed gets "legacy": then nobody knows what was
# there before, and uninstall offers everything, as it used to.
ADDED_FILE="${ADDED_FILE:-$HOME/.local/state/dotfiles/added}"
WEEKLY_JOB="${WEEKLY_JOB:-/etc/cron.weekly/system-update}"   # a sign of an earlier setup (tests use another)
# added_init: start the record (at the start of a run, before anything is installed)
added_init() {
  [[ "$DRY_RUN" == 1 || -f "$ADDED_FILE" ]] && return 0
  mkdir -p "$(dirname "$ADDED_FILE")"
  { echo "# What the dotfiles added to this computer (dot uninstall removes only these)."
    if [[ -f "$WEEKLY_JOB" || -f "$WALLPAPER" \
          || "$(readlink -f "$HOME/.bashrc" 2>/dev/null)" == "$DOTFILES/"* ]]; then
      echo "# Set up before this record was kept, so what was there before isn't known:"
      echo legacy
    fi; } > "$ADDED_FILE"
}
# mark_added <item>: note that the dotfiles added it (nothing in a dry run)
mark_added() {
  [[ "$DRY_RUN" == 1 ]] && return 0
  [[ -f "$ADDED_FILE" ]] || added_init
  grep -qxF -- "$1" "$ADDED_FILE" 2>/dev/null || echo "$1" >> "$ADDED_FILE"
}
# added_is_legacy: was this computer set up before the record was kept?
added_is_legacy() { [[ -f "$ADDED_FILE" ]] && grep -qx legacy "$ADDED_FILE"; }
# added_write <item>...: replace the record with exactly these (dot check's fixes, after you
# said which ones the dotfiles added): no longer legacy.
added_write() {
  mkdir -p "$(dirname "$ADDED_FILE")"
  { echo "# What the dotfiles added to this computer (dot uninstall removes only these)."
    echo "# Written by dot check on $(date +%F), from your answers."
    if (( $# )); then printf '%s\n' "$@"; fi; } > "$ADDED_FILE"
}
# was_added <item>: did the dotfiles add it? (Yes for everything without a record, or a legacy one.)
was_added() {
  [[ ! -f "$ADDED_FILE" ]] || grep -qxF -e legacy -e "$1" "$ADDED_FILE"
}

# fill_user <file>: print a system/ script with @USER@ replaced by this user's name.
fill_user() { sed "s/@USER@/$(id -un)/g" "$1"; }
# fill_home <file>: print a saved setup/ file with @HOME@ replaced by this home folder
# (scripts/save-app-settings.sh and dump-desktop-settings.sh store it that way).
fill_home() { sed "s|@HOME@|$HOME|g" "$1"; }
