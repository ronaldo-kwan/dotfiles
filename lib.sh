#!/usr/bin/env bash
# Shared helpers for install.sh, install-apps.sh, fresh-install.sh, check.sh and
# post-upgrade.sh. Source it after setting -uo pipefail:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck disable=SC2034  # DOTFILES, SETUP and FAILED are used by the scripts that source this

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DOTFILES/setup"
FAILED=()
# Terminal tools from apt (installed by fresh-install.sh, checked by check.sh)
TOOLS=(git gh gum curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak)
# Stow packages: folders here whose files are linked into your home folder
PACKAGES=(bash git starship ghostty btop lazygit terminal-default vscode claude systemd)

have() { command -v "$1" >/dev/null 2>&1; }

# --- Choices: what to set up (picked on the website, or everything) ----------------------
# DOTFILES_CHOICES lists what to set up, separated by spaces. Groups: terminal desktop
# notes safety updates firewall nvidia firmware claude-md nosnapfirefox; single apps:
# app:chrome app:code app:claude app:protonvpn app:obs app:onlyoffice app:steam,
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
DOTFILES_CHOICES="$(echo ${DOTFILES_CHOICES:-})" DOTFILES_SKIP="$(echo ${DOTFILES_SKIP:-})"   # tidy spacing
export DOTFILES_CHOICES DOTFILES_SKIP
chosen() {
  [[ " $DOTFILES_SKIP " == *" $1 "* ]] && return 1
  [[ -z "$DOTFILES_CHOICES" || " $DOTFILES_CHOICES " == *" $1 "* ]]
}
# need <choice>: in a step, skip it (with a note) unless it was chosen
need() { chosen "$1" && return 0; skip "not chosen"; return 1; }
# Is any choice starting with <prefix> (e.g. "pkg:") picked?
chosen_any() { [[ -z "$DOTFILES_CHOICES" || " $DOTFILES_CHOICES" == *" $1"* ]]; }

# The stow packages for what was chosen (git always: name, email and signing).
chosen_packages() {
  local p
  for p in "${PACKAGES[@]}"; do
    case "$p" in
      bash|starship|ghostty|btop|lazygit|terminal-default) chosen terminal && echo "$p" ;;
      vscode)  chosen app:code && echo "$p" ;;
      claude)  chosen claude-md && echo "$p" ;;
      systemd) chosen safety && echo "$p" ;;
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
  local t0=$SECONDS rc=0 pid i=0 frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  mkdir -p "$(dirname "$UI_LOG")"
  printf '\n### %s  %s\n' "$(date '+%F %T')" "$*" >> "$UI_LOG"
  local from; from=$(( $(stat -c %s "$UI_LOG") + 1 ))   # where this command's output starts
  if [[ "$UI_TTY" == 1 ]]; then
    "$@" >> "$UI_LOG" 2>&1 < /dev/null &
    pid=$!
    local prev_int; prev_int="$(trap -p INT)"
    trap 'printf "\e[?25h"; kill "$pid" 2>/dev/null' INT TERM
    printf '\e[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      (( i == 0 )) && ui_panel_draw     # once a second: the panel's timer
      printf '\r    %s%s%s %s %s%s%s\e[K' "$C_ACC" "${frames:i:1}" "$C_N" "$label" "$C_DIM" "$(fmt_time $((SECONDS - t0)))" "$C_N"
      i=$(( (i + 1) % 10 ))
      sleep 0.1
    done
    wait "$pid" || rc=$?
    printf '\r\e[K\e[?25h'
    trap - INT TERM
    [[ -n "$prev_int" ]] && eval "$prev_int"
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

# keep_sudo: ask for the password once, then keep sudo signed in until this script
# ends, so a long run (big downloads) doesn't stop halfway to ask again.
keep_sudo() {
  [[ -n "${SUDO_KEPT:-}" ]] && return 0
  sudo -v || return 1
  SUDO_KEPT=1
  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do sudo -n true; sleep 50; done ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# installed <package>: is this apt package installed?
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# repo_state <dir>: prints "uncommitted" and/or "unpushed"
repo_state() {
  local d="$1"
  [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]] && echo uncommitted
  [[ -n "$(git -C "$d" log --oneline '@{u}..' 2>/dev/null)" ]] && echo unpushed
  return 0
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
  prev="$(trap -p EXIT)"; prev="${prev#trap -- \'}"; prev="${prev%\' EXIT}"
  # shellcheck disable=SC2064  # $prev is meant to be expanded now
  trap "ui_panel_stop; $prev" EXIT
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
      ok)        icon='✔' col="$C_OK";   right="$( ((d >= 2)) && fmt_time "$d")" ;;
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

# Is the JetBrainsMono Nerd Font installed? (Not `fc-list | grep -q`: with pipefail
# that fails when grep stops reading fc-list's long output early.)
has_nerd_font() { [[ "$(fc-list 2>/dev/null)" == *"JetBrainsMono Nerd Font"* ]]; }

# Packages that install-apps.sh installs itself (not from setup/apt-packages.txt).
APP_PACKAGES=(google-chrome-stable code claude-desktop protonvpn-stable-release proton-vpn-gnome-desktop
  obs-studio onlyoffice-desktopeditors steam-installer 'nvidia-driver-*' 'libnvidia-gl-*'
  'linux-modules-nvidia-*' ufw)
# Added by Ubuntu itself (language support adds dictionaries for your languages).
UBUNTU_AUTO_PACKAGES=('language-pack-*' 'hunspell-*' 'hyphen-*' 'mythes-*' wbritish wamerican)

# unsaved_apt_packages: Ubuntu packages you installed yourself (apt, App Center, a .deb)
# that are still installed but in none of the dotfiles lists, so a new computer
# wouldn't get them. Read from apt's history; Ubuntu's installer is left out.
# A line "-name" in setup/apt-packages.txt marks one as "on purpose, not for new computers".
unsaved_apt_packages() {
  local known manual
  known="$( { printf '%s\n' "${TOOLS[@]}" "${APP_PACKAGES[@]}" "${UBUNTU_AUTO_PACKAGES[@]}"
              sed 's/#.*//' "$SETUP/apt-packages.txt" | awk 'NF{sub(/^-/, "", $1); print $1}'; } )"
  manual="$(apt-mark showmanual 2>/dev/null)"
  { cat /var/log/apt/history.log 2>/dev/null; zcat /var/log/apt/history.log.*.gz 2>/dev/null; } | awk '
    /^Commandline:/ { mine = !/force-unsafe-io|pkgDepCache::AutoInstall|unattended-upgrade/; next }
    /^Install:/ && mine {
      sub(/^Install: /, ""); n = split($0, parts, /\), /)
      for (i = 1; i <= n; i++) if (parts[i] !~ /automatic/) { split(parts[i], w, /[: ]/); print w[1] }
    }' | sort -u | while read -r p; do
      grep -qxF "$p" <<< "$manual" || continue                 # removed, or only a dependency
      local k hit=0
      # shellcheck disable=SC2053  # $k may be a pattern like nvidia-driver-*
      while read -r k; do [[ -n "$k" && "$p" == $k ]] && { hit=1; break; }; done <<< "$known"
      (( hit )) || echo "$p"
    done
  return 0
}

# fill_user <file>: print a system/ script with @USER@ replaced by this user's name.
fill_user() { sed "s/@USER@/$(id -un)/g" "$1"; }
