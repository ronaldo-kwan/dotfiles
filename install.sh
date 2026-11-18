#!/usr/bin/env bash
# Set up this computer from ~/dotfiles. Safe to run more than once.
#
# Needs (install first, see README step 1):
#   sudo apt install git gh stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit
#
# Does NOT use sudo. Steps that need sudo or a sign-in are listed at the end.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DOTFILES/setup"
PACKAGES=(bash git starship ghostty btop lazygit terminal-default vscode claude)

say()  { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
skip() { printf '    skipped: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "This will set up your configs from $DOTFILES:"
echo "  link config files, install the Nerd Font, VS Code extensions and Flatpak apps,"
echo "  and restore keyboard shortcuts, extension settings, dock, wallpaper and accent colour."
echo "Existing files that would be replaced are kept as <name>.orig."
echo "Keyboard shortcuts replace any custom shortcuts already on this computer."
read -rp "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Nothing changed."; exit 0; }

# 1. Link config files with stow ------------------------------------------------
say "Linking config files"
if have stow; then
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
else
  skip "stow isn't installed (sudo apt install stow), so nothing was linked"
fi

# 2. JetBrainsMono Nerd Font -----------------------------------------------------
say "JetBrainsMono Nerd Font"
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
  echo "    already installed"
else
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/JetBrainsMono.tar.xz" \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  mkdir -p "$tmp/extract" "$FONT_DIR"
  tar -xJf "$tmp/JetBrainsMono.tar.xz" -C "$tmp/extract"
  cp "$tmp"/extract/JetBrainsMonoNerdFont-*.ttf "$FONT_DIR/"
  rm -rf "$tmp"
  fc-cache -f "$FONT_DIR"
  echo "    installed"
fi

# 3. VS Code extensions --------------------------------------------------------------
say "VS Code extensions"
if have code; then
  while read -r ext; do
    [[ -z "$ext" ]] && continue
    code --install-extension "$ext" >/dev/null && echo "    $ext"
  done < "$SETUP/vscode-extensions.txt"
else
  skip "VS Code isn't installed yet"
fi

# 4. Flatpak apps ---------------------------------------------------------------
say "Flatpak apps"
if have flatpak && flatpak remotes --columns=name | grep -qx flathub; then
  mapfile -t apps < <(grep -v '^\s*$' "$SETUP/flatpaks.txt")
  flatpak install -y --noninteractive flathub "${apps[@]}"
elif have flatpak; then
  skip "Flathub isn't set up. Run: flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
else
  skip "flatpak isn't installed (sudo apt install flatpak)"
fi

# 5. GNOME settings ----------------------------------------------------------------
say "Keyboard shortcuts, extension settings and dock"
if have dconf && have gsettings; then
  dconf load /org/gnome/settings-daemon/plugins/media-keys/ < "$SETUP/gnome-shortcuts.dconf"
  dconf load /org/gnome/shell/extensions/ < "$SETUP/gnome-extension-settings.dconf"
  gsettings set org.gnome.shell favorite-apps "$(cat "$SETUP/dock-favorites.txt")"
  echo "    restored"
else
  skip "not a GNOME desktop"
fi

# 6. Wallpaper, dark mode and accent colour -----------------------------------------
say "Wallpaper, dark mode and accent colour"
if have gsettings; then
  WALL_DIR="$HOME/Pictures/Wallpapers/current"
  mkdir -p "$WALL_DIR"
  cp -n "$SETUP"/wallpaper/*.jpg "$WALL_DIR/"
  uri="file://$WALL_DIR/$(basename "$(ls "$SETUP"/wallpaper/*.jpg | head -1)")"
  gsettings set org.gnome.desktop.background picture-uri "$uri"
  gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  gsettings set org.gnome.desktop.interface accent-color blue
  echo "    set"
fi

# Still to do by hand ----------------------------------------------------------------
say "Done. Still to do yourself:"
cat <<'EOF'
  - Install apps from their own sources: Chrome, VS Code, Claude Desktop,
    ProtonVPN, OBS (see README, "Apps from other sources").
  - Install GNOME extensions from setup/gnome-extensions.txt with Extension Manager.
  - Optional: weekly updates script in system/ (needs sudo, see README).
  - Open a new terminal to load the new bash setup.
EOF
