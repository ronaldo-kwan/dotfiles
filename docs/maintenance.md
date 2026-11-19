# Keeping things up to date

## Saving changes (`dot save`, `dot push`)

Edit files at their usual place (for example `~/.bashrc`) or in `~/dotfiles`. Both are the same file. Then save the change:

```bash
dot push "Describe the change"     # = cd ~/dotfiles && git add -A && git commit && git push
```

The files in `setup/` are snapshots, so they don't update themselves. After changing extensions, apps, shortcuts, the dock or desktop settings like the theme, run `dot save` (or the old name `dotsave`). It runs `scripts/snapshot.sh`, which refreshes all of them, and shows what changed, without committing.

`setup/apt-packages.txt` is the exception: edit it by hand when you install or remove an Ubuntu app you want on every computer.

Things GNOME remembers by itself (window sizes, last-used folders, timestamps) are deliberately left out of the snapshots.

## Health check (`dot check`)

`dot check` (or `dotcheck`, or `~/dotfiles/check.sh`) checks that this computer still matches the repo: config links, terminal tools, the Nerd Font, every app and system job from `install-apps.sh`, the NVIDIA driver, Flatpaks, GNOME and VS Code extensions, the firewall, the Obsidian vault, the secret check, signed commits, the reminder, whether the snapshots are out of date, Ubuntu apps you installed that aren't in `setup/apt-packages.txt`, and whether anything isn't committed or pushed.

**Ubuntu apps you installed yourself** (with apt, App Center or a `.deb`) are read from apt's history; Ubuntu's own installs are left out. Add each one it lists to `setup/apt-packages.txt` so a new computer gets it, or write it as `-name` (for example `-cowsay   # just trying it`) to keep it off new computers and stop the reminder. It changes nothing; each ✘ line says which script fixes it.

## Weekly reminder

A systemd user timer (`systemd/.config/systemd/user/dotfiles-reminder.timer`, linked by `install.sh`) runs `check.sh --notify` on Sunday at 19:00, or at your next login if the computer was off. It shows a notification only if settings changed since your last `dot save`, you installed Ubuntu apps that aren't in `setup/apt-packages.txt`, or `~/dotfiles` / your notes have changes that aren't committed or pushed. It never commits.

```bash
systemctl --user list-timers dotfiles-reminder.timer   # when it runs next
~/dotfiles/check.sh --notify                            # run it now
systemctl --user disable --now dotfiles-reminder.timer  # switch it off
```

## Secret check before commits

`.githooks/pre-commit` runs before every commit in `~/dotfiles` and in your notes repo (`install.sh` points both at it with `git config core.hooksPath`). It stops the commit if something being committed looks like a secret:

- files that hold keys or sign-ins (`.env`, `*.pem`, `*.key`, SSH keys, `.git-credentials`, browser cookie and login files, password databases)
- token formats (GitHub, Anthropic, OpenAI, AWS, Google, Slack, GitLab) and private keys
- settings like `password = …`, `token: …`, `stream_key = …` (values like `true`, `false`, empty or placeholders are fine)

It shows only the file and line, never the value. If it's a false alarm: `git commit --no-verify`.

## Signed commits (`dot ssh`)

`dot ssh` (`scripts/ssh-setup.sh`) sets up this computer's SSH key: it creates `~/.ssh/id_ed25519` if there's none (choose a passphrase; GNOME remembers it after login), writes `~/.config/git/signing.gitconfig` so git signs every commit and tag with it, and adds the key to GitHub for signing in and for **Verified** commits (gh asks for permission once in the browser). The key never leaves the computer; each computer gets its own. `install.sh` turns signing back on when the key exists, and never creates keys. To stop signing, delete `~/.config/git/signing.gitconfig`. Check a commit: `git log --show-signature -1`.

## Weekly updates and monthly clean-up

`install-apps.sh` installs these (with this computer's username filled in where the scripts say `@USER@`); anacron runs them, so a missed run happens at the next start:

- **Weekly updates:** `system/etc/cron.weekly/system-update` updates Ubuntu packages and Flatpak apps once a week and shows a notification if an update fails, gets stuck, or needs a restart. Log: `/var/log/system-update.log`.
- **Monthly clean-up:** `system/etc/cron.monthly/system-cleanup` removes packages nothing needs any more (`apt autoremove`: old kernels, leftover dependencies) and unused Flatpak runtimes. It notifies if it fails. Log: `/var/log/system-cleanup.log`.

By hand:

```bash
sed "s/@USER@/$(id -un)/" ~/dotfiles/system/etc/cron.weekly/system-update > /tmp/system-update
sudo install -m 755 /tmp/system-update /etc/cron.weekly/system-update
```

## After upgrading Ubuntu

A new Ubuntu release (for example 26.04 → 28.04) switches off every app's own update source, so Chrome, VS Code, Claude, Proton VPN, ONLYOFFICE and OBS would quietly stop updating. After the upgrade and its restart, run:

```bash
dot upgrade        # same as ~/dotfiles/post-upgrade.sh
```

1. Switches those update sources back on. OBS's PPA is made for each release, so it's added again for the new one; if OBS doesn't support the new release yet, it says so, and you run `~/dotfiles/post-upgrade.sh --sources-only` again a few weeks later.
2. Updates everything (apt and Flatpak).
3. Runs `install-apps.sh`: anything missing comes back, the Snap Firefox is removed again if the upgrade brought it back, the NVIDIA driver and Steam's 32-bit library match, and the weekly/monthly jobs are put back.
4. Runs `install.sh`, downloading GNOME extensions again in the versions for the new GNOME.
5. Checks the NVIDIA driver and runs `check.sh`.

Then restart. If an extension is still off, switch it on in the Extensions app.

## GitHub checks

`.github/workflows/check.yml` runs on every push, and every Monday so a maker changing a download link or signing key shows up as a failed run (GitHub emails you) rather than on the day you set up a new computer: `shellcheck` on all scripts, then `install.sh` (twice), a dry run of `install-apps.sh`, `post-upgrade.sh` on test files and the secret check, in a clean Ubuntu 26.04 container. The result shows on the repo's **Actions** tab. To run shellcheck locally: `sudo apt install shellcheck`, then `shellcheck -x -S warning *.sh scripts/*.sh .githooks/pre-commit`.
