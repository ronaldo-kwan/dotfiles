#!/usr/bin/env bash
# dot ssh: an SSH key for this computer, and signed commits ("Verified" on GitHub).
#   1. Creates ~/.ssh/id_ed25519 if there's none (one key per computer; the key
#      never leaves it and never goes into a repo).
#   2. Turns on commit signing with it (~/.config/git/signing.gitconfig, which
#      ~/.gitconfig includes; without a key there's no such file and nothing changes).
#   3. Adds the key to your GitHub account twice: to sign in (git over SSH, gh) and
#      to show your commits as Verified. That needs one approval in the browser.
# Safe to run again: finished parts are skipped.

set -uo pipefail
# shellcheck source=../bin/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../bin/lib.sh"

KEY="$HOME/.ssh/id_ed25519"
SIGNING="$HOME/.config/git/signing.gitconfig"
SIGNERS="$HOME/.config/git/allowed_signers"

# install.sh runs only the signing part (never creates keys): ssh-setup.sh --signing-only
SIGNING_ONLY=0; [[ "${1:-}" == "--signing-only" ]] && SIGNING_ONLY=1

[[ "$SIGNING_ONLY" == 1 ]] || header "SSH key and signed commits" \
  "Creates an SSH key for this computer if there's none, signs your commits" \
  "with it, and adds it to GitHub (one approval in the browser)."
# shellcheck disable=SC2034  # read by run_step in lib.sh
STEP_TOTAL=3

# 1. Key ------------------------------------------------------------------------------
make_key() {
  if [[ -f "$KEY" ]]; then note "already there: ${KEY/#$HOME/\~}"; return 0; fi
  ask "Create an SSH key for this computer?" || { skip "you chose not to"; return 0; }
  note "choose a passphrase (recommended); GNOME remembers it after you log in"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$(git config user.email) ($(hostname))" -f "$KEY"
}

# 2. Signing (also run by install.sh, which never creates keys) -----------------------
signing_config() {
  if [[ ! -f "$KEY.pub" ]]; then skip "no SSH key yet (run: dot ssh)"; return 0; fi
  # GitHub matches a signature to you by this email, so it's needed first.
  local email; email="$(git config user.email || true)"
  if [[ -z "$email" ]]; then skip "git doesn't know your email yet (dot install asks for it)"; return 0; fi
  mkdir -p "$(dirname "$SIGNING")"
  printf '%s %s\n' "$email" "$(cut -d' ' -f1,2 "$KEY.pub")" > "$SIGNERS"
  cat > "$SIGNING" <<EOF
# Written by ~/dotfiles (dot ssh / install.sh): sign commits and tags with this
# computer's SSH key. Delete this file to stop signing.
[gpg]
	format = ssh
[gpg "ssh"]
	allowedSignersFile = $SIGNERS
[user]
	signingkey = $KEY.pub
[commit]
	gpgsign = true
[tag]
	gpgsign = true
EOF
  note "commits and tags are now signed with ${KEY/#$HOME/\~}"
}

# 3. GitHub ---------------------------------------------------------------------------
# key_on_github <type>: is this key already on GitHub as that type?
key_on_github() {
  local pub; pub="$(cut -d' ' -f2 "$KEY.pub")"
  gh api "user/$1" --paginate --jq '.[].key' 2>/dev/null | grep -qF "$pub"
}
add_to_github() {
  if [[ ! -f "$KEY.pub" ]]; then skip "no SSH key yet"; return 0; fi
  if ! have gh || ! gh auth status >/dev/null 2>&1; then
    skip "gh isn't signed in (run: gh auth login, then dot ssh again)"; return 0
  fi
  # Adding keys needs two extra permissions for gh; ask GitHub for them once.
  if ! gh api user/keys >/dev/null 2>&1 || ! gh api user/ssh_signing_keys >/dev/null 2>&1; then
    note "gh needs permission to add keys: approve it in the browser that opens"
    gh auth refresh -h github.com -s "$GH_KEY_SCOPES"
  fi
  local title; title="$(hostname) ($(date +%Y-%m))"
  if key_on_github keys; then note "already on GitHub for signing in"
  else gh ssh-key add "$KEY.pub" --type authentication --title "$title"; fi
  if key_on_github ssh_signing_keys; then note "already on GitHub for Verified commits"
  else gh ssh-key add "$KEY.pub" --type signing --title "$title"; fi
  # Done: take that permission away again, so a leaked gh sign-in can't be used to
  # add someone else's key to your account.
  if gh_key_admin; then
    note "removing gh's permission to add keys again: approve once more in the browser"
    gh auth refresh -h github.com --remove-scopes "$GH_KEY_SCOPES"
  fi
}

if [[ "$SIGNING_ONLY" == 1 ]]; then signing_config; exit; fi

yes_flag "$@"
choose_answer_mode
run_step "SSH key for this computer" make_key
run_step "Sign commits with it" signing_config
run_step "Add it to GitHub" add_to_github
summary || exit 1
printf '\n%sCheck:%s your next commit shows "Verified" on GitHub; locally: git log --show-signature -1\n' "$C_B" "$C_N"
