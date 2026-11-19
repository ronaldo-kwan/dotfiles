#!/usr/bin/env bash
# Shared helpers for install.sh, install-apps.sh, fresh-install.sh, check.sh and
# post-upgrade.sh. Source it after setting -uo pipefail:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck disable=SC2034  # DOTFILES, SETUP and FAILED are used by the scripts that source this

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DOTFILES/setup"
FAILED=()
# Terminal tools from apt (installed by fresh-install.sh, checked by check.sh)
TOOLS=(git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak)
# Stow packages: folders here whose files are linked into your home folder
PACKAGES=(bash git starship ghostty btop lazygit terminal-default vscode claude systemd)

have() { command -v "$1" >/dev/null 2>&1; }

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

fmt_time() { local t="$1"; if (( t < 60 )); then printf '%ss' "$t"; else printf '%dm %02ds' $((t / 60)) $((t % 60)); fi; }

# header "Title" "line"...: the box at the start of a script.
header() {
  [[ "$UI_NESTED" == 0 ]] || return 0
  local title="$1" l w; shift
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
    trap 'printf "\e[?25h"; kill "$pid" 2>/dev/null' INT TERM
    printf '\e[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r    %s%s%s %s %s%s%s\e[K' "$C_ACC" "${frames:i:1}" "$C_N" "$label" "$C_DIM" "$(fmt_time $((SECONDS - t0)))" "$C_N"
      i=$(( (i + 1) % 10 ))
      sleep 0.1
    done
    wait "$pid" || rc=$?
    printf '\r\e[K\e[?25h'
    trap - INT TERM
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
  printf '\n  %sHow should questions be answered?%s\n' "$C_B" "$C_N"
  printf '    %sY%s  Yes to everything: it runs by itself  %s(Enter)%s\n' "$C_ACC$C_B" "$C_N" "$C_DIM" "$C_N"
  printf '    %sn%s  Ask me before each step\n' "$C_ACC$C_B" "$C_N"
  read -rp "  ${C_ACC}›${C_N} " a
  if [[ "$a" =~ ^[Nn]$ ]]; then
    YES_ALL=0; printf '  %s✔%s I'"'"'ll ask before each step %s(Enter = yes)%s\n' "$C_OK" "$C_N" "$C_DIM" "$C_N"
  else
    YES_ALL=1; printf '  %s✔%s Yes to everything: you can leave it running\n' "$C_OK" "$C_N"
  fi
  export YES_ALL
}

# ask "Question?": true unless the answer is n/N (Enter means yes). With YES_ALL=1
# it shows the question with the answer and doesn't wait.
ask() {
  if [[ "$YES_ALL" == 1 ]]; then
    printf '    %s?%s %s %s› yes%s\n' "$C_INFO" "$C_N" "$1" "$C_DIM" "$C_N"; return 0
  fi
  local a; read -rp "    ${C_INFO}?${C_N} $1 ${C_DIM}[Y/n]${C_N} " a; [[ ! "$a" =~ ^[Nn]$ ]]
}

# keep_sudo: ask for the password once, then keep sudo signed in until this script
# ends, so a long run (big downloads) doesn't stop halfway to ask again.
keep_sudo() {
  sudo -v || return 1
  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do sudo -n true; sleep 50; done ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# installed <package>: is this apt package installed?
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

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
