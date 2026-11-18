# dotfiles

My terminal and desktop setup for Ubuntu (GNOME): bash, ble.sh, Starship, fzf, zoxide, eza, bat, Ghostty, btop, lazygit, and VS Code. Everything uses Catppuccin Mocha and JetBrainsMono Nerd Font.

## What's here

The linked folders are laid out for [GNU Stow](https://www.gnu.org/software/stow/). Each one is a "package" whose contents mirror your home folder, and the real files in `~` are symlinks into this repo.

| Package | Links to | What it is |
|---|---|---|
| `bash` | `~/.bashrc` | Aliases, history, and loading for ble.sh, Starship, zoxide, fzf, eza and bat |
| `git` | `~/.gitconfig` | Name and email, `main` as the default branch, `gh` for GitHub sign-in |
| `starship` | `~/.config/starship.toml` | Minimal prompt (`pure-preset`) |
| `ghostty` | `~/.config/ghostty/config` | Catppuccin Mocha, Nerd Font, padding |
| `btop` | `~/.config/btop/` | Catppuccin Mocha theme and settings |
| `lazygit` | `~/.config/lazygit/config.yml` | Catppuccin Mocha and Nerd Font icons |
| `terminal-default` | `~/.config/xdg-terminals.list` | Makes Ghostty the default terminal |
| `vscode` | `~/.config/Code/User/settings.json` | Theme, fonts, ligatures |
| `claude` | `~/.claude/CLAUDE.md` | Personal instructions for Claude Code |

These aren't linked. `install.sh` restores them, or see the manual steps below:

| File | What it is |
|---|---|
| `install.sh` | Sets up a new computer from this repo (no sudo) |
| `setup/vscode-extensions.txt` | VS Code extensions (the Catppuccin theme) |
| `setup/flatpaks.txt` | Flatpak apps: Bitwarden, Discord, Obsidian, Firefox and others |
| `setup/gnome-shortcuts.dconf` | Custom keyboard shortcuts: Super+C/X/T/E/F/O |
| `setup/gnome-extension-settings.dconf` | Settings for Caffeine, Clipboard Indicator, Ubuntu Dock, Tiling Assistant |
| `setup/dock-favorites.txt` | Apps pinned to the dock, in order |
| `setup/gnome-extensions.txt` | GNOME extensions to install |
| `setup/wallpaper/` | Desktop wallpaper |
| `system/` | Weekly automatic update script (needs sudo) |

## Making changes

Edit files at their usual place (for example `~/.bashrc`) or in this folder. Both are the same file. Then save the change:

```bash
cd ~/dotfiles
git add -A
git commit -m "Describe the change"
```

The files in `setup/` are snapshots, so they don't update themselves. After changing extensions, apps, shortcuts or the dock, refresh them before committing:

```bash
code --list-extensions > ~/dotfiles/setup/vscode-extensions.txt
flatpak list --app --columns=application > ~/dotfiles/setup/flatpaks.txt
dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > ~/dotfiles/setup/gnome-shortcuts.dconf
dconf dump /org/gnome/shell/extensions/ > ~/dotfiles/setup/gnome-extension-settings.dconf
gsettings get org.gnome.shell favorite-apps > ~/dotfiles/setup/dock-favorites.txt
```

## Setting up a new computer

### Quick setup

```bash
sudo apt install git gh stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
gh auth login
gh repo clone dotfiles ~/dotfiles
~/dotfiles/install.sh
```

`lazygit` comes from Ubuntu Pro's extra app repository (`esm-apps`).

`install.sh` asks before doing anything. It then:
- links the config files (keeping any existing ones as `.orig`)
- installs the Nerd Font, VS Code extensions and Flatpak apps
- restores keyboard shortcuts, extension settings, dock and wallpaper

It's safe to run again. At the end it lists what's left to do by hand: the apps below, GNOME extensions, and the weekly update script.

### Apps from other sources

These don't come from Ubuntu. Each official download adds its own update source, so they then update with `sudo apt upgrade`.

| App | Where to get it | Package |
|---|---|---|
| Google Chrome | google.com/chrome (.deb) | `google-chrome-stable` |
| VS Code | code.visualstudio.com (.deb) | `code` |
| Claude Desktop | claude.ai/download | `claude-desktop` |
| Proton VPN | protonvpn.com/download (Linux, Ubuntu) | `proton-vpn-gnome-desktop` |
| OBS Studio | `sudo add-apt-repository ppa:obsproject/obs-studio` | `obs-studio` |

### GNOME extensions

Install the extensions in `setup/gnome-extensions.txt` (Alphabetical App Grid, Caffeine, Clipboard Indicator) with Extension Manager:

```bash
sudo apt install gnome-shell-extension-manager
```

Their settings are restored by `install.sh`. Run it again after installing them if you installed them afterwards.

### Weekly automatic updates (optional)

First change `DESKTOP_USER=` in the script to the new username, then:

```bash
sudo cp ~/dotfiles/system/etc/cron.weekly/system-update /etc/cron.weekly/
sudo chmod +x /etc/cron.weekly/system-update
```

### Manual setup (instead of install.sh)

<details>
<summary>Step-by-step commands</summary>

**Nerd Font**

```bash
mkdir -p ~/.local/share/fonts/JetBrainsMonoNerdFont
cd /tmp && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
mkdir -p /tmp/jbm && tar -xJf JetBrainsMono.tar.xz -C /tmp/jbm
cp /tmp/jbm/JetBrainsMonoNerdFont-*.ttf ~/.local/share/fonts/JetBrainsMonoNerdFont/
fc-cache -f
```

**Link config files.** Stow won't replace files that already exist, so move them aside first:

```bash
mv ~/.bashrc ~/.bashrc.orig
mv ~/.gitconfig ~/.gitconfig.orig 2>/dev/null
cd ~/dotfiles
stow --no-folding bash git starship ghostty btop lazygit terminal-default vscode claude
```

**VS Code extensions and Flatpak apps**

```bash
xargs -n1 code --install-extension < ~/dotfiles/setup/vscode-extensions.txt
xargs flatpak install -y flathub < ~/dotfiles/setup/flatpaks.txt
```

**Shortcuts, extension settings and dock.** The shortcuts replace any custom shortcuts already on the computer.

```bash
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < ~/dotfiles/setup/gnome-shortcuts.dconf
dconf load /org/gnome/shell/extensions/ < ~/dotfiles/setup/gnome-extension-settings.dconf
gsettings set org.gnome.shell favorite-apps "$(cat ~/dotfiles/setup/dock-favorites.txt)"
```

**Wallpaper and dark mode**

```bash
mkdir -p ~/Pictures/Wallpapers/current
cp ~/dotfiles/setup/wallpaper/catppuccin-tropic-island-night.jpg ~/Pictures/Wallpapers/current/
W="file://$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night.jpg"
gsettings set org.gnome.desktop.background picture-uri "$W"
gsettings set org.gnome.desktop.background picture-uri-dark "$W"
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
```

**Ptyxis font** (if you still use Ptyxis)

```bash
gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 10'
```

</details>
