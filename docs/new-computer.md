[README](../README.md) · **New computer** · [Apps](apps.md) · [Maintenance](maintenance.md) · [Files](files.md)

# Setting up a new computer

From a blank laptop to the full setup: prepare the laptop, install Ubuntu, run one command, then sign in to a few things.

**Contents**

- [Before installing Ubuntu](#before-installing-ubuntu)
- [Option 1: one command](#option-1-one-command)
- [Option 2: automated install](#option-2-automated-install)
- [After the restart](#after-the-restart)
- [One password at start-up](#one-password-at-start-up)
- [Using the RTX 5060](#using-the-rtx-5060)
- [Running the parts separately](#running-the-parts-separately)
- [Manual setup](#manual-setup)

## Before installing Ubuntu

These steps are for my Lenovo Legion 5 with an RTX 5060; most apply to any laptop with an NVIDIA card.

1. **Set the GPU mode to Hybrid.** In Windows, open Lenovo Legion Space (or Vantage) and set the GPU mode to **Hybrid**. Without Windows, restart, press <kbd>F2</kbd> for the BIOS, and set **GPU Working Mode** to Hybrid. "Hybrid-iGPU only" hides the RTX 5060 from Ubuntu.
2. **Leave Secure Boot on.** Ubuntu's NVIDIA driver works with it.
3. **Boot the Ubuntu 26.04 USB stick** (<kbd>F12</kbd> at startup). In the installer, tick **Install third-party software for graphics and Wi-Fi hardware**.
4. **Encrypt the disk.** Recommended if the laptop leaves home, and only possible during the install: **Erase disk and install Ubuntu → Advanced features → Use LVM and encryption** (the wording may vary). Choose a passphrase, not TPM, which has problems with NVIDIA.
   - It protects your files, notes, browser sessions and sign-in tokens if the laptop is lost or stolen. The login password alone doesn't.
   - The passphrase is asked once per start-up, before Ubuntu loads; not at login, unlock or wake. To type only one password at start-up, see [One password at start-up](#one-password-at-start-up).

> [!IMPORTANT]
> Save the disk passphrase and the installer's recovery key in Bitwarden. Without them the disk can't be read, and only Backups can bring your files back.

## Option 1: one command

After Ubuntu is installed, open a terminal (<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd>) and run:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/bootstrap.sh)
```

1. `bootstrap.sh` installs git, gum and gh, downloads the dotfiles to `~/dotfiles` and starts `fresh-install.sh`. The repo is public, so no GitHub sign-in is needed.
2. The first time, it asks your **name and email for git commits**. <kbd>Enter</kbd> keeps the suggestion from `setup/git-identity`. They're saved in `~/.config/git/user.gitconfig`, on this computer only.
3. It asks **how questions should be answered**. Press <kbd>Enter</kbd> on **Yes to everything**, type your password once, and walk away.

<details>
<summary>Without the one-line command</summary>

```bash
sudo apt install git gum
git clone https://github.com/ronaldo-kwan/dotfiles ~/dotfiles
~/dotfiles/fresh-install.sh
```

`gum` draws the menus. If it's missing, `fresh-install.sh` installs it first, asking for your password before the first question.

</details>

### Yes to everything, or Let me choose

- **Yes to everything** installs every app, updates the firmware if the charger is plugged in, accepts the Microsoft fonts licence the codecs need, and restarts at the end after a 15-second countdown (<kbd>Ctrl</kbd> + <kbd>C</kbd> to stay). The scripts it runs get the same answer and don't ask again.
- **Let me choose** gives Yes/No buttons for each step, and one checklist of the apps: everything pre-ticked, <kbd>Space</kbd> unticks, <kbd>Enter</kbd> starts.
- To skip even this question, run `~/dotfiles/fresh-install.sh --yes`.

### What it does

`fresh-install.sh` runs these steps in order:

| Step | What happens |
|---|---|
| 1. Update the system | `apt full-upgrade` |
| 2. Update firmware | BIOS, SSD and devices with `fwupdmgr`, only if the charger is plugged in |
| 3. Terminal tools | Starship, eza, bat, fzf, zoxide, ble.sh, Ghostty, btop, lazygit and more; adds Flathub |
| 4. `install.sh` | Configs, fonts, Flatpak apps, GNOME extensions, desktop and app settings, the secret check, the weekly reminder |
| 5. `install-apps.sh` | Chrome, VS Code, Claude Desktop, Claude Code, Proton VPN, OBS, ONLYOFFICE, Steam, Ubuntu apps, the NVIDIA driver, weekly updates, monthly clean-up ([details](apps.md)) |
| 6. `install.sh` again | VS Code's extensions and Obsidian, now that those apps exist |

### What you see

- **A live list of steps** stays pinned at the top of the terminal: ✔ done, ↷ skipped, ✘ failed, and a spinner and timer on the running one (including the current part of a nested script). The details scroll underneath, numbered like `[3/6]`.
- **Long installs show a spinner** instead of pages of apt output. The full output is saved in `~/.cache/dotfiles/`, and if something fails its last lines are shown right there.
- **A summary table** at the end lists every step.
- **Your desktop look changes once, at the end.** The theme, fonts, extensions, dock and wallpaper stay Ubuntu's while it works, and switch to yours right before the restart. If you press <kbd>Ctrl</kbd> + <kbd>C</kbd> to skip the restart, log out and back in instead. `dot install` on its own applies the look straight away.

> [!TIP]
> If a step fails, the rest still run. Fix the cause and run it again; finished parts are skipped.

## Option 2: automated install

Instead of installing Ubuntu and then running the command, the Ubuntu installer can do most of it from [`setup/autoinstall.yaml`](../setup/autoinstall.yaml):

1. Boot the Ubuntu USB stick. In the installer, choose the **automated installation** and paste:

   ```text
   https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/setup/autoinstall.yaml
   ```

2. The installer only asks for the **disk** (choose encryption here, see [step 4](#before-installing-ubuntu)) and your **name and password**. The file answers the rest: language, keyboard, timezone, third-party drivers, codecs and updates. git, gum and gh are installed with Ubuntu.
3. Restart and log in. A terminal opens by itself and runs the [one command](#option-1-one-command): your name and email for git, then "Yes to everything". It runs once only.

> [!NOTE]
> The file is public and holds no password or other secret. It sets the language to `en_US.UTF-8`, the keyboard to `us` and the timezone to `Australia/Sydney`; [the website](https://ronaldo-kwan.github.io/dotfiles/) makes a copy with your own. The installer's menus for automated installs vary between Ubuntu releases; if yours doesn't offer it, use [option 1](#option-1-one-command).

## After the restart

> [!IMPORTANT]
> **NVIDIA with Secure Boot:** if the setup asked you to make up a short password, a blue **MOK management** screen appears after the restart. Choose **Enroll MOK → Continue → Yes**, type that password, then **Reboot**. Afterwards `nvidia-smi` should list the RTX 5060.

Then:

- [ ] Sign in to GitHub with `gh auth login` (for your private notes, `dot push` and signed commits), then run `dot install` again to fetch your notes.
- [ ] Sign in to your apps: Steam, browsers, Discord, Bitwarden.
- [ ] Open **Backups**, connect Google Drive, and turn on **Back Up Automatically**. Keep the backup encryption password somewhere safe; without it the backups can't be restored.
- [ ] Run `dot ssh` for signed commits (one approval in the browser).
- [ ] Run `dot check` to see that everything is in place. `dot check --fix` offers to fix anything that isn't.
- [ ] Set the display scaling in **Settings → Displays → Scale** if text looks too small or large. It isn't saved, because it depends on the screen.

## One password at start-up

With an encrypted disk, start-up asks for the disk passphrase and then your login password. The passphrase already protects everything, so you can skip the second:

1. **Settings → System → Users → Unlock** (your password) → turn on **Automatic Login**.
2. Empty the login keyring's password, or it asks for it after every start-up. (The keyring holds Chrome, Wi-Fi and SSH-key passwords and normally unlocks at login.) Open **Passwords and Keys** (`sudo apt install seahorse` if it's missing), right-click **Login** → **Change Password**, type the current password and leave the new one empty. Ignore the "unencrypted" warning: the disk is encrypted.
3. Restart to check.

| When | Asks for |
|---|---|
| Start-up or restart | The disk passphrase only, then the desktop |
| Waking from sleep | Your password ("Lock Screen on Suspend" stays on) |
| <kbd>Super</kbd> + <kbd>L</kbd>, or 5 minutes idle | Your password |

`sudo` and Settings still ask for your password. Tip: use the same password for the disk and login.

> [!CAUTION]
> Only do this with an encrypted disk. Otherwise anyone who switches the laptop on gets your desktop and saved passwords. To undo it, turn Automatic Login off and set the Login keyring's password back to your login password.

## Using the RTX 5060

Apps run on the AMD graphics built into the processor by default, which saves battery. Steam is the exception: the setup gives it a shortcut that asks for the NVIDIA card, so games started from Steam use the RTX 5060.

For any other app, right-click it in the app grid and choose **Launch using Discrete Graphics Card**. While it runs, `nvidia-smi` lists it under Processes.

## Running the parts separately

Each script can also run on its own, for example on a computer that's already set up. All are safe to run again.

| Script | Needs sudo | What it does |
|---|---|---|
| `~/dotfiles/install.sh` (`dot install`) | No | Links the config files (keeping existing ones as `.orig`), installs the Roboto Mono fonts, VS Code extensions, Flatpak apps and GNOME extensions for this GNOME version, and restores the desktop look, shortcuts, settings, dock, wallpaper, app settings and the Obsidian vault. Switches on the secret check and the weekly reminder. Extensions start after you log out and back in |
| `~/dotfiles/install-apps.sh` (`dot apps`) | Yes | Apps and system parts; see [Apps](apps.md) |
| `~/dotfiles/fresh-install.sh` (`dot fresh`) | Yes | All of the above, plus the system and firmware update |
| `~/dotfiles/check.sh` (`dot check`) | No | Shows what's missing. Changes nothing |

## Manual setup

What `install.sh` does, as commands to run by hand.

<details>
<summary>Step-by-step commands</summary>

### Fonts

Roboto everywhere: Roboto from Ubuntu, Roboto Mono from Google Fonts, and the RobotoMono Nerd Font (Roboto Mono plus prompt icons) for the terminal and VS Code.

```bash
sudo apt install fonts-roboto
mkdir -p ~/.local/share/fonts/RobotoMono ~/.local/share/fonts/RobotoMonoNerdFont
cd ~/.local/share/fonts/RobotoMono
curl -fL -o 'RobotoMono[wght].ttf' 'https://raw.githubusercontent.com/google/fonts/main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf'
curl -fL -o 'RobotoMono-Italic[wght].ttf' 'https://raw.githubusercontent.com/google/fonts/main/ofl/robotomono/RobotoMono-Italic%5Bwght%5D.ttf'
cd /tmp && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/RobotoMono.tar.xz
mkdir -p /tmp/rmn && tar -xJf RobotoMono.tar.xz -C /tmp/rmn
cp /tmp/rmn/RobotoMonoNerdFont*.ttf ~/.local/share/fonts/RobotoMonoNerdFont/
fc-cache -f
```

After linking the config files below (including the `fontconfig` package), give each Flatpak app the same font settings:

```bash
for a in $(flatpak list --app --columns=application); do
  mkdir -p ~/.var/app/$a/config/fontconfig && cp ~/dotfiles/fontconfig/.config/fontconfig/fonts.conf ~/.var/app/$a/config/fontconfig/
done
```

### Config files

Stow won't replace files that already exist, so move them aside first:

```bash
mv ~/.bashrc ~/.bashrc.orig
mv ~/.gitconfig ~/.gitconfig.orig 2>/dev/null
cd ~/dotfiles
stow --no-folding bash git starship ghostty btop lazygit terminal-default vscode claude systemd fontconfig
```

### VS Code extensions and Flatpak apps

```bash
xargs -n1 code --install-extension < ~/dotfiles/setup/vscode-extensions.txt
xargs flatpak install -y flathub < ~/dotfiles/setup/flatpaks.txt
```

### Desktop look, shortcuts, extension settings and dock

The shortcuts replace any custom shortcuts already on the computer.

```bash
dconf load /org/gnome/ < ~/dotfiles/setup/gnome-desktop.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < ~/dotfiles/setup/gnome-shortcuts.dconf
dconf load /org/gnome/shell/extensions/ < ~/dotfiles/setup/gnome-extension-settings.dconf
dconf load / < ~/dotfiles/setup/desktop-settings.dconf
gsettings set org.gnome.shell favorite-apps "$(cat ~/dotfiles/setup/dock-favorites.txt)"
```

### Wallpaper

```bash
mkdir -p ~/Pictures/Wallpapers/current
curl -fLo ~/Pictures/Wallpapers/current/catppuccin-tropic-island-night.jpg \
  https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/tropic_island_night.jpg
W="file://$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night.jpg"
gsettings set org.gnome.desktop.background picture-uri "$W"
gsettings set org.gnome.desktop.background picture-uri-dark "$W"
```

### Secret check and weekly reminder

```bash
git -C ~/dotfiles config core.hooksPath ~/dotfiles/.githooks
git -C ~/Documents/"Obsidian Vault" config core.hooksPath ~/dotfiles/.githooks
systemctl --user enable --now dotfiles-reminder.timer
```

</details>
