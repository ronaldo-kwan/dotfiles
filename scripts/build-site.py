#!/usr/bin/env python3
"""Write site/options.json for the dotfiles website, from the repo's own lists, so the
site always offers exactly what the scripts install. Run by the GitHub Pages workflow
(and by hand to preview: python3 scripts/build-site.py && python3 -m http.server -d site).
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETUP = ROOT / "setup"

# Groups: one switch each. Tokens are what the scripts check (lib.sh: chosen).
GROUPS = [
    ("terminal", "Terminal", "bash, ble.sh, Starship prompt, Ghostty, btop, lazygit, fzf, zoxide, eza, bat and the RobotoMono Nerd Font, in Catppuccin Mocha"),
    ("desktop", "Desktop look", "Adwaita dark with a blue accent, Roboto fonts in every app, close-only window buttons, 4 workspaces, GNOME extensions (no Ubuntu Dock), keyboard shortcuts, dock, wallpaper, default apps"),
    ("updates", "Weekly updates and monthly clean-up", "Ubuntu and Flatpak updates every week with a notification if something fails; unused packages removed monthly"),
    ("firewall", "Firewall", "Blocks connections from outside (ufw); everything you start yourself still works"),
    ("nvidia", "NVIDIA driver", "Only on computers with an NVIDIA card: Ubuntu's driver, plus Steam's 32-bit library and an NVIDIA shortcut for Steam"),
    ("firmware", "Firmware updates", "BIOS, SSD and device firmware with fwupdmgr, only when the charger is plugged in"),
    ("safety", "Safety checks", "A secret check before every git commit, signed commits (dot ssh), and a weekly reminder to save your settings"),
    ("notes", "Obsidian notes", "Clones your private GitHub repo called obsidian-vault (skipped if you don't have one)"),
    ("nosnapfirefox", "Firefox from Flathub instead of Snap", "Removes Ubuntu's Snap Firefox, only when the Flathub Firefox is installed"),
    ("claude-md", "Claude Code instructions", "The repo owner's personal instructions for Claude Code (~/.claude/CLAUDE.md); you probably don't want these"),
]
GROUP_DEFAULT_OFF = {"claude-md"}

# install-apps.sh entries that are single apps, by their install function.
APP_TOKENS = {
    "install_chrome": ("app:chrome", "Google's browser, from Google's own update source"),
    "install_vscode": ("app:code", "Microsoft's code editor, with the Catppuccin theme"),
    "install_claude": ("app:claude", "Anthropic's desktop app"),
    "install_claude_code": ("app:claude-code", "Anthropic's AI coding assistant for the terminal (the claude command)"),
    "install_chatgpt": ("app:chatgpt", "OpenAI's desktop app, with Codex"),
    "install_protonvpn": ("app:protonvpn", "Proton's VPN app"),
    "install_obs": ("app:obs", "Screen recording and streaming"),
    "install_onlyoffice": ("app:onlyoffice", "Office suite (documents, spreadsheets, slides)"),
    "install_steam": ("app:steam", "Valve's game store"),
}
# Entries handled by groups or the Ubuntu apps list (not shown as single apps).
NOT_SINGLE_APPS = {"install_ubuntu_apps", "install_nvidia_driver", "setup_steam_nvidia",
                   "setup_weekly_updates", "setup_monthly_cleanup", "setup_firewall", "remove_snap_firefox"}

FLATPAK_NAMES = {
    "com.discordapp.Discord": ("Discord", "Chat and voice"),
    "com.github.tchx84.Flatseal": ("Flatseal", "Manage Flatpak app permissions"),
    "md.obsidian.Obsidian": ("Obsidian", "Notes in Markdown"),
    "org.gnome.Boxes": ("Boxes", "Virtual machines"),
    "org.gnome.Calendar": ("Calendar", "GNOME's calendar"),
    "org.gnome.Decibels": ("Decibels", "Audio player"),
    "org.gnome.Music": ("Music", "GNOME's music player"),
    "org.gnome.Showtime": ("Showtime", "Video player"),
    "org.mozilla.firefox": ("Firefox", "Mozilla's browser"),
}


def outside_apps():
    text = (ROOT / "install-apps.sh").read_text()
    block = re.search(r"^APPS=\(\n(.*?)^\)", text, re.S | re.M).group(1)
    apps = []
    for line in block.splitlines():
        m = re.match(r'\s*"([^|]*)\|[^|]*\|([^|"]*)', line)
        if not m:
            continue
        name, fn = m.group(1), m.group(2)
        if fn in NOT_SINGLE_APPS:
            continue
        if fn not in APP_TOKENS:
            sys.exit(f"build-site.py: install-apps.sh has a new entry '{fn}': add it to APP_TOKENS")
        token, desc = APP_TOKENS[fn]
        apps.append({"token": token, "name": name, "desc": desc})
    return apps


def ubuntu_apps():
    apps = []
    for line in (SETUP / "apt-packages.txt").read_text().splitlines():
        m = re.match(r"\s*([a-z0-9][a-z0-9.+-]*)\s*(?:#\s*(.*))?$", line)
        if m:
            apps.append({"token": f"pkg:{m.group(1)}", "name": m.group(1), "desc": (m.group(2) or "").strip()})
    return apps


def flatpaks():
    apps = []
    for fid in (SETUP / "flatpaks.txt").read_text().split():
        name, desc = FLATPAK_NAMES.get(fid, (fid.rsplit(".", 1)[-1], ""))
        apps.append({"token": f"flatpak:{fid}", "name": name, "desc": desc, "id": fid})
    return apps


def main():
    autoinstall = (SETUP / "autoinstall.yaml").read_text()
    data = {
        "repo": "https://github.com/ronaldo-kwan/dotfiles",
        "raw": "https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main",
        "groups": [{"token": t, "name": n, "desc": d, "default": t not in GROUP_DEFAULT_OFF} for t, n, d in GROUPS],
        "apps": outside_apps(),
        "ubuntu": ubuntu_apps(),
        "flatpaks": flatpaks(),
        "autoinstall": autoinstall,
    }
    out = ROOT / "site" / "options.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(data, indent=1) + "\n")
    print(f"wrote {out.relative_to(ROOT)}: {len(data['groups'])} groups, {len(data['apps'])} apps, "
          f"{len(data['ubuntu'])} Ubuntu apps, {len(data['flatpaks'])} Flatpaks")


if __name__ == "__main__":
    main()
