# dotfiles

My Ubuntu (GNOME) setup: bash, ble.sh, Starship, fzf, zoxide, eza, bat, Ghostty, btop, lazygit and VS Code, all in Catppuccin Mocha with JetBrainsMono Nerd Font, plus my apps, desktop settings and weekly updates.

## New computer

Install Ubuntu 26.04 (first read [Before installing](docs/new-computer.md#before-installing-ubuntu-lenovo-legion-5)), open a terminal and run:

```bash
sudo apt install git gh
gh auth login
gh repo clone dotfiles ~/dotfiles
~/dotfiles/fresh-install.sh
```

It asks one question at the start: press <kbd>Enter</kbd> for **Yes to everything**, type your password once, and it runs by itself: it updates the system, installs everything and restarts at the end. Details and what to do after: [docs/new-computer.md](docs/new-computer.md).

## Everyday

| Command | What it does |
|---|---|
| `dotsave` | Refreshes the snapshots in `setup/` (apps, extensions, dock, desktop settings) and shows what changed. Doesn't commit. |
| `dotcheck` | Health check: links, tools, apps, extensions, scheduled jobs, unsaved changes. Changes nothing. |
| `cd ~/dotfiles && git add -A && git commit -m "…" && git push` | Saves your changes to GitHub |
| `update` | Updates Ubuntu packages now (it also happens weekly by itself) |

Config files like `~/.bashrc` are links into this folder, so editing either place edits the same file. A **weekly reminder** (Sunday evening, or your next login) tells you if settings changed since the last `dotsave` or changes aren't committed. It never commits anything.

A **secret check** runs before every commit here and in your notes repo, and stops the commit if something looks like a password, token or key. False alarm? `git commit --no-verify`.

## After upgrading Ubuntu to a new release

```bash
~/dotfiles/post-upgrade.sh
```

The upgrade switches off the apps' own update sources (Chrome, VS Code, Claude, Proton VPN, ONLYOFFICE, OBS). This switches them back on, updates everything, puts back anything that went missing (and removes the Snap Firefox if it came back), reinstalls GNOME extensions for the new GNOME, and checks the NVIDIA driver. See [docs/maintenance.md](docs/maintenance.md#after-upgrading-ubuntu).

## More

- [docs/new-computer.md](docs/new-computer.md): before installing, what `fresh-install.sh` does, the RTX 5060, manual setup
- [docs/apps.md](docs/apps.md): `install-apps.sh`, where each app comes from, Steam, Obsidian, GNOME extensions
- [docs/maintenance.md](docs/maintenance.md): `dotsave`, weekly updates, monthly clean-up, the reminder, the secret check, `post-upgrade.sh`, GitHub checks
- [docs/files.md](docs/files.md): what every file and folder here is
