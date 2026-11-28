[README](../README.md) · [New computer](new-computer.md) · **Apps** · [Brave on your phone](brave-phone.md) · [Maintenance](maintenance.md) · [Files](files.md)

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
~/code/github/dotfiles/bin/install-apps.sh            # one question: Yes to everything, or a checklist
~/code/github/dotfiles/bin/install-apps.sh --yes      # Yes to everything without asking (--all and -y work too)
DRY_RUN=1 ~/code/github/dotfiles/bin/install-apps.sh  # only checks the downloads, installs nothing
```

It first asks whether to answer Yes to everything. Choose **Let me choose** to get one checklist of the apps not yet installed: all pre-ticked, <kbd>Space</kbd> unticks, <kbd>Enter</kbd> starts. The codecs' font licence is a checkbox in it. Without gum, it asks Y/n for each app instead.

> [!NOTE]
> **If the computer's clock is wrong** by more than 5 minutes (common in a VM resumed from a saved state), installs would fail with "Release file … is not valid yet". The script checks the clock against the internet first and offers to fix it. If another software update is already running, it waits for it instead of failing.

## Where each app comes from

Each app comes from its maker's official source, so `sudo apt upgrade` keeps it updated. For Chrome, Brave Origin, VS Code, Claude Desktop, Claude Code, ChatGPT and ONLYOFFICE, the maker's signing key is checked against a fixed fingerprint (Brave's key file holds its three release keys, and must hold exactly those), and the source's package list must be signed with it, before the source is added (in dry runs too, so the GitHub check notices a changed key). Proton's setup package is checked the same way: Proton's package list must be signed with its key (fixed fingerprint), and the setup package must match the checksum that list gives. If ONLYOFFICE is installed without its update source (for example from a downloaded `.deb`), the script offers to add the source.

If a maker changes its download link, update the script; the table shows the manual way.

| App | Where to get it | Package |
|---|---|---|
| Google Chrome | Google's apt source, `dl.google.com/linux/chrome-stable/deb` (the same source Chrome's own `.deb` from google.com/chrome sets up) | `google-chrome-stable` |
| Brave Origin | Brave's apt source, `brave-browser-apt-release.s3.brave.com` (key from the same address, `brave-browser-archive-keyring.gpg`; the same source and files as brave.com/origin/linux, and regular Brave's). Free on Linux | `brave-origin` |
| VS Code | Microsoft's apt source, `packages.microsoft.com/repos/code` (the same source VS Code's own `.deb` from code.visualstudio.com sets up) | `code` |
| Claude Desktop | claude.ai/download | `claude-desktop` |
| Claude Code | Anthropic's apt source, `downloads.claude.ai/claude-code/apt/stable` (key from `downloads.claude.ai/keys/claude-code.asc`) | `claude-code` |
| ChatGPT (with Codex) | OpenAI's apt source, `persistent.oaistatic.com/codex-app-prod/linux/deb` (OpenAI ships the key inside its `.deb`; a copy is in [`setup/keys/chatgpt.asc`](../setup/keys/chatgpt.asc)) | `chatgpt` |
| Proton VPN | protonvpn.com/download (Linux, Ubuntu) | `proton-vpn-gnome-desktop` |
| OBS Studio | `sudo add-apt-repository ppa:obsproject/obs-studio` | `obs-studio` |
| ONLYOFFICE | ONLYOFFICE's update source (key from download.onlyoffice.com/GPG-KEY-ONLYOFFICE) | `onlyoffice-desktopeditors` |
| Steam | Ubuntu's own package; needs 32-bit support: `sudo dpkg --add-architecture i386` | `steam-installer` |
| Ubuntu apps | `sudo apt install` the packages in [`setup/apt-packages.txt`](../setup/apt-packages.txt) | see the file |

## Brave Origin's settings

`install-apps.sh` also puts [`system/etc/brave/policies/managed/dotfiles.json`](../system/etc/brave/policies/managed/dotfiles.json) in `/etc/brave/policies/managed/`, where Brave reads settings an administrator sets. They apply from Brave's next start, show at `brave://policy`, and are locked in Brave's own settings (with a "managed by your organization" note). Shields' ad blocking and fingerprinting levels are left at Brave's defaults: "aggressive" and "strict" break sites.

| Setting | Value | Why |
|---|---|---|
| `BraveP3AEnabled`, `BraveStatsPingEnabled`, `BraveWebDiscoveryEnabled`, `MetricsReportingEnabled` | off | No product analytics, daily usage ping, Web Discovery Project or diagnostic reports sent to Brave |
| `BraveGlobalPrivacyControlEnabled` | on | Tells sites not to sell or share your data (a legal opt-out in some places) |
| `BraveDeAmpEnabled`, `BraveDebouncingEnabled`, `BraveTrackingQueryParametersFilteringEnabled` | on | Skips Google's AMP pages and tracking redirects, and strips tracking parts (like `fbclid`) from links |
| `BraveReduceLanguageEnabled` | on | Shares less about your languages, which sites use to tell people apart |
| `BlockThirdPartyCookies` | on | No cookies from other sites embedded in a page |
| `WebRtcIPHandling` | `default_public_interface_only` | Video calls still work, but sites can't see your local network addresses (with Proton VPN on, only the VPN's) |
| `BackgroundModeEnabled` | off | Closing Brave quits it, instead of leaving it running |
| `AutofillCreditCardEnabled` | off | Card numbers aren't saved in the browser |
| `BraveAIChatEnabled`, `BraveLocalAIEnabled`, `BraveRewardsDisabled`, `BraveWalletDisabled`, `BraveVPNDisabled`, `BraveNewsDisabled`, `BraveTalkDisabled`, `BravePlaylistEnabled` | all off | Leo (AI), Rewards and its ads, the crypto wallet and Web3, the VPN, Brave News, Brave Talk and Playlist. Origin leaves these out already (only Web3, Leo and AI innovations are left as empty entries in its settings menu); this keeps them off if an update brings one back, and in regular Brave too, which reads the same folder |

`brave://policy` lists `AutofillCreditCardEnabled` as deprecated: Chromium is moving it into a newer `AutofillSettings` policy. It still applies (cards aren't saved). Once `AutofillSettings`' format is documented, switch to it; if a future Brave drops the old one, `brave://policy` shows it as unknown.

To change one, edit the file and run `dot apps`; `dot check` shows ✘ until the computer has the saved version. `dot uninstall --apps` removes the file with Brave.

### Your search engines and what opens on start

The search engines you pick in Brave's settings (**Settings → Search engine**, for normal and for private windows) are saved by `dot push` with your other Brave settings, and follow you to a new computer:

- **Private windows:** saved and put back like the settings below. Brave's built-in engines (Google, Brave, DuckDuckGo, Bing and the rest) have the same ID on every computer; one you added yourself is only on this one, so another computer would use Brave's default there.
- **Normal windows:** Brave guards this one against changes from outside (written into its settings file, it's replaced with Google), so `dot push` saves the engine itself (its name and addresses, as Brave has them) and `dot apps` makes it a *recommended* policy in `/etc/brave/policies/recommended/`: Brave starts with it, and you can still change it. Brave shows "Your administrator recommends a specific value" next to it. A computer where you haven't picked one keeps the saved one when you `dot push`.

**What Brave opens on start** (**Settings → Get started → On startup**: the new tab page, where you left off, or pages of your choice) is guarded the same way, so it's saved by `dot push` and made a recommended policy (`RestoreOnStartup`) by `dot apps` too. If you choose pages, their addresses are saved as well (`RestoreOnStartupURLs`), and so go in this repo, which is public.

Suggestions as you type go to the engine you picked (turn off **Improve search suggestions** to keep them on the computer).

### Your extensions and themes

`dot push` saves which extensions and themes you added from the Chrome Web Store: their names and IDs only, never what they store (your Bitwarden vault stays in Bitwarden). They go in this repo, which is public. They aren't installed for you, so nothing is forced on: on a computer that doesn't have them, `dot check` lists them ("Brave extensions you saved that aren't added here") and offers to open their store pages in Brave, where you click **Add to Brave**. A theme applies as soon as it's added. Their pinned icons come back by themselves once they're added.

If you remove one, the next `dot push` shows it leaving the list. On a computer without them, don't `dot push` before adding them, or the list is saved without them (its preview shows that too).

### Your own Brave settings

For Brave on your phone, which can't get these from the dotfiles, see [Brave on your phone](brave-phone.md).


What you change in Brave's own settings (not the locked ones above) is saved by `dot push`, like your desktop settings, into [`setup/apps/brave-settings.json`](../setup/apps/brave-settings.json). `dot check` and the weekly reminder show it as unsaved when Brave's settings differ from the saved ones, and `install.sh` puts them back on a new computer, or after `dot pull`.

Only an allowlist is saved, in [`scripts/brave-settings.py`](../scripts/brave-settings.py): the bookmarks bar, light or dark mode and theme colour, vertical tabs, the address bar and toolbar buttons, the sidebar's on/off (not its items), the new tab page's clock, stats and background (Brave's images, a colour, or one of yours: the file name is saved, and `install.sh` copies the image itself from the dotfiles' [`setup/wallpaper/`](../setup/wallpaper/), so pick one of those for it to follow you; with any other, a new computer keeps Brave's background), closing-window and last-tab behaviour, address bar suggestions, the toolbar (the home and forward buttons, what's pinned in **Customize toolbar**, which extensions' icons are pinned, tab search and the split-tab button), rounded corners, the new tab page's shortcuts (whether they're shown, and the ones you added yourself: their titles and addresses, which go in this repo and so are public; not the ones Brave fills in from your history), the home button, spell check and languages, translation (on or off, the languages to always translate and to never translate, and what to translate into; not the sites you said never to translate), downloads (where to, and whether to ask), HTTPS mode, fonts, the defaults for every site (for example, block notifications), and Shields' levels for every site: trackers and ads (standard or aggressive), fingerprinting, HTTPS upgrades and cookies (the settings in **Settings → Shields**; a level you set for one site isn't saved). Content filtering (**Settings → Shields → Content filtering**, `brave://settings/shields/filters`) is saved too: which filter lists are on or off, your own filters, and the lists you added by address (only the address and whether it's on; Brave downloads the list again). Brave keeps each list only by its ID, so `dot push` saves its name next to it, for you to read (from the list catalog Brave downloads, or a subscribed list's own title); the name isn't put back. Your own filters and those addresses go in this repo, which is public. Brave keeps these in its `Local State` file (next to the profile's `Default` folder, and shared by every profile), not with the other settings, so only these entries are read from it and written back into it; the rest of it (including the key your saved passwords are encrypted with) stays as it is. Developer mode, on the same page, isn't saved: Brave guards it against changes from outside. Brave keeps Strict fingerprinting only until it restarts, even when you set it in its own settings, so a restore gives what Brave itself would show. Nothing else in Brave's settings file is: your account and sync details, open and pinned tabs, history, and the settings you've changed for single sites (which list sites you visit) stay on the computer. Counters and records Brave keeps for itself are left out too, so they don't show as changes.

Brave rewrites its settings file while it's open and when it closes, so `install.sh` puts them back only when Brave is closed (it says so if not). They apply from Brave's next start. The first time, the files Brave had are kept as `Preferences.orig` and `Local State.orig` next to them.

## What else it sets up

| Part | What it does |
|---|---|
| **NVIDIA graphics driver** | Only on computers with an NVIDIA card. Runs Ubuntu's `sudo ubuntu-drivers install`, which picks the right driver for the card and works with Secure Boot. Restart afterwards |
| **Steam on the NVIDIA card** | Installs the 32-bit NVIDIA library that matches the driver (many games need it), and a copy of Steam's shortcut that asks for the NVIDIA card (and is named Steam, not Ubuntu's "Install Steam"). Quit Steam fully first if it's open |
| **Codecs** | `ubuntu-restricted-extras` (in the Ubuntu apps list) includes Microsoft's fonts, whose licence normally stops the install with a full-screen prompt. The script asks about it as a normal question instead (Yes to everything accepts it) |
| **Firewall** | Turns on Ubuntu's firewall (`ufw`) so other devices can't connect in. Everything you start yourself (browsing, Steam, updates) works as before, and qBittorrent's listening port stays open |
| **Snap Firefox removal** | Removes the Snap Firefox and Ubuntu's `firefox` package (which would bring the Snap back), because this setup uses the Flathub Firefox. Only if the Flathub Firefox is installed |
| **Login screen** | The same look as the desktop: a blurred, darkened copy of the wallpaper ([`setup/wallpaper/login-blurred.jpg`](../setup/wallpaper/login-blurred.jpg), copied to `/usr/share/backgrounds/dotfiles/`, since the login screen can't read your home folder), the dark theme, blue accent and Roboto (taken from `setup/gnome-desktop.dconf`). GNOME's usual way, using Ubuntu's own login-screen settings: `/etc/dconf/db/gdm.d/90-dotfiles`, and `/etc/dconf/profile/gdm` (Ubuntu's profile plus `system-db:gdm`). Shows from the next login screen. `dot uninstall --apps` puts Ubuntu's back |
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

Your **notes** aren't in this repo. They're in their own private repo, `obsidian-vault`, at `~/Documents/Obsidian Vault`. `dot push` saves changes to your notes along with `~/code/github/dotfiles` (with its own message, "Update notes"):

```bash
dot push
```

What `install.sh` does for Obsidian:

- Clones the `obsidian-vault` repo to `~/Documents/Obsidian Vault` if it isn't there. This needs `gh auth login` first.
- Adds your Obsidian settings (Catppuccin theme, hidden ribbon, core plugins, which community plugins are on) from `setup/apps/obsidian/` if the vault has none yet.
- Adds the vault to Obsidian's list, so Obsidian opens straight into it. Obsidian must be installed and closed for that; otherwise choose **Open folder as vault** once.

> [!NOTE]
> Community plugins themselves aren't saved here, only the list of them (`community-plugins.json`). Their program files can be megabytes, and their own settings (`data.json`) can hold API keys or sign-ins, while this repo is public. On a new computer, install them again from **Settings → Community plugins**. Your private notes repo can keep the whole `.obsidian` folder, plugins included: `dot push` saves it there.

The [secret check](maintenance.md#secret-check-before-commits) also guards commits in the notes repo.

## GNOME extensions

`install.sh` installs and enables the extensions in [`setup/gnome-extensions.txt`](../setup/gnome-extensions.txt) (Alphabetical App Grid, Blur my Shell, Caffeine, Clipboard Indicator) and restores their settings. It also sets exactly which extensions are on or off, including Ubuntu's built-in ones: Ubuntu Dock, desktop icons and web search are off. They start after you log out and back in.

**Blur my Shell** gives the glass look: a blurred top bar, overview, app grid and lock screen, and frosted Ghostty windows. Ghostty's background is 85% opaque (`background-opacity` in its config) and Blur my Shell blurs what's behind it; it's set to keep the window itself, and so the text, fully solid (`opacity=255` under `[blur-my-shell/applications]` in [`setup/gnome-extension-settings.dconf`](../setup/gnome-extension-settings.dconf)). The top bar goes solid while a window touches it (a maximised or full-screen one: `override-background-dynamically` under `[blur-my-shell/panel]`) and is blurred again when it moves away. The overview (Super) has its own, darker style, `pipeline_overview`: the same blur with a 60% layer of Catppuccin's base colour, so less of the wallpaper shows through. It's defined in `pipelines` under `[blur-my-shell]`, next to Blur my Shell's built-in styles (the setting holds them all); to change how dark it is, edit the last number in `(0.1176, 0.1176, 0.1804, 0.6)`. It's also the app grid's background. Its per-app blur is marked experimental by its author. It switches itself off in Power Saver mode. The lock screen uses the overview's darker style too, and shows no notifications (`show-in-lock-screen=false`; they're all there after unlocking).

To add another extension, put its ID in that file. The ID is shown on its extensions.gnome.org page, or by `gnome-extensions list`.
