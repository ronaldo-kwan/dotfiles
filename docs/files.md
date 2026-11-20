# What's in this repo

## Linked config files

These folders are laid out for [GNU Stow](https://www.gnu.org/software/stow/). Each one is a "package" whose contents mirror your home folder, and the real files in `~` are links into this repo.

| Package | Links to | What it is |
|---|---|---|
| `bash` | `~/.bashrc` | Aliases (`update`, the `dot` command, ...), history, and loading for ble.sh, Starship, zoxide, fzf, eza and bat |
| `git` | `~/.gitconfig` | Name and email, `main` as the default branch, `gh` for GitHub sign-in |
| `starship` | `~/.config/starship.toml` | Minimal prompt (`pure-preset`) |
| `ghostty` | `~/.config/ghostty/config` | Catppuccin Mocha, Nerd Font, padding |
| `btop` | `~/.config/btop/` | Catppuccin Mocha theme and settings |
| `lazygit` | `~/.config/lazygit/config.yml` | Catppuccin Mocha and Nerd Font icons |
| `terminal-default` | `~/.config/xdg-terminals.list` | Makes Ghostty the default terminal |
| `vscode` | `~/.config/Code/User/settings.json` | Theme, fonts, ligatures |
| `claude` | `~/.claude/CLAUDE.md` | Personal instructions for Claude Code |
| `systemd` | `~/.config/systemd/user/dotfiles-reminder.*` | The [weekly reminder](maintenance.md#weekly-reminder) |

## Scripts

| File | What it is |
|---|---|
| `setup/autoinstall.yaml` | Answers for the Ubuntu installer's automated install (no passwords in it) |
| `system/first-login/` | The one-time first-login step an automated install adds: opens a terminal running `bootstrap.sh` |
| `site/` | The website ([ronaldo-kwan.github.io/dotfiles](https://ronaldo-kwan.github.io/dotfiles/)): pick options, get a command or `autoinstall.yaml`. `options.json` is generated |
| `scripts/build-site.py` | Writes `site/options.json` from `install-apps.sh` and the lists in `setup/`, so the site matches the scripts |
| `bootstrap.sh` | The one command for a fresh Ubuntu: installs git, gum and gh, downloads the repo, starts `fresh-install.sh` |
| `fresh-install.sh` | Sets up a freshly installed Ubuntu in one go: system and firmware update, tools, then the two scripts below |
| `install.sh` | Configs, font, Flatpak apps, extensions, settings, secret check and reminder (no sudo) |
| `install-apps.sh` | Apps from their makers' sources, the NVIDIA driver, Steam on the NVIDIA card, weekly updates, monthly clean-up, Snap Firefox removal (sudo) |
| `post-upgrade.sh` | After upgrading Ubuntu to a new release: switches app update sources back on and puts everything back |
| `dot` | The `dot` command: a menu on its own, or `dot help`; `.bashrc` adds `dot cd` and Tab completion |
| `check.sh` | Health check (`dot check`); `--notify` is the weekly reminder |
| `lib.sh` | Helpers shared by the scripts above (questions, gum, the progress panel, steps, spinner, summary, clock check), plus the lists of terminal tools and stow packages |
| `scripts/ssh-setup.sh` | `dot ssh`: SSH key, signed commits, adding the key to GitHub |
| `scripts/snapshot.sh` | Writes the snapshots in `setup/` (used by `dot save`, and by `check.sh` into a temporary copy) |
| `scripts/dump-desktop-settings.sh` | Writes `setup/desktop-settings.dconf` |
| `scripts/save-app-settings.sh` | Writes `setup/apps/` |
| `system/` | Weekly update and monthly clean-up scripts; `@USER@` is replaced by your username when installed |
| `.githooks/pre-commit` | The [secret check](maintenance.md#secret-check-before-commits) |
| `.github/workflows/check.yml` | The [GitHub checks](maintenance.md#github-checks) |

## Snapshots (`setup/`)

Written by `dot save`, restored by `install.sh` (except `apt-packages.txt`, which you edit by hand and `install-apps.sh` installs).

| File | What it is |
|---|---|
| `git-identity` | Name and email suggested for git commits; saved per computer in `~/.config/git/user.gitconfig` |
| `vscode-extensions.txt` | VS Code extensions (the Catppuccin theme) |
| `apt-packages.txt` | Ubuntu packages I installed myself (`-name` lines: installed here on purpose but not wanted on new computers): VLC, qBittorrent, Tweaks, Extension Manager, Backups and rclone (for Google Drive), Software with Flathub, GNOME wallpapers and sounds, codecs, vainfo |
| `flatpaks.txt` | Flatpak apps: Bitwarden, Discord, Obsidian, Firefox and others |
| `gnome-desktop.dconf` | Desktop look: Adwaita theme and icons, fonts, dark mode, blue accent, close-only window buttons, 4 fixed workspaces, and which extensions are on or off (Ubuntu Dock, desktop icons and web search are off) |
| `desktop-settings.dconf` | Window shortcuts (Super+W, Super+1–4 workspaces), screenshot shortcut, power (never sleep on AC), sound theme, Files list view, file dialogs, search order, Backups schedule, Text Editor and Ptyxis settings |
| `gnome-shortcuts.dconf` | Custom keyboard shortcuts: Super+C/X/T/E/F/O |
| `gnome-extension-settings.dconf` | Settings for Caffeine, Clipboard Indicator, Ubuntu Dock, Tiling Assistant |
| `dock-favorites.txt` | Apps pinned to the dock, in order |
| `gnome-extensions.txt` | GNOME extensions that `install.sh` installs from extensions.gnome.org |
| `apps/` | Apps that start at login (Bitwarden), default apps (Chrome as browser, Showtime for video, Calendar), qBittorrent settings and Catppuccin theme, Obsidian vault settings and Catppuccin theme (not the notes). Cookies and window sizes are left out. Home-folder paths are stored as `@HOME@`. |
