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
| `fresh-install.sh` | Sets up a freshly installed Ubuntu in one go: system and firmware update, tools, then both scripts below |
| `install.sh` | Configs, fonts, Flatpak apps, extensions and settings (no sudo) |
| `install-apps.sh` | Optional: installs Chrome, VS Code, Claude Desktop, Proton VPN, OBS, ONLYOFFICE, Steam, the Ubuntu apps below and the NVIDIA driver (plus Steam's 32-bit NVIDIA library and RTX shortcut); sets up weekly updates (uses sudo) |
| `setup/vscode-extensions.txt` | VS Code extensions (the Catppuccin theme) |
| `setup/apt-packages.txt` | Ubuntu packages I installed myself: VLC, qBittorrent, Tweaks, Extension Manager, Backups and rclone (for Google Drive), Software with Flathub, GNOME wallpapers and sounds, codecs, vainfo. Edit by hand. |
| `setup/flatpaks.txt` | Flatpak apps: Bitwarden, Discord, Obsidian, Firefox and others |
| `setup/gnome-desktop.dconf` | Desktop look: Adwaita theme and icons, fonts, dark mode, blue accent, close-only window buttons, 4 fixed workspaces, and which extensions are on or off (Ubuntu Dock, desktop icons and web search are off) |
| `setup/desktop-settings.dconf` | Window shortcuts (Super+W, Super+1–4 workspaces), screenshot shortcut, power (never sleep on AC), sound theme, Files list view, file dialogs, search order, Backups schedule, Text Editor and Ptyxis settings |
| `setup/gnome-shortcuts.dconf` | Custom keyboard shortcuts: Super+C/X/T/E/F/O |
| `setup/gnome-extension-settings.dconf` | Settings for Caffeine, Clipboard Indicator, Ubuntu Dock, Tiling Assistant |
| `setup/dock-favorites.txt` | Apps pinned to the dock, in order |
| `setup/gnome-extensions.txt` | GNOME extensions that `install.sh` installs from extensions.gnome.org |
| `setup/wallpaper/` | Desktop wallpaper |
| `setup/apps/` | Apps that start at login (Bitwarden), default apps (Chrome as browser, Showtime for video, Calendar), qBittorrent settings and Catppuccin theme, Obsidian vault settings and Catppuccin theme (not the notes). Cookies and window sizes are left out. Home-folder paths are stored as `@HOME@`. |
| `system/` | Weekly update and monthly clean-up scripts, installed by `install-apps.sh` (needs sudo) |
| `scripts/dump-desktop-settings.sh` | Used by `dotsave` to write `setup/desktop-settings.dconf` |
| `scripts/save-app-settings.sh` | Used by `dotsave` to update `setup/apps/` |

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
bash ~/dotfiles/scripts/dump-desktop-settings.sh > ~/dotfiles/setup/desktop-settings.dconf
bash ~/dotfiles/scripts/save-app-settings.sh
```

Things GNOME remembers by itself (window sizes, last-used folders, timestamps) are deliberately left out of the snapshots.

## Setting up a new computer

### Before installing Ubuntu (Lenovo Legion 5)

1. **GPU mode: Hybrid.** In Windows, open Lenovo Legion Space (or Vantage) and set the GPU mode to **Hybrid**. Without Windows: restart, press <kbd>F2</kbd> for the BIOS, and set **GPU Working Mode** to Hybrid. "Hybrid-iGPU only" hides the RTX 5060 from Ubuntu.
2. **Leave Secure Boot on.** Ubuntu's NVIDIA driver works with it.
3. Boot the Ubuntu 26.04 USB stick (<kbd>F12</kbd> at startup) and, in the installer, tick **Install third-party software for graphics and Wi-Fi hardware**.

### Fresh install: one script

After Ubuntu is installed, open a terminal (<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd>) and run these. `gh auth login` signs you in to GitHub through the browser.

```bash
sudo apt install git gh
gh auth login
gh repo clone dotfiles ~/dotfiles
~/dotfiles/fresh-install.sh
```

`fresh-install.sh` does everything in the right order and ends with a restart:

1. **Updates the system** (`apt full-upgrade`).
2. **Updates firmware** (BIOS, SSD, devices) with `fwupdmgr`, only if the charger is plugged in. It asks first.
3. **Installs the terminal tools** (Starship, eza, bat, fzf, zoxide, ble.sh, Ghostty, btop, lazygit, ...) and adds Flathub.
4. Runs **`install.sh`**: configs, fonts, Flatpak apps, GNOME extensions, desktop and app settings.
5. Runs **`install-apps.sh`**: Chrome, VS Code, Claude Desktop, Proton VPN, OBS, ONLYOFFICE, Steam, Ubuntu apps, the NVIDIA driver, weekly updates, monthly clean-up.
6. Runs **`install.sh` again**, for VS Code's extensions and Obsidian now that those apps exist.

Every question defaults to **Yes**, so press <kbd>Enter</kbd> to go on. If a step fails, the rest still run and the failures are listed at the end. Fix the cause and run it again; finished parts are skipped.

**Two screens need you:**
- **Font licence** (codecs): press <kbd>Tab</kbd> to `<Ok>` and <kbd>Enter</kbd>, then choose `<Yes>`.
- **NVIDIA with Secure Boot:** if asked, make up a short password (letters and numbers). After the restart, a blue **MOK management** screen appears: Enroll MOK → Continue → Yes → type that password → Reboot. Then `nvidia-smi` should list the RTX 5060.

**After the restart:** sign in to your apps (Steam, browsers, Discord, Bitwarden). Open **Backups**, connect Google Drive, and turn on **Back Up Automatically**. Keep the backup encryption password somewhere safe; without it the backups can't be restored.

Display scaling isn't saved, because it depends on the screen. Set it in **Settings → Displays → Scale** if text looks too small or large.

### Using the RTX 5060

Apps run on the AMD graphics built into the processor by default, which saves battery. Steam is the exception: the setup gives it a shortcut that asks for the NVIDIA card, so games started from Steam use the RTX 5060.

For any other app, right-click it in the app grid and choose **Launch using Discrete Graphics Card**. While it runs, `nvidia-smi` lists it under Processes.

### Running the parts separately

The three scripts can also be run on their own, for example on a computer that's already set up. Each is safe to run again.

- `~/dotfiles/install.sh` (no sudo): links config files (keeping existing ones as `.orig`). It installs the Nerd Font, VS Code extensions, Flatpak apps and GNOME extensions (the versions matching this computer's GNOME). It restores your desktop look, shortcuts, settings, extension settings, dock, wallpaper, app settings and the Obsidian vault. GNOME extensions start after you log out and back in.
- `~/dotfiles/install-apps.sh` (sudo): the apps and system parts below.
- `~/dotfiles/fresh-install.sh` (sudo): all of the above, plus the system and firmware update.

### Apps from other sources

These need sudo and extra setup, so `install.sh` doesn't install them. Run `install-apps.sh` instead. It uses sudo, asks before each app, and skips any already installed:

```bash
~/dotfiles/install-apps.sh            # asks before each app
~/dotfiles/install-apps.sh --all      # installs all of them
DRY_RUN=1 ~/dotfiles/install-apps.sh  # only checks the downloads, installs nothing
```

Each app comes from its maker's official source, which then keeps it updated with `sudo apt upgrade`. The Claude Desktop and ONLYOFFICE signing keys' fingerprints and Proton's setup package checksum are checked before installing. If ONLYOFFICE is installed without its update source (for example from a downloaded `.deb`), the script offers to add the source so it gets updates.

It first checks the computer's clock against the internet. If it's more than 5 minutes off (common in a VM resumed from a saved state), installs would fail with "Release file … is not valid yet", so it offers to fix the clock before going on: with `sudo chronyc makestep` on Ubuntu 25.10 and later (which use chrony), or by restarting `systemd-timesyncd` on older versions. If that doesn't work, it sets the clock from the internet time. If another software update is already running (Ubuntu often starts one right after the clock is fixed), it waits for it to finish instead of failing. If a maker changes its download link, update the script; the table shows the manual way:

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

The script also offers to **remove Ubuntu's Snap Firefox**, because this setup uses the Flatpak Firefox (in `setup/flatpaks.txt`). It removes both the Snap and Ubuntu's `firefox` package, which only exists to install the Snap and would bring it back on an update. It only does this if the Flatpak Firefox is installed. By hand: `sudo snap remove firefox && sudo apt remove firefox`.

**Steam's files aren't in this repo on purpose.** `~/.steam` holds your Steam sign-in, games and Steam's own program files. On a new computer, install Steam, sign in, and reinstall games; Steam Cloud brings back saves for games that support it.

### Obsidian

Your **notes** aren't in this repo. They're in their own private repo, `obsidian-vault`, at `~/Documents/Obsidian Vault`. To save changes to your notes:

```bash
cd ~/Documents/"Obsidian Vault" && git add -A && git commit -m "Update notes" && git push
```

`install.sh` clones that repo to `~/Documents/Obsidian Vault` if it isn't there. It also adds your Obsidian settings (Catppuccin theme, hidden ribbon, core plugins) from `setup/apps/obsidian/` if the vault has none yet. It also adds the vault to Obsidian's list, so Obsidian opens straight into it. Obsidian needs to be installed and closed for that; otherwise choose **Open folder as vault** once.

### GNOME extensions

`install.sh` installs and enables the extensions in `setup/gnome-extensions.txt` (Alphabetical App Grid, Caffeine, Clipboard Indicator) and restores their settings. It also applies exactly which extensions are on or off, including Ubuntu's built-in ones: Ubuntu Dock, desktop icons and web search are switched off, as on the original computer. They start after you log out and back in. To add another extension to the list, put its ID (shown on its extensions.gnome.org page or by `gnome-extensions list`) in that file.

### Weekly updates, monthly clean-up and NVIDIA driver

`install-apps.sh` also offers these:

- **Weekly automatic updates:** installs `system/etc/cron.weekly/system-update` with this computer's username filled in. It updates Ubuntu packages and Flatpak apps once a week and shows a notification if an update fails, gets stuck, or needs a restart. The log is `/var/log/system-update.log`.
- **Monthly clean-up:** installs `system/etc/cron.monthly/system-cleanup`, which once a month removes packages nothing needs any more (`apt autoremove`: old kernels, leftover dependencies) and unused Flatpak runtimes (`flatpak uninstall --unused`). It shows a notification if it fails. The log is `/var/log/system-cleanup.log`.
- **NVIDIA graphics driver:** only on computers with an NVIDIA card. It runs Ubuntu's `sudo ubuntu-drivers install`, which picks the right driver for the card and works with Secure Boot. Restart afterwards.
- **Steam on the NVIDIA card:** installs the 32-bit NVIDIA library that matches the driver (many games need it), and a copy of Steam's shortcut that asks for the NVIDIA card, so games run on it. Quit Steam fully first if it's open.
- **Codecs** (`ubuntu-restricted-extras`, in the Ubuntu apps list) shows a font licence screen: press <kbd>Tab</kbd> to `<Ok>` and <kbd>Enter</kbd>, then choose `<Yes>`.

By hand:

```bash
sed "s/^DESKTOP_USER=.*/DESKTOP_USER=$(id -un)/" ~/dotfiles/system/etc/cron.weekly/system-update > /tmp/system-update
sudo install -m 755 /tmp/system-update /etc/cron.weekly/system-update
sudo ubuntu-drivers install
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
