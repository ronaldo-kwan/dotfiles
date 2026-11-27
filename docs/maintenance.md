[README](../README.md) · [New computer](new-computer.md) · [Apps](apps.md) · **Maintenance** · [Files](files.md)

# Keeping things up to date

Day-to-day use after the setup: saving changes, checking the computer, and what runs by itself.

**Contents**

- Everyday: [Saving changes](#saving-changes) · [More than one computer](#more-than-one-computer) · [The `dot` menu](#the-dot-menu) · [Health check](#health-check)
- Runs by itself: [Weekly reminder](#weekly-reminder) · [Weekly updates and monthly clean-up](#weekly-updates-and-monthly-clean-up) · [Secret check before commits](#secret-check-before-commits)
- Once in a while: [Signed commits](#signed-commits) · [After upgrading Ubuntu](#after-upgrading-ubuntu)
- The repo: [GitHub checks](#github-checks) · [The website and choices](#the-website-and-choices) · [The README screenshot](#the-readme-screenshot) · [Releases](#releases)

## Saving changes

Edit files at their usual place (for example `~/.bashrc`) or in `~/code/github/dotfiles`; both are the same file. Then save the change to GitHub:

```bash
dot push                       # the message says what changed: "Update desktop settings and bash config"
dot push "Describe the change" # or your own
dot push --dry-run             # only show what would be saved (-n)
dot push --yes                 # don't ask (-y)
```

It refreshes the snapshots, lists what will be saved in `~/code/github/dotfiles` and your Obsidian notes (message "Update notes"), and asks first. With gum you can also change the message there. Then it commits everything (`git add -A`) and pushes; the [secret check](#secret-check-before-commits) runs before each commit. If GitHub has commits this computer doesn't, it stops before changing anything and asks you to `dot pull` first.

**The snapshots.** The files in `setup/` are snapshots of extensions, apps, shortcuts, the dock and desktop settings like the theme, so they don't update themselves: `dot push` refreshes them with `scripts/snapshot.sh` first. To see what changed without committing anything, run `dot push --dry-run`.

- `setup/apt-packages.txt` is the exception: edit it by hand when you install or remove an Ubuntu app you want on every computer.
- Things GNOME remembers by itself (window sizes, last-used folders, timestamps) are left out of the snapshots on purpose.
- On a computer set up with only some parts chosen on the website, only those parts are refreshed; the rest stays as saved, so a partial setup never overwrites the full one.

## More than one computer

Changes you push from one computer don't reach the others by themselves. On the other computer, run:

```bash
dot pull
```

1. **Gets the new commits** for `~/code/github/dotfiles` and your notes, and lists them. It only fast-forwards, so it never merges or overwrites anything.
2. **Offers to apply them** with `dot install`: new config links, extensions, desktop and app settings. Config files that were already linked are up to date straight away.
3. **Offers `dot apps`** if the app lists changed (`install-apps.sh` or `setup/apt-packages.txt`).

> [!TIP]
> If you also changed settings on this computer, run `dot push` first. Applying the pulled settings replaces this computer's desktop settings with the ones in the repo.

If both computers have new commits, `dot pull` stops and tells you what to run (`git -C ~/code/github/dotfiles pull --rebase`, then `dot push`). `dot check` and the [weekly reminder](#weekly-reminder) tell you when GitHub has commits this computer doesn't.

## The `dot` menu

`dot` on its own opens a menu: arrow keys to move, <kbd>Enter</kbd> to run, <kbd>Esc</kbd> to quit. It checks GitHub first (5 seconds at most), then shows for `~/code/github/dotfiles` and your notes whether anything is unsaved, not pushed or new on GitHub, and when you last pushed. The cursor starts on what needs doing: **Get changes** if GitHub has new commits, **Save to GitHub** if something is unsaved, otherwise **Health check**. The setup scripts are under **Set up and repair**. After each action it says whether it worked; <kbd>Enter</kbd> goes back to the menu, <kbd>q</kbd> quits. Without `gum`, `dot` prints the same status lines and the list of commands.

Every command explains itself: `dot help <command>` or `dot <command> --help` (which never starts the script). A mistyped command gets a suggestion (`dot psuh` → *Did you mean: dot push?*), and old names say what replaced them (`dot notes` → `dot push`; `dot save` still works, as `dot push --dry-run`). `dot` exits with 0 when it worked, 1 when something failed and 2 when the command line was wrong.

The scripts use gum too: Yes/No buttons, the start question, the app checklist, and a live list of steps pinned at the top of the terminal. Without gum, in a short window, or when the output goes to a file or GitHub's checks, they fall back to plain text. To force the plain look:

```bash
DOT_PLAIN=1 dot apps
```

## Health check

`dot check` (or `~/code/github/dotfiles/bin/check.sh`) checks that this computer still matches the repo. Each ✘ line ends with what fixes it (→ `dot apps`, → `dot push`, ...), and if anything is wrong it offers to [fix it](#fixing-problems). It changes nothing unless you say yes.

<details>
<summary>Everything it checks</summary>

- Config links, terminal tools, and the two fonts: installed, and the pinned version (an older copy shows ✘; `dot install` replaces it)
- Every app and system job from `install-apps.sh`, and the NVIDIA driver. If it isn't running because Ubuntu installed a new kernel before the NVIDIA module for it (this happens; the module follows within days), it says so, names an older kernel to start from the boot menu (**Advanced options for Ubuntu**) meanwhile, and tells you once Ubuntu has published the module (`sudo apt update && sudo apt full-upgrade`, then restart)
- Flatpaks, GNOME extensions and VS Code extensions
- The firewall, the Obsidian vault, the secret check, signed commits and the reminder
- Automatic backups
- Whether the snapshots are out of date
- Ubuntu apps you installed that aren't in `setup/apt-packages.txt`
- Whether anything isn't committed or pushed, and whether GitHub has commits from another computer

</details>

**Apps you installed yourself** (with apt, App Center or a `.deb`) are read from apt's history; Ubuntu's own installs are left out. Add each Ubuntu app it lists to `setup/apt-packages.txt` so a new computer gets it, or write it as `-name` to keep it off new computers and stop the reminder:

```text
-cowsay   # just trying it
```

Apps that only come from their maker's own update source, a PPA or a downloaded `.deb` are listed separately: `setup/apt-packages.txt` can't install them, because a new computer doesn't have that source. To keep one, add it to `install-apps.sh` with its source (see how ChatGPT is done: an `APPS` entry, its `APP_PARTS` line and its install function); otherwise write it as `-name`. `dot check` never adds these to the list.

**Automatic backups** count as part of the setup: `dot check` shows ✘ while Backups' "Back Up Automatically" is off. Turn it on (and connect Google Drive), then run `dot push`, so new computers get it switched on too.

### Fixing problems

When `dot check` finds problems, it asks whether to fix them (`dot check --fix` skips that question). Then it offers each fix in a sensible order, asking first (<kbd>Enter</kbd> = yes, <kbd>n</kbd> = skip):

1. `dot pull`, if GitHub has new commits
2. Missing tools
3. `dot apps`, `dot install`, `dot ssh`
4. Adding unsaved Ubuntu apps to `setup/apt-packages.txt`
5. Opening Backups
6. `dot push`, for the snapshots and anything not saved to GitHub

A summary shows what was fixed. Run `dot check` again to confirm.

## Weekly reminder

A systemd user timer runs `check.sh --notify` on Sunday at 19:00, or at your next login if the computer was off. It shows a notification only if:

- settings changed since your last `dot push`,
- you installed Ubuntu apps that aren't in `setup/apt-packages.txt`,
- automatic backups are off,
- `~/code/github/dotfiles` or your notes have changes that aren't committed or pushed, or
- GitHub has commits from another computer (run `dot pull`).

It never commits anything.

```bash
systemctl --user list-timers dotfiles-reminder.timer   # when it runs next
~/code/github/dotfiles/bin/check.sh --notify                            # run it now
systemctl --user disable --now dotfiles-reminder.timer  # switch it off
```

## Weekly updates and monthly clean-up

`install-apps.sh` installs these, with this computer's username filled in where the scripts say `@USER@`. anacron runs them, so a missed run happens at the next start. Each log is kept under 1 MB: past that, it's moved to the same name with `.1` added (`/var/log/system-update.log.1`) and a new one starts.

| Job | What it does | Log |
|---|---|---|
| **Weekly updates** (`system/etc/cron.weekly/system-update`) | Updates Ubuntu packages and Flatpak apps, and shows a notification if an update fails, gets stuck, or needs a restart | `/var/log/system-update.log` |
| **Monthly clean-up** (`system/etc/cron.monthly/system-cleanup`) | Removes packages nothing needs any more (`apt autoremove`: old kernels, leftover dependencies) and unused Flatpak runtimes. Notifies if it fails | `/var/log/system-cleanup.log` |

To install one by hand:

```bash
sed "s/@USER@/$(id -un)/" ~/code/github/dotfiles/system/etc/cron.weekly/system-update > /tmp/system-update
sudo install -m 755 /tmp/system-update /etc/cron.weekly/system-update
```

## Secret check before commits

[`.githooks/pre-commit`](../.githooks/pre-commit) runs before every commit in `~/code/github/dotfiles` and in your notes repo (`install.sh` points both at it with `git config core.hooksPath`). It stops the commit if something being committed looks like a secret:

- **Files that hold keys or sign-ins:** `.env`, `*.pem`, `*.key`, SSH keys, `.git-credentials`, browser cookie and login files, password databases
- **Token formats:** GitHub, Anthropic, OpenAI, AWS, Google, Slack, GitLab, Stripe, npm, Hugging Face, and private keys
- **Settings** like `password = …`, `token: …`, `stream_key = …` (values like `true`, `false`, empty or placeholders are fine). Not in Obsidian plugins' own program code (`.obsidian/plugins/*/main.js`), which copies its settings around in lines that look like key settings; tokens are still looked for there, and plugin settings (`data.json`) are checked in full

It shows only the file and line, never the value.

> [!TIP]
> If it's a false alarm, commit with `git commit --no-verify`.

`--no-verify` skips the check, and a secret a later commit removes is still in the history. So the [GitHub checks](#github-checks) also run it on every commit there is, on every branch. To do the same yourself:

```bash
bash ~/code/github/dotfiles/.githooks/pre-commit --history
```

It names the file, line and commit. A secret it finds there has been on GitHub: revoke it with whoever issued it, since deleting it in a new commit doesn't take it out of the history.

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
> A new Ubuntu release (for example 26.04 → 28.04) switches off every app's own update source, so Chrome, Brave Origin, VS Code, Claude, ChatGPT, Proton VPN, ONLYOFFICE and OBS would quietly stop updating. After the upgrade and its restart, run `dot upgrade`.

```bash
dot upgrade                  # same as ~/code/github/dotfiles/bin/post-upgrade.sh
DRY_RUN=1 dot upgrade --yes  # only shows what it would do
```

1. **Switches the update sources back on.** OBS's PPA is made for each release, so it's added again for the new one. If OBS doesn't support the new release yet, it says so; run `~/code/github/dotfiles/bin/post-upgrade.sh --sources-only` again a few weeks later.
2. **Updates everything** (apt and Flatpak).
3. **Runs `install-apps.sh`:** anything missing comes back, the Snap Firefox is removed again if the upgrade brought it back, the NVIDIA driver and Steam's 32-bit library match, and the weekly and monthly jobs are put back.
4. **Runs `install.sh`,** downloading GNOME extensions again in the versions for the new GNOME.
5. **Checks the NVIDIA driver** and runs `check.sh`.

Then restart. If an extension is still off, switch it on in the Extensions app.

## GitHub checks

[`.github/workflows/check.yml`](../.github/workflows/check.yml) runs on every push to `main`, every pull request, and every Monday (a newer push to the same pull request cancels the run it replaces; each job also stops after a time limit, so a stuck download can't hold it for hours). The Monday run catches a maker that moved a download or changed a signing key within a week, and GitHub emails you when it fails. (GitHub pauses scheduled runs in a repo with no activity for 60 days; **Actions → check → Enable workflow** starts them again.) Every job runs on the `ubuntu-26.04` runner rather than `ubuntu-latest`, so a new runner image only comes in when `check.yml` says so. Before setting up a new computer, run it by hand (`gh workflow run check.yml --repo ronaldo-kwan/dotfiles`, or **Actions → check → Run workflow**), so a maker changing a download link or signing key shows up as a failed run rather than halfway through the setup; see [New computer](new-computer.md#first-check-the-dotfiles-still-work). In a clean Ubuntu 26.04 container it runs:

- [`actionlint`](https://github.com/rhysd/actionlint) on the workflow files themselves (mistyped keys, wrong job names in `needs:`, bad `${{ }}` expressions), so a broken workflow fails here instead of on the day it's needed; one fixed version, checked against its checksum like the fonts below (`ACTIONLINT_VERSION` and `ACTIONLINT_SHA256` in `check.yml`)
- [`scripts/lint.sh`](../scripts/lint.sh): a syntax check of every script, `shellcheck` at every level (with the settings in [`.shellcheckrc`](../.shellcheckrc)), `pyflakes` on `scripts/build-site.py` and `node --check` on the website's scripts, with Ubuntu 26.04's own versions of each, and [ESLint](https://eslint.org) on the website's scripts (the versions in `package-lock.json`, with the rules in [`eslint.config.mjs`](../eslint.config.mjs)). Run it yourself after `sudo apt install shellcheck pyflakes3 nodejs npm`; the first run puts ESLint in `node_modules/`
- that actionlint and the Nerd Font are their newest releases: a newer one is a warning on the run, and fails the Monday run, since Dependabot can't update these two
- the system check (both copies must agree), and [`scripts/test-helpers.sh`](../scripts/test-helpers.sh): quick checks of the shared helpers in `lib.sh` and of the app table in `install-apps.sh` (run it yourself with `bash scripts/test-helpers.sh`)
- dry runs of `fresh-install.sh` (every step of setting up a new computer, including `install.sh` and `install-apps.sh`), `post-upgrade.sh` on test files, `install.sh` (which also checks the pinned downloads) and `uninstall.sh --apps`; none may change anything
- `install.sh` (twice), a dry run of `install-apps.sh`, `post-upgrade.sh` on test files, and `uninstall.sh --apps` (no links, test apps or jobs may be left)
- the secret check, on every file and on the whole history (`--history`), and the website build
- the desktop settings, for real in a container without a screen ([`scripts/test-desktop.sh`](../scripts/test-desktop.sh)): `install.sh` must load every saved setting, the dock and the wallpaper, and `uninstall.sh` must put them all back to Ubuntu's defaults
- the website's choices: `install.sh` with only some parts chosen must link only those, and `dot check` must show the rest as "not chosen"

### Pinned downloads

The fonts aren't in this repo. `install.sh` downloads one fixed version of each and uses it only if its checksum matches, so every computer gets the same files and a changed file is never used:

| What | Where (in `lib.sh`) |
|---|---|
| RobotoMono Nerd Font | `NERD_FONT_VERSION` (a Nerd Fonts release) and `NERD_FONT_SHA256` (of its `RobotoMono.tar.xz`) |
| Roboto Mono | `ROBOTO_MONO_URL` (a commit of Google Fonts' repo) and `ROBOTO_MONO_FILES` |

The wallpaper is in the repo itself, in [`setup/wallpaper/`](../setup/wallpaper/) (its MIT licence is in [`licenses/wallpaper.txt`](../licenses/wallpaper.txt)). To use another, replace the file there, keeping its name (or change `WALLPAPER` in `lib.sh`).

To move to a newer version, change the address, download the file and put its checksum next to it:

```bash
curl -fsSL -o /tmp/f "<new address>" && sha256sum /tmp/f
```

The Monday check run tells you when Nerd Fonts has a newer release. Nerd Fonts publishes its checksums with each release (`SHA-256.txt`), so you can compare. Then run `DRY_RUN=1 dot install --yes`: it downloads and checks the files without installing them. After the change, `dot check` shows ✘ on each computer until `dot install` has put the new version there.

The workflows name each action by its commit ID, with the version as a comment (`actions/checkout@3d3c42e… # v7.0.1`), since a tag like `v7` can be moved to other code. Dependabot ([`.github/dependabot.yml`](../.github/dependabot.yml)) looks for new releases every week and opens one pull request that moves them all, ID and comment; the check workflow runs on it, so merge it once it's green, after reading the release notes of any new major version. To update one by hand instead, find its newest release and that release's commit ID:

```bash
gh release view --repo actions/checkout --json tagName --jq .tagName   # e.g. v7.0.1
gh api repos/actions/checkout/commits/v7.0.1 --jq .sha
```

Then replace the commit ID and the version comment on every line that uses it (`grep -rn 'actions/checkout@' .github/workflows`), and read the release notes for a new major version. The actions are `actions/checkout`, `actions/configure-pages`, `actions/upload-pages-artifact` and `actions/deploy-pages`. Pushing runs both workflows on the new versions.

actionlint is pinned the same way as the fonts: `ACTIONLINT_VERSION` and `ACTIONLINT_SHA256` in `check.yml`, from the release's `checksums.txt`. ESLint is in `package.json` and `package-lock.json`, and Dependabot updates those too, in a pull request of its own.

GitHub also guards the repo itself (**Settings → Rules → Rulesets**): `main` can't be force-pushed or deleted, and release tags (`v*`) can't be moved or deleted, so `DOTFILES_REF=v2.0.0` always sets up the same code. Dependabot alerts and security updates are on, so a security advisory for anything Dependabot watches shows up under **Security** with a pull request that fixes it.

The result shows on the repo's [Actions](https://github.com/ronaldo-kwan/dotfiles/actions) tab. To run the lint checks locally:

```bash
sudo apt install shellcheck pyflakes3 nodejs npm
bash ~/code/github/dotfiles/scripts/lint.sh
```

## The website and choices

The website ([ronaldo-kwan.github.io/dotfiles](https://ronaldo-kwan.github.io/dotfiles/), source in `site/`) turns what a visitor picks into settings for the scripts:

| Setting | Meaning |
|---|---|
| `DOTFILES_CHOICES='terminal desktop app:chrome pkg:vlc flatpak:org.mozilla.firefox ...'` | Set up only these |
| `DOTFILES_SKIP='claude-md app:steam'` | Everything except these (the site uses whichever is shorter) |
| `DOTFILES_GIT_NAME` / `DOTFILES_GIT_EMAIL` | Your name and email for git, without asking |

`bootstrap.sh` saves the choices in `~/.config/dotfiles/choices` (`-name` lines are skipped items), and every script follows them from then on, including `dot check`, which shows unchosen parts as "not chosen". Delete that file to go back to everything.

The site's app lists come from the repo: `scripts/build-site.py` reads `install-apps.sh` and `setup/`. So does the docs site ([ronaldo-kwan.github.io/dotfiles/docs](https://ronaldo-kwan.github.io/dotfiles/docs/), source in `site/docs/`): it turns `README.md` (from *What's inside* to *Use it yourself*) and the pages in `docs/` into HTML, and builds the `dot` page from the `COMMANDS` table and help in `dot` itself, so the docs never say something the repo doesn't. The installer and the docs share their look and the light/dark switch (`site/style.css`, `site/common.js`, and `site/theme.js`, which puts the saved theme on before the page is drawn). Both pages carry a Content-Security-Policy that lets only the site's own files load or run, so no inline `<script>`, `<style>` or `style="…"`: put code and styles in the `.js` and `.css` files. The `website` workflow ([`.github/workflows/pages.yml`](../.github/workflows/pages.yml)) rebuilds and publishes it on every push to `main` that touches any of them. On a pull request it only builds the site, so a mistake shows up before merging and nothing is published.

If a deploy fails, use **Re-run failed jobs** on the run: the build and the deploy are separate jobs, so only the deploy runs again, with the site the build already uploaded. Don't use **Re-run all jobs**: the build would upload the site a second time, and the deploy stops when it finds two. If the build itself failed, start a new run instead (**Run workflow** on the `website` workflow, or `gh workflow run pages.yml`).

> [!NOTE]
> A new app in `install-apps.sh` (an `APPS` entry whose choice starts with `app:`) needs a description in `APP_DESCRIPTIONS` in `scripts/build-site.py`. The build stops with a message if it's missing. It also stops if a link in the docs points at a heading that doesn't exist, or a `dot` command has no help. A new page in `docs/` goes in `DOC_PAGES` there. To preview the site: `python3 scripts/build-site.py && python3 -m http.server -d site`, then open `localhost:8000` (the installer) and `localhost:8000/docs/`.

## The README screenshot

[`docs/images/desktop.webp`](images/desktop.webp) is taken from the `ubuntu-dotfiles-test` virtual machine in GNOME Boxes, so it shows a fresh install rather than this computer.

1. Start `ubuntu-dotfiles-test` in Boxes, log in, open Ghostty in `~/code/github/dotfiles` and run `fastfetch && ls`. Close anything else.
2. With the Boxes window still open, capture the machine's screen (Boxes comes with `virsh`):

   ```bash
   flatpak run --filesystem=/tmp --command=virsh org.gnome.Boxes -c qemu:///session screenshot ubuntu-dotfiles-test --file /tmp/vm.png
   ```

3. Swap red and blue, and save it at 1920 pixels wide:

   ```bash
   python3 -c "
   from PIL import Image
   im = Image.open('/tmp/vm.png').convert('RGB'); r, g, b = im.split()
   im = Image.merge('RGB', (b, g, r))
   im.resize((1920, round(1920 * im.height / im.width)), Image.LANCZOS).save('docs/images/desktop.webp', quality=85, method=6)"
   ```

> [!IMPORTANT]
> Don't skip the swap. The screenshot comes out with red and blue the wrong way round: the night sky shows orange. Afterwards the terminal's background should be close to Catppuccin Mocha's `#1e1e2e`.

If the picture shows something new, update the `alt` text and caption under it in `README.md`.

## Releases

A release marks a version that set up a real computer properly, so there's a known-good one to go back to. Installs still come from `main`; a release changes nothing for them. They're numbered `vMAJOR.MINOR.PATCH`:

| Bump | When | Example |
|---|---|---|
| Major (`v2.0.0`) | A setup from scratch works differently: a new Ubuntu release, or something removed or replaced | Moving to Ubuntu 28.04 |
| Minor (`v1.1.0`) | Something new: an app, a setting, a `dot` command | Adding an app |
| Patch (`v1.0.1`) | Fixes only | A changed download address |

To make one, after a setup has worked:

1. Run the checks (`gh workflow run check.yml --repo ronaldo-kwan/dotfiles`) and wait for them to pass.
2. Tag `main`, signed like the commits, and push the tag:

   ```bash
   git tag -s v1.1.0 -m "v1.1.0: <one line on what's new>" && git push origin v1.1.0
   ```

3. Publish it with notes grouped as **Features**, **Fixes**, **CI** and **Docs** (see [v1.0.0](https://github.com/ronaldo-kwan/dotfiles/releases/tag/v1.0.0)). `git log --oneline v1.0.0..v1.1.0` lists what went in:

   ```bash
   gh release create v1.1.0 --verify-tag --title v1.1.0 --notes-file notes.md
   ```

4. Rebuild the website, so its **The latest release** switch offers the new one (it reads the newest `v*` tag when it's built):

   ```bash
   gh workflow run pages.yml --repo ronaldo-kwan/dotfiles
   ```

To set up a new computer from a release instead of `main`, tick **The latest release** on the website. That adds `DOTFILES_REF=v1.1.0` to the command, and `bootstrap.sh` sets up from that release: it puts the computer's `main` back to that version.

From then on it's like any computer that's behind GitHub: `dot check` and the weekly reminder say GitHub has new commits, and `dot pull` brings it up to the newest version. `dot push` waits until you've pulled.
