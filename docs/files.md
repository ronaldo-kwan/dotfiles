[README](../README.md) · [New computer](new-computer.md) · [Apps](apps.md) · [Brave on your phone](brave-phone.md) · [Maintenance](maintenance.md) · **Files**

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
├── bootstrap.sh                      the one command for a new computer (stays here: its web address)
├── dot                               the dot command
├── bin/                              the main scripts: setting up, checking, undoing
│   ├── fresh-install.sh  install.sh  install-apps.sh  post-upgrade.sh  uninstall.sh
│   └── check.sh  lib.sh              the health check, shared helpers
├── home/                             config files, linked into ~ by Stow
│   └── bash/ git/ starship/ ghostty/ …
├── setup/                            snapshots: apps, extensions, desktop settings
├── scripts/                          snapshot, SSH, website, lint, the tests and the VM test
├── system/                           weekly and monthly jobs, Brave's settings
├── licenses/                         licences of the Catppuccin themes and the wallpaper
├── site/                             the website: the installer, and the docs in docs/
├── docs/                             these pages (images/: the README screenshot)
├── .githooks/                        the secret check, and the checks before pushing
└── .github/                          GitHub checks, the website and Dependabot
```

> [!NOTE]
> Before v2.0.0 the scripts and config folders were at the top of the repo. `bootstrap.sh` still sets up those older releases, and `install.sh` removes the links they left behind.

## Linked config files

The folders in `home/` are laid out for [GNU Stow](https://www.gnu.org/software/stow/). Each one is a "package" whose contents mirror your home folder, and the real files in `~` are links into this repo: `~/.bashrc` is a link to `home/bash/.bashrc`, for example.

| Package | Links to | What it is |
|---|---|---|
| `bash` | `~/.bashrc` | Aliases (`update`, the `dot` command, ...), history, and loading for ble.sh, Starship, zoxide, fzf, eza and bat; ble.sh's colours as you type, and man pages in colour through bat |
| `git` | `~/.gitconfig` | `main` as the default branch, `gh` for GitHub sign-in, and includes for your per-computer name and email (`~/.config/git/user.gitconfig`) and signing (`~/.config/git/signing.gitconfig`) |
| `starship` | `~/.config/starship.toml` | The prompt: the shape of Starship's `tokyo-night` preset, in Catppuccin Mocha colours, with the Ubuntu logo, how long a slow command took, and a red `❯` after one that failed |
| `ghostty` | `~/.config/ghostty/` | Catppuccin Mocha (title bar too), a frosted-glass background (85% opaque, blurred behind by Blur my Shell), Nerd Font, a bar cursor with a smooth trail (`shaders/cursor-trail.glsl`; delete its `custom-shader` line to switch it off), a little extra line spacing, padding, the window's starting size |
| `btop` | `~/.config/btop/` | Catppuccin Mocha theme and settings |
| `lazygit` | `~/.config/lazygit/config.yml` | Catppuccin Mocha and Nerd Font icons |
| `bat` | `~/.config/bat/` | Catppuccin Mocha theme (`install.sh` runs `batcat cache --build` for it), line numbers and git changes |
| `eza` | `~/.config/eza/theme.yml` | Catppuccin Mocha, blue accent, for `ls`, `ll` and `tree` |
| `fzf` | `~/.config/fzf/fzfrc` | Catppuccin Mocha colours, and the list in a rounded box under the command line (Ctrl+R, Ctrl+T, Alt+C) |
| `fastfetch` | `~/.config/fastfetch/config.jsonc` | System info with Nerd Font icons in Catppuccin colours |
| `terminal-default` | `~/.config/xdg-terminals.list`, `~/.local/share/applications/org.gnome.Ptyxis.desktop` | Makes Ghostty the default terminal, and hides Ubuntu's built-in Terminal (Ptyxis) from the app grid and search so typing "ter" finds Ghostty first |
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
| `bin/fresh-install.sh` | Sets up a freshly installed Ubuntu in one go: system and firmware update, tools (the Flatpak apps start installing in the background there), then the two scripts below, and a restart that waits for any other software update to finish |
| `bin/install.sh` | Configs, fonts, Flatpak apps, extensions, settings, the secret check and the reminder (no sudo) |
| `bin/install-apps.sh` | Apps from their makers' sources (each source added and checked, then all their packages installed in one go), the NVIDIA driver, Steam on the NVIDIA card, weekly updates, monthly clean-up, Snap Firefox removal (sudo) |
| `bin/post-upgrade.sh` | After upgrading Ubuntu to a new release: switches app update sources back on and puts everything back |
| `bin/uninstall.sh` | `dot uninstall`: undoes `install.sh` for your user (links, desktop settings, extensions, fonts, reminder, secret check); `--apps` also removes the apps and system parts you pick |

### Everyday

| File | What it is |
|---|---|
| `dot` | The `dot` command (`save`, `push`, `pull`, `check`, ...): a menu on its own, or `dot help`. `.bashrc` adds `dot cd` and <kbd>Tab</kbd> completion |
| `bin/check.sh` | The health check (`dot check`); `--notify` is the weekly reminder |
| `scripts/ssh-setup.sh` | `dot ssh`: SSH key, signed commits, adding the key to GitHub |
| `scripts/snapshot.sh` | Writes the snapshots in `setup/` (used by `dot push`, and by `check.sh` into a temporary copy) |
| `scripts/dump-desktop-settings.sh` | Writes `setup/desktop-settings.dconf` |
| `scripts/save-app-settings.sh` | Writes `setup/apps/` |
| `scripts/test-helpers.sh` | Quick checks of the helpers in `lib.sh` and the app table in `install-apps.sh`, in five groups at once (about 2 seconds); GitHub's checks and the checks before each push run it |
| `docs/brave-phone.md` | How to set Brave on Android the same as the laptop (a phone can't get it from the dotfiles) |
| `scripts/brave-settings.py` | Saves and puts back Brave Origin's own settings: an allowlist from its profile, never the account, tabs or per-site parts (used by `dot push`, `dot check` and `install.sh`) |
| `scripts/lint.sh` | Looks for mistakes in the scripts without running them: syntax, `shellcheck` (every script at once), `pyflakes`, `node --check` and ESLint; GitHub's checks run it, and so do the checks before a push that changes scripts |
| `scripts/test-desktop.sh` | Loads the saved desktop settings and resets them again, checking each one; only runs in GitHub's checks (it changes desktop settings) |
| `scripts/test-vm.sh` | `dot vm`: tests the whole setup like a new computer, in a GNOME Boxes virtual machine: a fresh Ubuntu, the website's command, the restart, then `dot check`. Keeps apt's downloads on a cache disk between tests, so later ones take about 7 minutes ([how](maintenance.md#a-test-in-a-virtual-machine)) |

### Shared

| File | What it is |
|---|---|
| `bin/lib.sh` | Helpers shared by the scripts (questions, gum, the progress panel, steps, spinner, summary, clock check, apt-get, dry runs, reading the `setup/` lists, which packages are installed, fetching both repos at once, the Flatpak apps in the background), plus the lists of terminal tools and stow packages and the places outside `~/code/github/dotfiles` the scripts use (notes vault, wallpaper, fonts, which dconf file goes where) |

## Snapshots (`setup/`)

Written by `dot push` and restored by `install.sh`, except `apt-packages.txt`, which you edit by hand and `install-apps.sh` installs.

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
| `apps/` | Display settings (`monitors.xml`: scale and resolution, without the screen's serial number; put back only on a computer with the same screen), apps that start at login (only Flatpak apps from `flatpaks.txt`, since only those are put back), default apps (Brave Origin as browser, Showtime for video, Calendar), qBittorrent settings and theme, Obsidian vault settings, theme and the list of community plugins (not the notes or the plugins themselves), Brave Origin's own settings (`brave-settings.json`: an allowlist, see [Apps](apps.md#your-own-brave-settings)). Cookies and window sizes are left out, and home-folder paths are stored as `@HOME@` |
| `wallpaper/` | The wallpaper (`tropic_island_night.jpg` from [catppuccin-wallpapers](https://github.com/zhichaoh/catppuccin-wallpapers); its MIT licence is in `licenses/wallpaper.txt`); `install.sh` copies it to `~/Pictures/Wallpapers/current`. `catppuccin-tropic-island-night-16x10.jpg` is a 16:10 crop of it for 16:10 screens (not set by `install.sh`). `login-blurred.jpg` is a blurred, darkened copy for the login screen (`install-apps.sh`) |
| `keys/chatgpt.asc` | OpenAI's public signing key for the ChatGPT app's update source (OpenAI doesn't publish it at an address of its own); `install-apps.sh` checks its fingerprint |

## Automation and the website

| File | What it is |
|---|---|
| `system/etc/` | The weekly update and monthly clean-up jobs (`@USER@` is replaced by your username when installed), and Brave Origin's settings (`brave/policies/managed/dotfiles.json`) |
| `.githooks/pre-commit` | The [secret check](maintenance.md#secret-check-before-commits) |
| `.githooks/pre-push` | The [checks before pushing](maintenance.md#checks-before-pushing): `test-helpers.sh`, and `lint.sh` when a push changes scripts |
| `.shellcheckrc` | `shellcheck`'s settings for every script (and why each one is there) |
| `package.json`, `package-lock.json`, `eslint.config.mjs` | ESLint for the website's scripts (`scripts/lint.sh` runs it; `node_modules/` isn't saved). Nothing here goes on the computers |
| `SECURITY.md` | How to report a security problem privately (GitHub's private vulnerability reporting is on) |
| `.editorconfig` | How editors write the files: UTF-8, Unix line endings, spaces, a newline at the end |
| `.github/workflows/check.yml` | The [GitHub checks](maintenance.md#github-checks) |
| `.github/workflows/pages.yml` | Builds and publishes the website |
| `.github/dependabot.yml` | Opens a pull request each week when the workflows' actions have new releases |
| `site/` | The [website](https://ronaldo-kwan.github.io/dotfiles/): pick options and get your own command (`index.html`, `index.css`, `app.js`). `docs/` is the [docs site](https://ronaldo-kwan.github.io/dotfiles/docs/) with these pages (`docs/index.html`, `docs/docs.js`, `docs/docs.css`). Both use `style.css`, `common.js` and `theme.js` (the saved light/dark choice, before the page is drawn). `options.json` and `docs/docs.json` are generated |
| `scripts/build-site.py` | Writes `site/options.json` from `install-apps.sh` and the lists in `setup/`, and `site/docs/docs.json` from `README.md`, `docs/` and `dot`'s own help, so the site matches the scripts |
