# Setting up a new computer

## Before installing Ubuntu (Lenovo Legion 5)

1. **GPU mode: Hybrid.** In Windows, open Lenovo Legion Space (or Vantage) and set the GPU mode to **Hybrid**. Without Windows: restart, press <kbd>F2</kbd> for the BIOS, and set **GPU Working Mode** to Hybrid. "Hybrid-iGPU only" hides the RTX 5060 from Ubuntu.
2. **Leave Secure Boot on.** Ubuntu's NVIDIA driver works with it.
3. Boot the Ubuntu 26.04 USB stick (<kbd>F12</kbd> at startup) and, in the installer, tick **Install third-party software for graphics and Wi-Fi hardware**.

## Fresh install: one script

After Ubuntu is installed, open a terminal (<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd>) and run these. `gh auth login` signs you in to GitHub through the browser.

```bash
sudo apt install git gh
gh auth login
gh repo clone dotfiles ~/dotfiles
~/dotfiles/fresh-install.sh
```

`fresh-install.sh` does everything in the right order and ends with a restart:

1. **Updates the system** (`apt full-upgrade`).
2. **Updates firmware** (BIOS, SSD, devices) with `fwupdmgr`, only if the charger is plugged in.
3. **Installs the terminal tools** (Starship, eza, bat, fzf, zoxide, ble.sh, Ghostty, btop, lazygit, ...) and adds Flathub.
4. Runs **`install.sh`**: configs, fonts, Flatpak apps, GNOME extensions, desktop and app settings, the secret check and the weekly reminder.
5. Runs **`install-apps.sh`**: Chrome, VS Code, Claude Desktop, Proton VPN, OBS, ONLYOFFICE, Steam, Ubuntu apps, the NVIDIA driver, weekly updates, monthly clean-up.
6. Runs **`install.sh` again**, for VS Code's extensions and Obsidian now that those apps exist.

**One question at the start:** "Answer Yes to every question, so the rest runs by itself?" Press <kbd>Enter</kbd> (Yes), then type your password once; you can walk away. Yes to everything means: install every app, update firmware if the charger is in, accept the Microsoft fonts licence that the codecs need, and restart at the end (after a 15-second countdown; <kbd>Ctrl</kbd> + <kbd>C</kbd> stays). The scripts it runs get the same answer and don't ask again. Type <kbd>n</kbd> instead to be asked before each step and app (Enter still means Yes). To skip even the first question: `~/dotfiles/fresh-install.sh --yes`.

**What you see:** each step is numbered (`[3/6]`) and ends with ✔ done, ↷ skipped (with the reason) or ✘ failed. Long installs show a spinner and a timer instead of pages of apt output; the full output is saved in `~/.cache/dotfiles/` and, if something fails, its last lines are shown right there. A summary table at the end lists every step.

If a step fails, the rest still run. Fix the cause and run it again; finished parts are skipped.

**One screen may still need you:**
- **NVIDIA with Secure Boot:** if asked, make up a short password (letters and numbers). After the restart, a blue **MOK management** screen appears: Enroll MOK → Continue → Yes → type that password → Reboot. Then `nvidia-smi` should list the RTX 5060.

**After the restart:** sign in to your apps (Steam, browsers, Discord, Bitwarden). Open **Backups**, connect Google Drive, and turn on **Back Up Automatically**. Keep the backup encryption password somewhere safe; without it the backups can't be restored. Then run `dot ssh` (signed commits, one approval in the browser) and `dot check` to see that everything is in place (`dot check --fix` offers to fix anything that isn't).

Display scaling isn't saved, because it depends on the screen. Set it in **Settings → Displays → Scale** if text looks too small or large.

## Using the RTX 5060

Apps run on the AMD graphics built into the processor by default, which saves battery. Steam is the exception: the setup gives it a shortcut that asks for the NVIDIA card, so games started from Steam use the RTX 5060.

For any other app, right-click it in the app grid and choose **Launch using Discrete Graphics Card**. While it runs, `nvidia-smi` lists it under Processes.

## Running the parts separately

The scripts can also be run on their own, for example on a computer that's already set up. Each is safe to run again.

- `~/dotfiles/install.sh` (no sudo): links config files (keeping existing ones as `.orig`). It installs the Nerd Font, VS Code extensions, Flatpak apps and GNOME extensions (the versions matching this computer's GNOME). It restores your desktop look, shortcuts, settings, extension settings, dock, wallpaper, app settings and the Obsidian vault, and switches on the secret check and weekly reminder. GNOME extensions start after you log out and back in.
- `~/dotfiles/install-apps.sh` (sudo): apps and system parts, see [apps.md](apps.md).
- `~/dotfiles/fresh-install.sh` (sudo): all of the above, plus the system and firmware update.
- `~/dotfiles/check.sh` (or `dot check`): shows what's missing. Changes nothing.

## Manual setup (instead of install.sh)

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
stow --no-folding bash git starship ghostty btop lazygit terminal-default vscode claude systemd
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
dconf load / < ~/dotfiles/setup/desktop-settings.dconf
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

**Secret check and weekly reminder**

```bash
git -C ~/dotfiles config core.hooksPath ~/dotfiles/.githooks
git -C ~/Documents/"Obsidian Vault" config core.hooksPath ~/dotfiles/.githooks
systemctl --user enable --now dotfiles-reminder.timer
```

</details>
