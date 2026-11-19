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
| `install-apps.sh` | Optional: installs Chrome, VS Code, Claude Desktop, Proton VPN, OBS, ONLYOFFICE, Steam and the Ubuntu apps below (uses sudo) |
| `setup/vscode-extensions.txt` | VS Code extensions (the Catppuccin theme) |
| `setup/apt-packages.txt` | Ubuntu apps I installed myself: VLC, qBittorrent, Tweaks, Extension Manager, Backups, Software. Edit by hand. |
| `setup/flatpaks.txt` | Flatpak apps: Bitwarden, Discord, Obsidian, Firefox and others |
| `setup/gnome-desktop.dconf` | Desktop look: Adwaita theme and icons, fonts, dark mode, blue accent, close-only window buttons, 4 fixed workspaces, and which extensions are on or off (Ubuntu Dock, desktop icons and web search are off) |
| `setup/gnome-shortcuts.dconf` | Custom keyboard shortcuts: Super+C/X/T/E/F/O |
| `setup/gnome-extension-settings.dconf` | Settings for Caffeine, Clipboard Indicator, Ubuntu Dock, Tiling Assistant |
| `setup/dock-favorites.txt` | Apps pinned to the dock, in order |
| `setup/gnome-extensions.txt` | GNOME extensions that `install.sh` installs from extensions.gnome.org |
| `setup/wallpaper/` | Desktop wallpaper |
| `system/` | Weekly automatic update script (needs sudo) |

## Making changes

Edit files at their usual place (for example `~/.bashrc`) or in this folder. Both are the same file. Then save the change:

```bash
cd ~/dotfiles
git add -A
git commit -m "Describe the change"
```

The files in `setup/` are snapshots, so they don't update themselves. After changing extensions, apps, shortcuts, the dock or desktop settings like the theme, run `dotsave` (defined in `.bashrc`). It refreshes all of them and shows what changed, without committing:

```bash
dotsave
```

`dotsave` runs these commands, plus a snapshot of the desktop look settings into `gnome-desktop.dconf` (see `.bashrc`):

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
sudo apt install git gh curl stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit flatpak
gh auth login
gh repo clone dotfiles ~/dotfiles
~/dotfiles/install.sh
~/dotfiles/install-apps.sh   # optional, see below
~/dotfiles/install.sh        # again, only if you installed VS Code, to add its extensions
```

Then log out and back in.

`lazygit` comes from Ubuntu Pro's extra app repository (`esm-apps`).

`install.sh` asks before doing anything. It then:
- links the config files (keeping any existing ones as `.orig`)
- installs the Nerd Font, VS Code extensions, Flatpak apps and GNOME extensions (the versions matching this computer's GNOME, from extensions.gnome.org)
- restores your desktop look (theme, icons, dark mode, accent colour, window buttons, workspaces), keyboard shortcuts, extension settings, dock and wallpaper

It's safe to run again. If a step fails, the others still run, and the failures are listed at the end. GNOME extensions start working after you log out and back in.

Display scaling isn't saved, because it depends on the screen. Set it in **Settings → Displays → Scale** if text looks too small or large.

### Apps from other sources

These need sudo and extra setup, so `install.sh` doesn't install them. Run `install-apps.sh` instead. It uses sudo, asks before each app, and skips any already installed:

```bash
~/dotfiles/install-apps.sh            # asks before each app
~/dotfiles/install-apps.sh --all      # installs all of them
DRY_RUN=1 ~/dotfiles/install-apps.sh  # only checks the downloads, installs nothing
```

Each app comes from its maker's official source, which then keeps it updated with `sudo apt upgrade`. The Claude Desktop and ONLYOFFICE signing keys' fingerprints and Proton's setup package checksum are checked before installing. If ONLYOFFICE is installed without its update source (for example from a downloaded `.deb`), the script offers to add the source so it gets updates.

It first checks the computer's clock against the internet. If it's more than 5 minutes off (common in a VM resumed from a saved state), installs would fail with "Release file … is not valid yet", so it offers to fix the clock (`sudo systemctl restart systemd-timesyncd`) before going on. If a maker changes its download link, update the script; the table shows the manual way:

| App | Where to get it | Package |
|---|---|---|
| Google Chrome | google.com/chrome (.deb) | `google-chrome-stable` |
| VS Code | code.visualstudio.com (.deb) | `code` |
| Claude Desktop | claude.ai/download | `claude-desktop` |
| Proton VPN | protonvpn.com/download (Linux, Ubuntu) | `proton-vpn-gnome-desktop` |
| OBS Studio | `sudo add-apt-repository ppa:obsproject/obs-studio` | `obs-studio` |
| ONLYOFFICE | ONLYOFFICE's update source (key from download.onlyoffice.com/GPG-KEY-ONLYOFFICE) | `onlyoffice-desktopeditors` |
| Steam | Ubuntu's own package; needs 32-bit support: `sudo dpkg --add-architecture i386` | `steam-installer` |
| Ubuntu apps | `sudo apt install` the packages in `setup/apt-packages.txt` | see the file |

**Steam's files aren't in this repo on purpose.** `~/.steam` holds your Steam sign-in, games and Steam's own program files. On a new computer, install Steam, sign in, and reinstall games; Steam Cloud brings back saves for games that support it.

### GNOME extensions

`install.sh` installs and enables the extensions in `setup/gnome-extensions.txt` (Alphabetical App Grid, Caffeine, Clipboard Indicator) and restores their settings. It also applies exactly which extensions are on or off, including Ubuntu's built-in ones: Ubuntu Dock, desktop icons and web search are switched off, as on the original computer. They start after you log out and back in. To add another extension to the list, put its ID (shown on its extensions.gnome.org page or by `gnome-extensions list`) in that file.

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

**Desktop look, shortcuts, extension settings and dock.** The shortcuts replace any custom shortcuts already on the computer.

```bash
dconf load /org/gnome/ < ~/dotfiles/setup/gnome-desktop.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < ~/dotfiles/setup/gnome-shortcuts.dconf
dconf load /org/gnome/shell/extensions/ < ~/dotfiles/setup/gnome-extension-settings.dconf
gsettings set org.gnome.shell favorite-apps "$(cat ~/dotfiles/setup/dock-favorites.txt)"
```

**Wallpaper**

```bash
mkdir -p ~/Pictures/Wallpapers/current
cp ~/dotfiles/setup/wallpaper/catppuccin-tropic-island-night.jpg ~/Pictures/Wallpapers/current/
W="file://$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night.jpg"
gsettings set org.gnome.desktop.background picture-uri "$W"
gsettings set org.gnome.desktop.background picture-uri-dark "$W"
```

**Ptyxis font** (if you still use Ptyxis)

```bash
gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 10'
```

</details>
