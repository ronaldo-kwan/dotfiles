[README](../README.md) · [New computer](new-computer.md) · [Apps](apps.md) · [Maintenance](maintenance.md) · **Files**

# What's in this repo

A map of every file and folder, and what each one is for.

**Contents**

- [Overview](#overview)
- [Linked config files](#linked-config-files)
- [Scripts](#scripts)
- [Snapshots (`setup/`)](#snapshots-setup)
- [Automation and the website](#automation-and-the-website)

## Overview

```text
dotfiles/
├── bootstrap.sh, fresh-install.sh,   setup scripts
│   install.sh, install-apps.sh,
│   post-upgrade.sh
├── dot, check.sh, lib.sh             the dot command, the health check, shared helpers
├── bash/ git/ starship/ ghostty/ …   config files, linked into ~ by Stow
├── setup/                            snapshots: apps, extensions, desktop settings
├── scripts/                          snapshot, SSH and website helpers
├── system/                           weekly and monthly jobs, the first-login step
├── site/                             the installer website
├── docs/                             these pages (images/: the README screenshot)
├── .githooks/                        the secret check
└── .github/workflows/                GitHub checks and the website
```

## Linked config files

These folders are laid out for [GNU Stow](https://www.gnu.org/software/stow/). Each one is a "package" whose contents mirror your home folder, and the real files in `~` are links into this repo.

| Package | Links to | What it is |
|---|---|---|
| `bash` | `~/.bashrc` | Aliases (`update`, the `dot` command, ...), history, and loading for ble.sh, Starship, zoxide, fzf, eza and bat |
| `git` | `~/.gitconfig` | `main` as the default branch, `gh` for GitHub sign-in, and includes for your per-computer name and email (`~/.config/git/user.gitconfig`) and signing (`~/.config/git/signing.gitconfig`) |
| `starship` | `~/.config/starship.toml` | The Tokyo Night prompt (Starship's `tokyo-night` preset, with the Ubuntu logo) |
| `ghostty` | `~/.config/ghostty/config` | Catppuccin Mocha, Nerd Font, padding |
| `btop` | `~/.config/btop/` | Catppuccin Mocha theme and settings |
| `lazygit` | `~/.config/lazygit/config.yml` | Catppuccin Mocha and Nerd Font icons |
| `terminal-default` | `~/.config/xdg-terminals.list` | Makes Ghostty the default terminal |
| `vscode` | `~/.config/Code/User/settings.json` | Theme, fonts, ligatures |
| `claude` | `~/.claude/CLAUDE.md` | Personal instructions for Claude Code |
| `systemd` | `~/.config/systemd/user/dotfiles-reminder.*` | The [weekly reminder](maintenance.md#weekly-reminder) |
| `fontconfig` | `~/.config/fontconfig/fonts.conf` | Makes Roboto the sans-serif, serif and system-ui font and Roboto Mono the monospace font in every app |

> [!NOTE]
> Flatpak apps don't read `~/.config`, so `install.sh` also copies `fonts.conf` into each Flatpak app's own folder (`~/.var/app/<id>/config/fontconfig/`).

## Scripts

### Setting up

| File | What it is |
|---|---|
| `bootstrap.sh` | The one command for a fresh Ubuntu: installs git, gum and gh, downloads the repo, starts `fresh-install.sh` |
| `fresh-install.sh` | Sets up a freshly installed Ubuntu in one go: system and firmware update, tools, then the two scripts below |
| `install.sh` | Configs, fonts, Flatpak apps, extensions, settings, the secret check and the reminder (no sudo) |
| `install-apps.sh` | Apps from their makers' sources, the NVIDIA driver, Steam on the NVIDIA card, weekly updates, monthly clean-up, Snap Firefox removal (sudo) |
| `post-upgrade.sh` | After upgrading Ubuntu to a new release: switches app update sources back on and puts everything back |
| `uninstall.sh` | `dot uninstall`: undoes `install.sh` for your user (links, desktop settings, extensions, fonts, reminder, secret check); `--apps` also removes the apps and system parts you pick |

### Everyday

| File | What it is |
|---|---|
| `dot` | The `dot` command (`save`, `push`, `pull`, `check`, ...): a menu on its own, or `dot help`. `.bashrc` adds `dot cd` and <kbd>Tab</kbd> completion |
| `check.sh` | The health check (`dot check`); `--notify` is the weekly reminder |
| `scripts/ssh-setup.sh` | `dot ssh`: SSH key, signed commits, adding the key to GitHub |
| `scripts/snapshot.sh` | Writes the snapshots in `setup/` (used by `dot save`, and by `check.sh` into a temporary copy) |
| `scripts/dump-desktop-settings.sh` | Writes `setup/desktop-settings.dconf` |
| `scripts/save-app-settings.sh` | Writes `setup/apps/` |

### Shared

| File | What it is |
|---|---|
| `lib.sh` | Helpers shared by the scripts (questions, gum, the progress panel, steps, spinner, summary, clock check), plus the lists of terminal tools and stow packages |

## Snapshots (`setup/`)

Written by `dot save` and restored by `install.sh`, except `apt-packages.txt`, which you edit by hand and `install-apps.sh` installs.

| File | What it is |
|---|---|
| `git-identity` | Name and email suggested for git commits; saved per computer in `~/.config/git/user.gitconfig` |
| `vscode-extensions.txt` | VS Code extensions (the Catppuccin theme) |
| `apt-packages.txt` | Ubuntu packages I installed myself: VLC, qBittorrent, Tweaks, Extension Manager, Backups and rclone (for Google Drive), Software with Flathub, GNOME wallpapers and sounds, codecs, vainfo, the Roboto font. `-name` lines are installed here on purpose but not wanted on new computers |
| `flatpaks.txt` | Flatpak apps: Discord, Obsidian, Firefox and others |
| `gnome-desktop.dconf` | Desktop look: Adwaita theme and icons, Roboto fonts, dark mode, blue accent, close-only window buttons, 4 fixed workspaces, and which extensions are on or off (Ubuntu Dock, desktop icons and web search are off) |
| `desktop-settings.dconf` | Window shortcuts (<kbd>Super</kbd> + <kbd>W</kbd>, <kbd>Super</kbd> + <kbd>1</kbd>–<kbd>4</kbd> for workspaces), the screenshot shortcut, power (never sleep on AC), sound theme, Files list view, file dialogs, search order, the Backups schedule, Text Editor and Ptyxis settings |
| `gnome-shortcuts.dconf` | Custom keyboard shortcuts: <kbd>Super</kbd> + <kbd>C</kbd> / <kbd>X</kbd> / <kbd>T</kbd> / <kbd>E</kbd> / <kbd>F</kbd> / <kbd>O</kbd> |
| `gnome-extension-settings.dconf` | Settings for Caffeine, Clipboard Indicator, Ubuntu Dock, Tiling Assistant |
| `dock-favorites.txt` | Apps pinned to the dock, in order |
| `gnome-extensions.txt` | GNOME extensions that `install.sh` installs from extensions.gnome.org |
| `apps/` | Apps that start at login, default apps (Chrome as browser, Showtime for video, Calendar), qBittorrent settings and theme, Obsidian vault settings, theme and the list of community plugins (not the notes or the plugins themselves). Cookies and window sizes are left out, and home-folder paths are stored as `@HOME@` |
| `keys/chatgpt.asc` | OpenAI's public signing key for the ChatGPT app's update source (OpenAI doesn't publish it at an address of its own); `install-apps.sh` checks its fingerprint |
| `autoinstall.yaml` | Answers for the Ubuntu installer's [automated install](new-computer.md#option-2-automated-install) (no passwords in it) |

## Automation and the website

| File | What it is |
|---|---|
| `system/etc/` | The weekly update and monthly clean-up jobs; `@USER@` is replaced by your username when installed |
| `system/first-login/` | The one-time first-login step an automated install adds: opens a terminal running `bootstrap.sh` |
| `.githooks/pre-commit` | The [secret check](maintenance.md#secret-check-before-commits) |
| `.github/workflows/check.yml` | The [GitHub checks](maintenance.md#github-checks) |
| `.github/workflows/pages.yml` | Builds and publishes the website |
| `.github/dependabot.yml` | Monthly pull requests when the workflows' actions have new versions |
| `site/` | The [website](https://ronaldo-kwan.github.io/dotfiles/): pick options, get a command or `autoinstall.yaml`. `options.json` is generated |
| `scripts/build-site.py` | Writes `site/options.json` from `install-apps.sh` and the lists in `setup/`, so the site matches the scripts |
