# Apps

## Apps from other sources (`install-apps.sh`)

These need sudo and extra setup, so `install.sh` doesn't install them. `install-apps.sh` uses sudo, asks before each app, and skips any already installed:

```bash
~/dotfiles/install-apps.sh            # asks before each app
~/dotfiles/install-apps.sh --all      # installs all of them
DRY_RUN=1 ~/dotfiles/install-apps.sh  # only checks the downloads, installs nothing
```

Each app comes from its maker's official source, which then keeps it updated with `sudo apt upgrade`. The Claude Desktop and ONLYOFFICE signing keys' fingerprints and Proton's setup package checksum are checked before installing. If ONLYOFFICE is installed without its update source (for example from a downloaded `.deb`), the script offers to add the source so it gets updates.

It first checks the computer's clock against the internet. If it's more than 5 minutes off (common in a VM resumed from a saved state), installs would fail with "Release file … is not valid yet", so it offers to fix the clock first: with `sudo chronyc makestep` on Ubuntu 25.10 and later (which use chrony), or by restarting `systemd-timesyncd` on older versions, or by setting the clock from the internet time. If another software update is already running, it waits for it instead of failing.

If a maker changes its download link, update the script; the table shows the manual way:

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

It also sets up the [weekly updates and monthly clean-up](maintenance.md#weekly-updates-and-monthly-clean-up), and:

- **NVIDIA graphics driver:** only on computers with an NVIDIA card. It runs Ubuntu's `sudo ubuntu-drivers install`, which picks the right driver for the card and works with Secure Boot. Restart afterwards.
- **Steam on the NVIDIA card:** installs the 32-bit NVIDIA library that matches the driver (many games need it), and a copy of Steam's shortcut that asks for the NVIDIA card, so games run on it. Quit Steam fully first if it's open.
- **Codecs** (`ubuntu-restricted-extras`, in the Ubuntu apps list) shows a font licence screen: press <kbd>Tab</kbd> to `<Ok>` and <kbd>Enter</kbd>, then choose `<Yes>`.
- **Removes Ubuntu's Snap Firefox**, because this setup uses the Flatpak Firefox (in `setup/flatpaks.txt`). It removes both the Snap and Ubuntu's `firefox` package, which only exists to install the Snap and would bring it back on an update. It only does this if the Flatpak Firefox is installed. By hand: `sudo snap remove firefox && sudo apt remove firefox`.

## Steam

**Steam's files aren't in this repo on purpose.** `~/.steam` holds your Steam sign-in, games and Steam's own program files. On a new computer, install Steam, sign in, and reinstall games; Steam Cloud brings back saves for games that support it.

## Obsidian

Your **notes** aren't in this repo. They're in their own private repo, `obsidian-vault`, at `~/Documents/Obsidian Vault`. To save changes to your notes:

```bash
cd ~/Documents/"Obsidian Vault" && git add -A && git commit -m "Update notes" && git push
```

`install.sh` clones that repo to `~/Documents/Obsidian Vault` if it isn't there (it needs `gh auth login` first). It adds your Obsidian settings (Catppuccin theme, hidden ribbon, core plugins) from `setup/apps/obsidian/` if the vault has none yet, and adds the vault to Obsidian's list, so Obsidian opens straight into it. Obsidian needs to be installed and closed for that; otherwise choose **Open folder as vault** once. The [secret check](maintenance.md#secret-check-before-commits) also guards commits in the notes repo.

## GNOME extensions

`install.sh` installs and enables the extensions in `setup/gnome-extensions.txt` (Alphabetical App Grid, Caffeine, Clipboard Indicator) and restores their settings. It also applies exactly which extensions are on or off, including Ubuntu's built-in ones: Ubuntu Dock, desktop icons and web search are switched off, as on the original computer. They start after you log out and back in. To add another extension, put its ID (shown on its extensions.gnome.org page or by `gnome-extensions list`) in that file.
