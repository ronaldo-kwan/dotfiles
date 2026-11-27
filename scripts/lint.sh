#!/usr/bin/env bash
# Looks for mistakes in the scripts without running them: syntax (bash -n, sh -n),
# the shellcheck linter (every level, with .shellcheckrc), pyflakes for the Python and node --check
# for the website's scripts. Changes nothing. Run by GitHub's checks
# (.github/workflows/check.yml) on Ubuntu 26.04, so the same versions as here, or by hand:
#   sudo apt install shellcheck pyflakes3 nodejs
#   bash scripts/lint.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

missing=()
for tool in shellcheck pyflakes3 node; do command -v "$tool" >/dev/null || missing+=("$tool"); done
if (( ${#missing[@]} )); then
  echo "Missing: ${missing[*]}. Install them with: sudo apt install shellcheck pyflakes3 nodejs"
  exit 1
fi

bash_files=(bootstrap.sh bin/*.sh dot scripts/*.sh .githooks/pre-commit home/bash/.bashrc)
sh_files=(system/etc/cron.*/*)
rc=0
step() {   # step "what" command...: run one check, and say how it went
  if "${@:2}"; then printf '✔ %s\n' "$1"; else printf '✘ %s\n' "$1"; rc=1; fi
}
syntax() {
  local f ok=0
  for f in "${bash_files[@]}"; do bash -n "$f" || ok=1; done
  for f in "${sh_files[@]}"; do sh -n "$f" || ok=1; done
  return "$ok"
}
node_check() {
  local f ok=0
  while IFS= read -r f; do node --check "$f" || ok=1; done < <(git ls-files 'site/*.js')
  return "$ok"
}

step "syntax (bash -n, sh -n)" syntax
step "shellcheck $(shellcheck --version | sed -n 's/^version: //p')" \
  shellcheck -x -S style "${bash_files[@]}" "${sh_files[@]}"
step "pyflakes (scripts/*.py)" pyflakes3 scripts/*.py
step "node --check (site/**/*.js)" node_check
exit "$rc"
