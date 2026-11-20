# dotfiles

My Ubuntu (GNOME) setup: bash, ble.sh, Starship, fzf, zoxide, eza, bat, Ghostty, btop, lazygit and VS Code, all in Catppuccin Mocha with JetBrainsMono Nerd Font, plus my apps, desktop settings and weekly updates.

## New computer

Install Ubuntu 26.04 (first read [Before installing](docs/new-computer.md#before-installing-ubuntu-lenovo-legion-5)), open a terminal (<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd>) and run this one command. No GitHub account or sign-in needed:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/bootstrap.sh)
```

It installs git and gum, downloads the dotfiles to `~/dotfiles`, asks your name and email for git (once), and one question: press <kbd>Enter</kbd> for **Yes to everything**, type your password once, and it runs by itself: it updates the system, installs everything and restarts at the end. Afterwards, `gh auth login` signs you in to GitHub for your notes, pushing and signed commits. Details: [docs/new-computer.md](docs/new-computer.md).

**Even simpler, from the installer:** choose the automated installation and give it `https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main/setup/autoinstall.yaml`. You only pick the disk and type your name and password; at your first login the setup starts by itself. See [Automated install](docs/new-computer.md#automated-install-from-the-installer).

## Everyday

Everything goes through one command, `dot`. On its own, **`dot` opens a menu**: pick with the arrow keys, Enter runs it, and the top shows whether anything is unsaved. Or type the command directly (`dot help` lists them; <kbd>Tab</kbd> completes):

| Command | What it does |
|---|---|
| `dot save` | Refreshes the snapshots in `setup/` (apps, extensions, dock, desktop settings) and shows what changed |
| `dot push "message"` | Saves to GitHub: commits everything and pushes (the secret check runs first) |
| `dot notes` | Same for your Obsidian notes |
| `dot check` | Health check: links, tools, apps, extensions, firewall, signing, backups, unsaved changes. Changes nothing; each ✘ says what fixes it |
| `dot check --fix` | The same, then offers to fix each problem in order (asks first; Enter = yes) |
| `dot status` / `dot cd` / `dot edit` | What changed / go to `~/dotfiles` / open it in VS Code |
| `dot install`, `dot apps`, `dot fresh`, `dot upgrade`, `dot ssh` | The setup scripts (see below) |
| `update` | Updates Ubuntu packages now (it also happens weekly by itself) |

`dotsave` and `dotcheck` still work as before.

Config files like `~/.bashrc` are links into this folder, so editing either place edits the same file. A **weekly reminder** (Sunday evening, or your next login) tells you if settings changed since the last `dot save`, you installed Ubuntu apps that aren't saved, automatic backups are off, or changes aren't committed. It never commits anything.

A **secret check** runs before every commit here and in your notes repo, and stops the commit if something looks like a password, token or key. False alarm? `git commit --no-verify`.

## Signed commits

```bash
dot ssh
```

Creates an SSH key for this computer (if there's none), signs your commits with it, and adds it to GitHub, so your commits show **Verified**. One approval in the browser. Run it once per computer.

## After upgrading Ubuntu to a new release

```bash
dot upgrade
```

The upgrade switches off the apps' own update sources (Chrome, VS Code, Claude, Proton VPN, ONLYOFFICE, OBS). This switches them back on, updates everything, puts back anything that went missing (and removes the Snap Firefox if it came back), reinstalls GNOME extensions for the new GNOME, and checks the NVIDIA driver. See [docs/maintenance.md](docs/maintenance.md#after-upgrading-ubuntu).

## Using this yourself

You're welcome to use or adapt this (MIT licence). The scripts install *my* apps and settings, so:

1. **Fork** this repo on GitHub, then in your fork edit:
   - `setup/git-identity`: your name and email (suggested for git commits; saved per computer, never committed)
   - `setup/apt-packages.txt`, `setup/flatpaks.txt`, `setup/vscode-extensions.txt`, `setup/gnome-extensions.txt`: your apps
   - `install-apps.sh` (the `APPS` list): which outside apps to install (Chrome, VS Code, Steam, ...)
   - the configs in `bash/`, `ghostty/`, `starship/` ... to taste; `claude/` holds my Claude Code instructions, delete it if you don't want them
2. On a fresh Ubuntu, run the one command with your fork:
   ```bash
   DOTFILES_REPO=https://github.com/YOU/dotfiles.git bash <(wget -qO- https://raw.githubusercontent.com/YOU/dotfiles/main/bootstrap.sh)
   ```
3. On your current computer, `dot save` then saves your own desktop settings into `setup/`.

Your notes, if any, aren't part of it: `install.sh` looks for a private repo of yours called `obsidian-vault` and skips it if there's none.

## More

- [docs/new-computer.md](docs/new-computer.md): before installing, what `fresh-install.sh` does, the RTX 5060, manual setup
- [docs/apps.md](docs/apps.md): `install-apps.sh`, where each app comes from, Steam, Obsidian, GNOME extensions
- [docs/maintenance.md](docs/maintenance.md): `dot save`, `dot check`, `dot ssh`, weekly updates, monthly clean-up, the reminder, the secret check, `post-upgrade.sh`, GitHub checks
- [docs/files.md](docs/files.md): what every file and folder here is

MIT licensed (see [LICENSE](LICENSE)); the Catppuccin themes keep their own MIT licence.
