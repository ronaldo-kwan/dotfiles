[README](../README.md) · [New computer](new-computer.md) · **Apps** · [Maintenance](maintenance.md) · [Files](files.md)

# Apps

Which apps the setup installs, where each comes from, and the system parts that come with them.

**Contents**

- [Installing the apps](#installing-the-apps)
- [Where each app comes from](#where-each-app-comes-from)
- [What else it sets up](#what-else-it-sets-up)
- [Steam](#steam)
- [Obsidian](#obsidian)
- [GNOME extensions](#gnome-extensions)

## Installing the apps

`install-apps.sh` (or `dot apps`) installs the apps that need sudo and extra setup, so `install.sh` leaves them out. It skips anything already installed.

```bash
~/dotfiles/install-apps.sh            # one question: Yes to everything, or a checklist
~/dotfiles/install-apps.sh --yes      # Yes to everything without asking (--all and -y work too)
DRY_RUN=1 ~/dotfiles/install-apps.sh  # only checks the downloads, installs nothing
```

It first asks whether to answer Yes to everything. Choose **Let me choose** to get one checklist of the apps not yet installed: all pre-ticked, <kbd>Space</kbd> unticks, <kbd>Enter</kbd> starts. The codecs' font licence is a checkbox in it. Without gum, it asks Y/n for each app instead.

> [!NOTE]
> **If the computer's clock is wrong** by more than 5 minutes (common in a VM resumed from a saved state), installs would fail with "Release file … is not valid yet". The script checks the clock against the internet first and offers to fix it. If another software update is already running, it waits for it instead of failing.

## Where each app comes from

Each app comes from its maker's official source, so `sudo apt upgrade` keeps it updated. The Claude Desktop, Claude Code and ONLYOFFICE signing keys' fingerprints and Proton's setup-package checksum are checked before installing. If ONLYOFFICE is installed without its update source (for example from a downloaded `.deb`), the script offers to add the source.

If a maker changes its download link, update the script; the table shows the manual way.

| App | Where to get it | Package |
|---|---|---|
| Google Chrome | google.com/chrome (`.deb`) | `google-chrome-stable` |
| VS Code | code.visualstudio.com (`.deb`) | `code` |
| Claude Desktop | claude.ai/download | `claude-desktop` |
| Claude Code | Anthropic's apt source, `downloads.claude.ai/claude-code/apt/stable` (key from `downloads.claude.ai/keys/claude-code.asc`) | `claude-code` |
| Proton VPN | protonvpn.com/download (Linux, Ubuntu) | `proton-vpn-gnome-desktop` |
| OBS Studio | `sudo add-apt-repository ppa:obsproject/obs-studio` | `obs-studio` |
| ONLYOFFICE | ONLYOFFICE's update source (key from download.onlyoffice.com/GPG-KEY-ONLYOFFICE) | `onlyoffice-desktopeditors` |
| Steam | Ubuntu's own package; needs 32-bit support: `sudo dpkg --add-architecture i386` | `steam-installer` |
| Ubuntu apps | `sudo apt install` the packages in [`setup/apt-packages.txt`](../setup/apt-packages.txt) | see the file |

## What else it sets up

| Part | What it does |
|---|---|
| **NVIDIA graphics driver** | Only on computers with an NVIDIA card. Runs Ubuntu's `sudo ubuntu-drivers install`, which picks the right driver for the card and works with Secure Boot. Restart afterwards |
| **Steam on the NVIDIA card** | Installs the 32-bit NVIDIA library that matches the driver (many games need it), and a copy of Steam's shortcut that asks for the NVIDIA card. Quit Steam fully first if it's open |
| **Codecs** | `ubuntu-restricted-extras` (in the Ubuntu apps list) includes Microsoft's fonts, whose licence normally stops the install with a full-screen prompt. The script asks about it as a normal question instead (Yes to everything accepts it) |
| **Firewall** | Turns on Ubuntu's firewall (`ufw`) so other devices can't connect in. Everything you start yourself (browsing, Steam, updates) works as before, and qBittorrent's listening port stays open |
| **Snap Firefox removal** | Removes the Snap Firefox and Ubuntu's `firefox` package (which would bring the Snap back), because this setup uses the Flathub Firefox. Only if the Flathub Firefox is installed |
| **Weekly updates and monthly clean-up** | See [Keeping things up to date](maintenance.md#weekly-updates-and-monthly-clean-up) |

Handy commands:

```bash
sudo ufw status verbose                        # firewall rules
sudo ufw allow <port>                          # open another port
sudo ufw disable                               # firewall off
sudo snap remove firefox && sudo apt remove firefox   # Snap Firefox removal, by hand
```

## Steam

> [!NOTE]
> Steam's files aren't in this repo on purpose. `~/.steam` holds your Steam sign-in, games and Steam's own program files.

On a new computer, install Steam, sign in, and reinstall your games. Steam Cloud brings back saves for games that support it.

## Obsidian

Your **notes** aren't in this repo. They're in their own private repo, `obsidian-vault`, at `~/Documents/Obsidian Vault`. To save changes to your notes:

```bash
dot notes "Describe the change"
```

What `install.sh` does for Obsidian:

- Clones the `obsidian-vault` repo to `~/Documents/Obsidian Vault` if it isn't there. This needs `gh auth login` first.
- Adds your Obsidian settings (Catppuccin theme, hidden ribbon, core plugins) from `setup/apps/obsidian/` if the vault has none yet.
- Adds the vault to Obsidian's list, so Obsidian opens straight into it. Obsidian must be installed and closed for that; otherwise choose **Open folder as vault** once.

The [secret check](maintenance.md#secret-check-before-commits) also guards commits in the notes repo.

## GNOME extensions

`install.sh` installs and enables the extensions in [`setup/gnome-extensions.txt`](../setup/gnome-extensions.txt) (Alphabetical App Grid, Caffeine, Clipboard Indicator) and restores their settings. It also sets exactly which extensions are on or off, including Ubuntu's built-in ones: Ubuntu Dock, desktop icons and web search are off. They start after you log out and back in.

To add another extension, put its ID in that file. The ID is shown on its extensions.gnome.org page, or by `gnome-extensions list`.
