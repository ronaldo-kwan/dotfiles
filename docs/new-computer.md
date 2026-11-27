[README](../README.md) · **New computer** · [Apps](apps.md) · [Brave on your phone](brave-phone.md) · [Maintenance](maintenance.md) · [Files](files.md)

# Setting up a new computer

From a blank laptop to the full setup: prepare the laptop, install Ubuntu, run one command, then sign in to a few things.

**Contents**

- [First: check the dotfiles still work](#first-check-the-dotfiles-still-work)
- [Before installing Ubuntu](#before-installing-ubuntu)
- [One command](#one-command)
- [After the restart](#after-the-restart)
- [One password at start-up](#one-password-at-start-up)
- [Using the RTX 5060](#using-the-rtx-5060)
- [Running the parts separately](#running-the-parts-separately)
- [Undoing it](#undoing-it)
- [Manual setup](#manual-setup)

## First: check the dotfiles still work

A day or so before, from your current computer, run the GitHub checks:

```bash
gh workflow run check.yml --repo ronaldo-kwan/dotfiles
```

(Or **Actions → check → Run workflow** on GitHub, which works from a phone too.) Within a few minutes it has installed everything in a clean Ubuntu 26.04 and tried every app's download and signing key. If something fails, such as a maker that moved a download or changed its key, fix it now and push, rather than halfway through the new computer's setup. See [GitHub checks](maintenance.md#github-checks) for what it covers.

To try the whole setup the way the new computer will get it (a fresh Ubuntu, the website's command, the restart, then `dot check`), run `dot vm` here too: it does it in a GNOME Boxes virtual machine, in about an hour the first time. See [A test in a virtual machine](maintenance.md#a-test-in-a-virtual-machine).

They also run by themselves every Monday, but a maker can change something any day, so run them now. If the run warns that an action or a pinned download is old, or fails because of one, see [updating the actions](maintenance.md#pinned-downloads).

## Before installing Ubuntu

These steps are for my Lenovo Legion 5 with an RTX 5060; most apply to any laptop with an NVIDIA card.

1. **Set the GPU mode to Hybrid.** In Windows, open Lenovo Legion Space (or Vantage) and set the GPU mode to **Hybrid**. Without Windows, restart, press <kbd>F2</kbd> for the BIOS, and set **GPU Working Mode** to Hybrid. "Hybrid-iGPU only" hides the RTX 5060 from Ubuntu.
2. **Leave Secure Boot on.** Ubuntu's NVIDIA driver works with it.
3. **Boot the Ubuntu 26.04 USB stick** (<kbd>F12</kbd> at startup). In the installer, tick **Install third-party software for graphics and Wi-Fi hardware**.
4. **Encrypt the disk.** Recommended if the laptop leaves home, and only possible during the install: **Erase disk and install Ubuntu → Advanced features → Use LVM and encryption** (the wording may vary). Choose a passphrase, not TPM, which has problems with NVIDIA.
   - It protects your files, notes, browser sessions and sign-in tokens if the laptop is lost or stolen. The login password alone doesn't.
   - The passphrase is asked once per start-up, before Ubuntu loads; not at login, unlock or wake. To type only one password at start-up, see [One password at start-up](#one-password-at-start-up).

> [!IMPORTANT]
> Save the disk passphrase and the installer's recovery key in your password manager. Without them the disk can't be read, and only Backups can bring your files back.

## One command

After Ubuntu is installed, open a terminal (<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd>) and run:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/bootstrap.sh)
```

1. `bootstrap.sh` first checks the system, then installs git, gum and gh, downloads the dotfiles to `~/code/github/dotfiles` and starts `fresh-install.sh`. The repo is public, so no GitHub sign-in is needed.
   - On another Ubuntu version, an Ubuntu-based system (Mint, Pop!_OS) or a desktop other than GNOME, it says why and asks before changing anything (<kbd>Enter</kbd> = no). To try it there without the question, put `DOTFILES_ANY_SYSTEM=1` in front of the command. On anything else it stops.
2. The first time, it asks your **name and email for git commits**. <kbd>Enter</kbd> keeps the suggestion from `setup/git-identity`. They're saved in `~/.config/git/user.gitconfig`, on this computer only.
3. It asks **how questions should be answered**. Press <kbd>Enter</kbd> on **Yes to everything**, type your password once, and walk away.

A command from [the website](https://ronaldo-kwan.github.io/dotfiles/) ends with `--yes`: what you picked there is the answer, so it skips this question (and the name question too, if you filled it in).

<details>
<summary>Without the one-line command</summary>

```bash
sudo apt install git gum
git clone https://github.com/ronaldo-kwan/dotfiles ~/code/github/dotfiles
~/code/github/dotfiles/bin/fresh-install.sh
```

`gum` draws the menus. If it's missing, `fresh-install.sh` installs it first, asking for your password before the first question.

</details>

### Yes to everything, or Let me choose

- **Yes to everything** installs every app, updates the firmware if the charger is plugged in, accepts the Microsoft fonts licence the codecs need, and restarts at the end after a 15-second countdown (<kbd>Ctrl</kbd> + <kbd>C</kbd> to stay). If another software update is running then (often the weekly updates, which first run about 10 minutes after a new computer starts), it waits for that to finish, since Ubuntu refuses to restart in the middle of one. The scripts it runs get the same answer and don't ask again.
- **Let me choose** gives Yes/No buttons for each step, and one checklist of the apps: everything pre-ticked, <kbd>Space</kbd> unticks, <kbd>Enter</kbd> starts.
- To skip even this question, run `~/code/github/dotfiles/bin/fresh-install.sh --yes`.

### What it does

`fresh-install.sh` runs these steps in order:

| Step | What happens |
|---|---|
| 1. Update the system | `apt full-upgrade` |
| 2. Update firmware | BIOS, SSD and devices with `fwupdmgr`, only if the charger is plugged in |
| 3. Terminal tools | Starship, eza, bat, fzf, zoxide, ble.sh, Ghostty, btop, lazygit and more, plus what checks the dotfiles' own scripts before a push (shellcheck, pyflakes, Node.js); adds Flathub and starts the Flatpak apps installing in the background, so they download while the next steps run |
| 4. `install.sh` | Configs, fonts, GNOME extensions (including the frosted glass), desktop and app settings (on the same laptop, its display scale too), the lock screen, the secret check, the weekly reminder |
| 5. `install-apps.sh` | Chrome, Brave Origin, VS Code, Claude Desktop, Claude Code, ChatGPT, Proton VPN, OBS, ONLYOFFICE, Steam, Ubuntu apps, the NVIDIA driver, weekly updates, monthly clean-up, the login screen's look, the firewall, and no Snap Firefox ([details](apps.md)). Each app's update source is added and checked first; then all their packages install in one go, which is minutes faster than one app at a time |
| 6. `install.sh` again | VS Code's extensions and Obsidian, now that those apps exist; waits for the Flatpak apps and installs any that didn't make it |

### What you see

- **A live list of steps** stays pinned at the top of the terminal: ✔ done, ↷ skipped, ✘ failed, and a spinner and timer on the running one (including the current part of a nested script). The details scroll underneath, numbered like `[3/6]`.
- **Long installs show a spinner** instead of pages of apt output. The full output is saved in `~/.cache/dotfiles/`, and if something fails its last lines are shown right there.
- **A summary table** at the end lists every step.
- **Your desktop look changes once, at the end.** The theme, fonts, extensions, dock and wallpaper stay Ubuntu's while it works, and switch to yours right before the restart. If you press <kbd>Ctrl</kbd> + <kbd>C</kbd> to skip the restart, log out and back in instead. `dot install` on its own applies the look straight away.

> [!TIP]
> If a step fails, the rest still run. Fix the cause and run it again; finished parts are skipped.

## After the restart

> [!IMPORTANT]
> **NVIDIA with Secure Boot:** if the setup asked you to make up a short password, a blue **MOK management** screen appears after the restart. Choose **Enroll MOK → Continue → Yes**, type that password, then **Reboot**. Afterwards `nvidia-smi` should list the RTX 5060.

Then:

- [ ] Sign in to GitHub with `gh auth login` (for your private notes, `dot push` and signed commits), then run `dot install` again to fetch your notes.
- [ ] Sign in to your apps: Steam, browsers, Discord.
- [ ] Open **Backups**, connect Google Drive, and turn on **Back Up Automatically**. Keep the backup encryption password somewhere safe; without it the backups can't be restored.
- [ ] Run `dot ssh` for signed commits (one approval in the browser).
- [ ] Run `dot check` to see that everything is in place. It offers to fix anything that isn't.
- [ ] Check the display scaling (**Settings → Displays → Scale**). On a computer with the same screen as when you last ran `dot push`, it's already set (from `setup/apps/monitors.xml`); on another screen, set it yourself if text looks too small or large. Whole-number scales (100%, 200%) avoid a thin seam under the top bar that fractional ones can leave.

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
| `~/code/github/dotfiles/bin/install.sh` (`dot install`) | No | Links the config files (keeping existing ones as `.orig`; later, saved app settings it replaces go to `.prev`, so the `.orig` from before the dotfiles is never overwritten), installs the Roboto Mono fonts, VS Code extensions, Flatpak apps and GNOME extensions for this GNOME version, and restores the desktop look, shortcuts, settings, dock, wallpaper, app settings and the Obsidian vault. Switches on the secret check and the weekly reminder. Extensions start after you log out and back in. `DRY_RUN=1 dot install --yes` only shows what it would change |
| `~/code/github/dotfiles/bin/install-apps.sh` (`dot apps`) | Yes | Apps and system parts; see [Apps](apps.md) |
| `~/code/github/dotfiles/bin/fresh-install.sh` (`dot fresh`) | Yes | All of the above, plus the system and firmware update. `DRY_RUN=1 dot fresh --yes` only shows what it would do |
| `~/code/github/dotfiles/bin/check.sh` (`dot check`) | No | Shows what's missing. Changes nothing |
| `~/code/github/dotfiles/bin/uninstall.sh` (`dot uninstall`) | No | Undoes `install.sh`; see [Undoing it](#undoing-it) |

## Undoing it

To go back to Ubuntu's own setup, for example after trying these dotfiles:

```bash
dot uninstall          # your settings only; asks first (--yes doesn't)
dot uninstall --apps   # the apps and system parts too (a checklist; needs your password)
```

On its own, it changes only your user's files and settings, no sudo:

- **Config links are removed.** Files you had before (kept as `<name>.orig`) come back; without one, `~/.bashrc` becomes Ubuntu's default. Your git name and email move into a plain `~/.gitconfig`, so commits keep working.
- **The desktop goes back to Ubuntu's defaults:** theme, fonts, shortcuts, dock, wallpaper, Files and other settings `install.sh` loaded. Backups' settings stay, so automatic backups keep running.
- **What it added is removed:** the GNOME extensions it downloaded (not ones you had before), the Roboto Mono fonts, the wallpaper, and its copies of font settings in Flatpak apps and of login apps.
- **The weekly reminder and the secret check are switched off,** and the website's saved choices are deleted.

Then log out and back in.

### Removing the apps too (`--apps`)

Apps stay unless you ask, because removing them needs sudo. With `--apps` it shows a checklist of what it found, all ticked: <kbd>Space</kbd> unticks what you want to keep, <kbd>Enter</kbd> removes the rest after one password.

Only what the dotfiles added is on the list. The install scripts write down each app, package, Flatpak and GNOME extension they install that wasn't there before, and whether they switched the firewall on or removed the Snap Firefox. The list is kept in `~/.local/state/dotfiles/added`. Anything you had before the dotfiles isn't on it and stays. A computer set up before this list existed is marked `legacy`: nobody knows what was there before, so everything that matches is offered, as it used to be. After `--apps`, the list is emptied: whatever you kept is now yours.

| On the list | What removing it does |
|---|---|
| Apps from their makers (Chrome, Brave Origin, VS Code, Claude, ChatGPT, Proton VPN, OBS, ONLYOFFICE, Steam) | Removes the app and its update source and key |
| Ubuntu apps from `setup/apt-packages.txt`, terminal tools | Removes them, except ones Ubuntu's own desktop includes (like Backups) and general tools (git, curl, gum, gh) |
| Flatpak apps from `setup/flatpaks.txt` | Removes each, then runtimes nothing uses |
| Weekly updates and monthly clean-up, the firewall | Deletes the jobs; switches the firewall off |
| The login screen's look | Removes its settings, background and profile, so the login screen is Ubuntu's again |
| Ubuntu's Snap Firefox | Puts it back |

Apps' own settings and data (your Steam games, browser profiles) stay in your home folder, so reinstalling one brings it back as it was. The NVIDIA driver always stays: removing it can leave you without a screen. To see everything it would do without changing anything: `DRY_RUN=1 dot uninstall --apps --yes`. `~/code/github/dotfiles` itself stays; delete it with `rm -rf ~/code/github/dotfiles`.

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
  mkdir -p ~/.var/app/$a/config/fontconfig && cp ~/code/github/dotfiles/fontconfig/.config/fontconfig/fonts.conf ~/.var/app/$a/config/fontconfig/
done
```

### Config files

Stow won't replace files that already exist, so move them aside first:

```bash
mv ~/.bashrc ~/.bashrc.orig
mv ~/.gitconfig ~/.gitconfig.orig 2>/dev/null
stow --dir ~/code/github/dotfiles/home --target ~ --no-folding \
  bash git starship ghostty btop lazygit bat eza fzf fastfetch terminal-default vscode claude systemd fontconfig
```

### VS Code extensions and Flatpak apps

```bash
xargs -n1 code --install-extension < ~/code/github/dotfiles/setup/vscode-extensions.txt
xargs flatpak install -y flathub < ~/code/github/dotfiles/setup/flatpaks.txt
```

### Desktop look, shortcuts, extension settings and dock

The shortcuts replace any custom shortcuts already on the computer.

```bash
dconf load /org/gnome/ < ~/code/github/dotfiles/setup/gnome-desktop.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < ~/code/github/dotfiles/setup/gnome-shortcuts.dconf
dconf load /org/gnome/shell/extensions/ < ~/code/github/dotfiles/setup/gnome-extension-settings.dconf
dconf load / < ~/code/github/dotfiles/setup/desktop-settings.dconf
gsettings set org.gnome.shell favorite-apps "$(cat ~/code/github/dotfiles/setup/dock-favorites.txt)"
```

### Wallpaper

```bash
mkdir -p ~/Pictures/Wallpapers/current
cp ~/code/github/dotfiles/setup/wallpaper/catppuccin-tropic-island-night-16x9.jpg ~/Pictures/Wallpapers/current/
W="file://$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night-16x9.jpg"
gsettings set org.gnome.desktop.background picture-uri "$W"
gsettings set org.gnome.desktop.background picture-uri-dark "$W"
```

### Login screen

The login screen's look is system-wide and needs sudo, so it's simplest with `dot apps`: choose **Let me choose** and tick only **the login screen**. What it does is described in [Apps](apps.md#what-else-it-sets-up).

### Secret check and weekly reminder

```bash
git -C ~/code/github/dotfiles config core.hooksPath ~/code/github/dotfiles/.githooks
git -C ~/Documents/"Obsidian Vault" config core.hooksPath ~/code/github/dotfiles/.githooks
systemctl --user enable --now dotfiles-reminder.timer
```

</details>
