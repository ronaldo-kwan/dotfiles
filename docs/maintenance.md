[README](../README.md) · [New computer](new-computer.md) · [Apps](apps.md) · **Maintenance** · [Files](files.md)

# Keeping things up to date

Day-to-day use after the setup: saving changes, checking the computer, and what runs by itself.

**Contents**

- Everyday: [Saving changes](#saving-changes) · [The `dot` menu](#the-dot-menu) · [Health check](#health-check)
- Runs by itself: [Weekly reminder](#weekly-reminder) · [Weekly updates and monthly clean-up](#weekly-updates-and-monthly-clean-up) · [Secret check before commits](#secret-check-before-commits)
- Once in a while: [Signed commits](#signed-commits) · [After upgrading Ubuntu](#after-upgrading-ubuntu)
- The repo: [GitHub checks](#github-checks) · [The website and choices](#the-website-and-choices)

## Saving changes

Edit files at their usual place (for example `~/.bashrc`) or in `~/dotfiles`; both are the same file. Then save the change to GitHub:

```bash
dot push "Describe the change"     # = cd ~/dotfiles && git add -A && git commit && git push
```

**Snapshots need a refresh first.** The files in `setup/` are snapshots, so they don't update themselves. After changing extensions, apps, shortcuts, the dock or desktop settings like the theme, run `dot save` (or the old name `dotsave`). It refreshes all of them with `scripts/snapshot.sh` and shows what changed, without committing.

- `setup/apt-packages.txt` is the exception: edit it by hand when you install or remove an Ubuntu app you want on every computer.
- Things GNOME remembers by itself (window sizes, last-used folders, timestamps) are left out of the snapshots on purpose.

## The `dot` menu

`dot` on its own opens a menu: arrow keys to move, <kbd>Enter</kbd> to run, <kbd>q</kbd> or <kbd>Esc</kbd> to quit. Its status line shows unsaved changes in `~/dotfiles` and your notes, and when you last pushed. After each action, any key goes back to the menu. Without `gum`, `dot` prints the list of commands instead.

The scripts use gum too: Yes/No buttons, the start question, the app checklist, and a live list of steps pinned at the top of the terminal. Without gum, in a short window, or when the output goes to a file or GitHub's checks, they fall back to plain text. To force the plain look:

```bash
DOT_PLAIN=1 dot apps
```

## Health check

`dot check` (or `dotcheck`, or `~/dotfiles/check.sh`) checks that this computer still matches the repo. It changes nothing, and each ✘ line ends with what fixes it (→ `dot apps`, → `dot save`, ...).

<details>
<summary>Everything it checks</summary>

- Config links, terminal tools and the Nerd Font
- Every app and system job from `install-apps.sh`, and the NVIDIA driver
- Flatpaks, GNOME extensions and VS Code extensions
- The firewall, the Obsidian vault, the secret check, signed commits and the reminder
- Automatic backups
- Whether the snapshots are out of date
- Ubuntu apps you installed that aren't in `setup/apt-packages.txt`
- Whether anything isn't committed or pushed

</details>

**Ubuntu apps you installed yourself** (with apt, App Center or a `.deb`) are read from apt's history; Ubuntu's own installs are left out. Add each one it lists to `setup/apt-packages.txt` so a new computer gets it, or write it as `-name` to keep it off new computers and stop the reminder:

```text
-cowsay   # just trying it
```

**Automatic backups** count as part of the setup: `dot check` shows ✘ while Backups' "Back Up Automatically" is off. Turn it on (and connect Google Drive), then run `dot save`, so new computers get it switched on too.

### Fixing problems

`dot check --fix` runs the same check, then offers each fix in a sensible order, asking first (<kbd>Enter</kbd> = yes, <kbd>n</kbd> = skip):

1. Missing tools
2. `dot apps`, `dot install`, `dot ssh`
3. Adding unsaved Ubuntu apps to `setup/apt-packages.txt`
4. Opening Backups
5. `dot save`
6. `dot push` and `dot notes` for anything those changed

A summary shows what was fixed. Run `dot check` again to confirm.

## Weekly reminder

A systemd user timer runs `check.sh --notify` on Sunday at 19:00, or at your next login if the computer was off. It shows a notification only if:

- settings changed since your last `dot save`,
- you installed Ubuntu apps that aren't in `setup/apt-packages.txt`,
- automatic backups are off, or
- `~/dotfiles` or your notes have changes that aren't committed or pushed.

It never commits anything.

```bash
systemctl --user list-timers dotfiles-reminder.timer   # when it runs next
~/dotfiles/check.sh --notify                            # run it now
systemctl --user disable --now dotfiles-reminder.timer  # switch it off
```

## Weekly updates and monthly clean-up

`install-apps.sh` installs these, with this computer's username filled in where the scripts say `@USER@`. anacron runs them, so a missed run happens at the next start.

| Job | What it does | Log |
|---|---|---|
| **Weekly updates** (`system/etc/cron.weekly/system-update`) | Updates Ubuntu packages and Flatpak apps, and shows a notification if an update fails, gets stuck, or needs a restart | `/var/log/system-update.log` |
| **Monthly clean-up** (`system/etc/cron.monthly/system-cleanup`) | Removes packages nothing needs any more (`apt autoremove`: old kernels, leftover dependencies) and unused Flatpak runtimes. Notifies if it fails | `/var/log/system-cleanup.log` |

To install one by hand:

```bash
sed "s/@USER@/$(id -un)/" ~/dotfiles/system/etc/cron.weekly/system-update > /tmp/system-update
sudo install -m 755 /tmp/system-update /etc/cron.weekly/system-update
```

## Secret check before commits

[`.githooks/pre-commit`](../.githooks/pre-commit) runs before every commit in `~/dotfiles` and in your notes repo (`install.sh` points both at it with `git config core.hooksPath`). It stops the commit if something being committed looks like a secret:

- **Files that hold keys or sign-ins:** `.env`, `*.pem`, `*.key`, SSH keys, `.git-credentials`, browser cookie and login files, password databases
- **Token formats:** GitHub, Anthropic, OpenAI, AWS, Google, Slack, GitLab, and private keys
- **Settings** like `password = …`, `token: …`, `stream_key = …` (values like `true`, `false`, empty or placeholders are fine)

It shows only the file and line, never the value.

> [!TIP]
> If it's a false alarm, commit with `git commit --no-verify`.

## Signed commits

`dot ssh` ([`scripts/ssh-setup.sh`](../scripts/ssh-setup.sh)) sets up this computer's SSH key, so your commits show **Verified** on GitHub:

1. Creates `~/.ssh/id_ed25519` if there's none. Choose a passphrase; GNOME remembers it after login.
2. Writes `~/.config/git/signing.gitconfig`, so git signs every commit and tag with it.
3. Adds the key to GitHub for signing in and for signing. gh asks for permission once in the browser.

The key never leaves the computer, and each computer gets its own. `install.sh` turns signing back on when the key exists, and never creates keys.

```bash
git log --show-signature -1                 # check a commit
rm ~/.config/git/signing.gitconfig          # stop signing
```

## After upgrading Ubuntu

> [!IMPORTANT]
> A new Ubuntu release (for example 26.04 → 28.04) switches off every app's own update source, so Chrome, VS Code, Claude, Proton VPN, ONLYOFFICE and OBS would quietly stop updating. After the upgrade and its restart, run `dot upgrade`.

```bash
dot upgrade        # same as ~/dotfiles/post-upgrade.sh
```

1. **Switches the update sources back on.** OBS's PPA is made for each release, so it's added again for the new one. If OBS doesn't support the new release yet, it says so; run `~/dotfiles/post-upgrade.sh --sources-only` again a few weeks later.
2. **Updates everything** (apt and Flatpak).
3. **Runs `install-apps.sh`:** anything missing comes back, the Snap Firefox is removed again if the upgrade brought it back, the NVIDIA driver and Steam's 32-bit library match, and the weekly and monthly jobs are put back.
4. **Runs `install.sh`,** downloading GNOME extensions again in the versions for the new GNOME.
5. **Checks the NVIDIA driver** and runs `check.sh`.

Then restart. If an extension is still off, switch it on in the Extensions app.

## GitHub checks

[`.github/workflows/check.yml`](../.github/workflows/check.yml) runs on every push, and every Monday, so a maker changing a download link or signing key shows up as a failed run (GitHub emails you) rather than on the day you set up a new computer. In a clean Ubuntu 26.04 container it runs:

- `shellcheck` on all scripts
- `install.sh` (twice), a dry run of `install-apps.sh`, and `post-upgrade.sh` on test files
- the secret check, the website build and a schema check of `setup/autoinstall.yaml`

The result shows on the repo's [Actions](https://github.com/ronaldo-kwan/dotfiles/actions) tab. To run shellcheck locally:

```bash
sudo apt install shellcheck
shellcheck -x -S warning *.sh scripts/*.sh .githooks/pre-commit
```

## The website and choices

The website ([ronaldo-kwan.github.io/dotfiles](https://ronaldo-kwan.github.io/dotfiles/), source in `site/`) turns what a visitor picks into settings for the scripts:

| Setting | Meaning |
|---|---|
| `DOTFILES_CHOICES='terminal desktop app:chrome pkg:vlc flatpak:org.mozilla.firefox ...'` | Set up only these |
| `DOTFILES_SKIP='claude-md app:steam'` | Everything except these (the site uses whichever is shorter) |
| `DOTFILES_GIT_NAME` / `DOTFILES_GIT_EMAIL` | Your name and email for git, without asking |

`bootstrap.sh` saves the choices in `~/.config/dotfiles/choices` (`-name` lines are skipped items), and every script follows them from then on, including `dot check`, which shows unchosen parts as "not chosen". Delete that file to go back to everything.

The site's app lists come from the repo: `scripts/build-site.py` reads `install-apps.sh` and `setup/`, and the `website` workflow ([`.github/workflows/pages.yml`](../.github/workflows/pages.yml)) rebuilds and publishes it on every push that touches them.

> [!NOTE]
> A new entry in `install-apps.sh` needs a line in `APP_TOKENS` in `scripts/build-site.py`. The build stops with a message if it's missing.
