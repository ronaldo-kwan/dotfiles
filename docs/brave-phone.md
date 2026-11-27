[README](../README.md) · [New computer](new-computer.md) · [Apps](apps.md) · **Brave on your phone** · [Maintenance](maintenance.md) · [Files](files.md)

# Brave on your phone

How to set Brave on Android the same way as Brave Origin on the laptop. The laptop gets its settings from the dotfiles by itself ([Apps](apps.md#brave-origins-settings)); a phone can't, and Brave Sync doesn't carry settings (only bookmarks, passwords, history, open tabs). So it's this checklist, once per phone: about five minutes.

> [!NOTE]
> Menu names change a little between Brave versions. The paths below are from Brave for Android in 2026; if one isn't where it says, use the search box at the top of Brave's **Settings**. Where a laptop setting has no phone equivalent, the table says so.

Open Brave's settings on the phone: the **⋮** menu (bottom right, or top right) → **Settings**.

## Shields and privacy

**Settings → Brave Shields & privacy**

| Setting | Set it to | Laptop |
|---|---|---|
| **Block trackers & ads** | **Aggressive** | Aggressive (saved by `dot push`) |
| **Upgrade connections to HTTPS** | The default, which upgrades where it can (not "strict") | Standard |
| **Block fingerprinting** | **Standard** (the default) | Standard |
| **Block cookies** | **Block third-party cookies** | Locked to the same |
| **Auto-redirect AMP pages** | On | Locked on |
| **Auto-redirect tracking URLs** | On | Locked on |
| **Prevent fingerprinting via language settings** | On | Locked on |
| **WebRTC IP handling policy** | **Default public interface only** | Locked to the same. It hides your local network addresses but keeps video calls working; "Disable non-proxied UDP" is stricter but breaks calls in the browser |
| **Allow privacy-preserving product analytics (P3A)** | Off | Locked off |
| **Automatically send daily usage ping to Brave** | Off | Locked off |
| **Automatically send diagnostic reports** | Off | Locked off |
| **Web Discovery Project** (if listed) | Off | Locked off |
| **Global Privacy Control** (if listed) | On | Locked on |

Stripping tracking parts from links (like `fbclid`) has no switch on the phone: Brave does it by itself, as the laptop's locked setting does.

## Turn off the extras

Brave for Android comes with features Brave Origin on the laptop doesn't have: Rewards and its ads, a crypto wallet, a VPN, Leo (AI), Brave News, Playlist. None can be removed from the app, but each can be switched off and hidden. (Paying the one-time Brave Origin upgrade inside the app removes them instead.)

| Where | Setting | Set it to |
|---|---|---|
| **Settings → Appearance** | **Brave Rewards icon** | Off |
| **Settings → Appearance** | **Brave Ads** | Off |
| **Settings → Brave Wallet** | **Default Ethereum wallet**, **Default Solana wallet** | **None** |
| **Settings → Brave Wallet** | **Display Web3 notifications**, **Enable NFT discovery** | Off |
| **Settings → Brave Shields & privacy** | **Unstoppable Domains**, **Ethereum Name Service** (and its **ENS offchain lookup**), **Solana Name Service**: **Resolve Method** | **Disabled** |
| **Settings → Brave Shields & privacy** | **IPFS Gateway** (if listed) | Off |
| **Settings → Brave Shields & privacy** | **Block "Switch to App" notices** | On |
| **Settings → Notifications** | **Brave Ads** notifications | Off |
| **Settings → New Tab Page** | **Show Sponsored Images** | Off |

These have no single switch in every version, so look for them by name in Settings' search box:

- **Leo:** in **Settings → Leo** (or **Brave Leo**), turn off what shows it in the address bar and menu. Not opening it is enough; it sends nothing until you use it.
- **Brave News:** on a new tab, the **News** switch at the bottom, or **Settings → New Tab Page → Show Brave News**: off.
- **Brave VPN:** nothing to turn off; it only runs if you subscribe. Hide its button where **Settings → Appearance** offers it.
- **Playlist:** **Settings → Media → Playlist** (if listed): off.

On the laptop these are switched off and locked by the dotfiles' policies (see [Apps](apps.md#brave-origins-settings)).

## Search engines

**Settings → Search engines**

| Setting | Set it to | Laptop |
|---|---|---|
| **Standard Tab** | **Google** | Google |
| **Private Tab** | **Google** | Google |

Suggestions as you type go to Google, as on the laptop. To keep them on the phone, turn off **Show search suggestions** (under **Settings → Brave Shields & privacy** or **Search engines**).

## Translation

**Settings → Languages** (on some versions **Settings → Translate**)

| Setting | Set it to | Laptop |
|---|---|---|
| Offer to translate pages | On | On |
| **Always translate** these languages (under **Advanced**) | **German, Japanese, Chinese (Simplified)**, into English | The same |

## New tab page

**Settings → New Tab Page**, or the settings button on a new tab

| Setting | Set it to | Laptop |
|---|---|---|
| **Show background images** | On | On |
| **Show Sponsored Images** | Off | Not on Origin (there's nothing to turn off) |
| **Show Brave stats** (if listed) | Off | Off |
| **Show top sites** / shortcuts | On | On |
| Your shortcuts | Add the same ones by hand: on a new tab, long-press a tile, or **Add shortcut** | Saved by `dot push` (`custom_links` in `setup/apps/brave-settings.json`) |

The laptop's background is the dotfiles' Catppuccin island wallpaper. The phone shows Brave's own images; to use the same one, copy `setup/wallpaper/catppuccin-tropic-island-night-16x9.jpg` to the phone, and pick it on a new tab's customise button if your version offers your own photo.

## Payment cards and addresses

**Settings → Payment methods** and **Settings → Addresses and more**

| Setting | Set it to | Laptop |
|---|---|---|
| **Save and fill payment methods** | Off | Locked off |
| **Save and fill addresses** | As you like | Brave's default |

## Passwords: Bitwarden

The laptop uses the Bitwarden extension. On the phone, install the **Bitwarden Password Manager** app and turn on its autofill: Android's **Settings → Passwords and accounts** (or **Passwords & autofill**) → **Autofill service** → **Bitwarden**. It then fills logins in Brave and in other apps.

## Not on the phone

These laptop settings have no Android equivalent, so there's nothing to set:

- Fonts (Roboto, Roboto Mono): the phone uses the system's
- Vertical tabs, the sidebar, the bookmarks bar, toolbar pins and the forward button: the phone's toolbar is different (you can move it to the bottom under **Settings → Appearance**)
- Extensions and the Ride the Wave theme: Brave for Android doesn't run extensions. For a dark Brave, **Settings → Appearance → Theme → Dark**
- Background mode and what opens on start: Android decides those

## Keeping it the same

When you change one of these on the laptop, `dot push` saves it, and this page is the one to update by hand for the phone. The settings that follow you between computers by themselves are listed under [Brave Origin's settings](apps.md#brave-origins-settings).
