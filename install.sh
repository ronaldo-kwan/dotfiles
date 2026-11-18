#!/usr/bin/env bash
# Set up this computer from ~/dotfiles. Safe to run more than once.
#
# Needs (install first, see README):
#   sudo apt install git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
#
# Does NOT use sudo. Steps that need sudo or a sign-in are listed at the end.
# If one step fails, the others still run, and failures are listed at the end.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DOTFILES/setup"
PACKAGES=(bash git starship ghostty btop lazygit terminal-default vscode claude)
FAILED=()

say()  { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
skip() { printf '    skipped: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Run one step in a subshell with "stop on error", and record it if it fails.
run_step() {
  local title="$1"; shift
  say "$title"
  ( set -e; "$@" )
  local rc=$?
  if (( rc != 0 )); then
    printf '    \033[1;31mfailed\033[0m (exit code %s)\n' "$rc"
    FAILED+=("$title")
  fi
}

# 1. Link config files with stow ------------------------------------------------
link_configs() {
  if ! have stow; then
    skip "stow isn't installed (sudo apt install stow), so nothing was linked"
    return 0
  fi
  for pkg in "${PACKAGES[@]}"; do
    # Move aside real files that stow would refuse to replace.
    while IFS= read -r -d '' src; do
      target="$HOME/${src#"$DOTFILES/$pkg/"}"
      if [[ -e "$target" && ! -L "$target" ]]; then
        mv "$target" "$target.orig"
        echo "    kept existing ${target/#$HOME/\~} as ${target/#$HOME/\~}.orig"
      fi
    done < <(find "$DOTFILES/$pkg" -type f -print0)
  done
  # --no-folding links individual files, so apps that write extra files into
  # their config folder (like btop's log) don't write them into this repo.
  stow --dir="$DOTFILES" --target="$HOME" --no-folding --restow "${PACKAGES[@]}"
  echo "    linked: ${PACKAGES[*]}"
}

# 2. JetBrainsMono Nerd Font -----------------------------------------------------
install_font() {
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont" tmp
  if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    echo "    already installed"
    return 0
  fi
  if ! have curl; then
    skip "curl isn't installed (sudo apt install curl), so the font wasn't downloaded"
    return 0
  fi
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/JetBrainsMono.tar.xz" \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  mkdir -p "$tmp/extract" "$font_dir"
  tar -xJf "$tmp/JetBrainsMono.tar.xz" -C "$tmp/extract"
  cp "$tmp"/extract/JetBrainsMonoNerdFont-*.ttf "$font_dir/"
  rm -rf "$tmp"
  fc-cache -f "$font_dir"
  echo "    installed"
}

# 3. VS Code extensions --------------------------------------------------------------
install_vscode_extensions() {
  if ! have code; then
    skip "VS Code isn't installed yet"
    return 0
  fi
  while read -r ext; do
    [[ -z "$ext" ]] && continue
    code --install-extension "$ext" >/dev/null && echo "    $ext"
  done < "$SETUP/vscode-extensions.txt"
}

# 4. Flatpak apps ---------------------------------------------------------------
install_flatpaks() {
  if ! have flatpak; then
    skip "flatpak isn't installed (sudo apt install flatpak)"
    return 0
  fi
  if ! flatpak remotes --columns=name | grep -qx flathub; then
    skip "Flathub isn't set up. Run: sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
    return 0
  fi
  mapfile -t apps < <(grep -v '^\s*$' "$SETUP/flatpaks.txt")
  flatpak install -y --noninteractive flathub "${apps[@]}"
}

# 5. GNOME settings ----------------------------------------------------------------
restore_gnome_settings() {
  if ! have dconf || ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  dconf load /org/gnome/settings-daemon/plugins/media-keys/ < "$SETUP/gnome-shortcuts.dconf"
  dconf load /org/gnome/shell/extensions/ < "$SETUP/gnome-extension-settings.dconf"
  gsettings set org.gnome.shell favorite-apps "$(cat "$SETUP/dock-favorites.txt")"
  echo "    restored"
}

# 6. Wallpaper, dark mode and accent colour -----------------------------------------
set_look() {
  if ! have gsettings; then
    skip "not a GNOME desktop"
    return 0
  fi
  local wall_dir="$HOME/Pictures/Wallpapers/current" wall uri
  wall="$(ls "$SETUP"/wallpaper/*.jpg | head -1)"
  mkdir -p "$wall_dir"
  cp --update=none "$wall" "$wall_dir/"
  uri="file://$wall_dir/$(basename "$wall")"
  gsettings set org.gnome.desktop.background picture-uri "$uri"
  gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  gsettings set org.gnome.desktop.interface accent-color blue
  echo "    set"
}

# Main ---------------------------------------------------------------------------------
echo "This will set up your configs from $DOTFILES:"
echo "  link config files, install the Nerd Font, VS Code extensions and Flatpak apps,"
echo "  and restore keyboard shortcuts, extension settings, dock, wallpaper and accent colour."
echo "Existing files that would be replaced are kept as <name>.orig."
echo "Keyboard shortcuts replace any custom shortcuts already on this computer."
read -rp "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Nothing changed."; exit 0; }

run_step "Linking config files"                          link_configs
run_step "JetBrainsMono Nerd Font"                       install_font
run_step "VS Code extensions"                            install_vscode_extensions
run_step "Flatpak apps"                                  install_flatpaks
run_step "Keyboard shortcuts, extension settings and dock" restore_gnome_settings
run_step "Wallpaper, dark mode and accent colour"        set_look

if (( ${#FAILED[@]} > 0 )); then
  say "Finished with problems. These steps failed (see messages above):"
  printf '  - %s\n' "${FAILED[@]}"
else
  say "Done."
fi
cat <<'EOF'

Still to do yourself:
  - Install apps from their own sources: Chrome, VS Code, Claude Desktop,
    ProtonVPN, OBS (see README, "Apps from other sources").
  - Install GNOME extensions from setup/gnome-extensions.txt with Extension Manager.
  - Optional: weekly updates script in system/ (needs sudo, see README).
  - Log out and back in, then open a new terminal.
EOF

(( ${#FAILED[@]} == 0 ))
