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
    ("terminal", "Terminal", "bash, ble.sh, Starship prompt, Ghostty, btop, lazygit, fzf, zoxide, eza, bat, fastfetch and coloured man pages, all in Catppuccin Mocha, with the RobotoMono Nerd Font"),
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

# A description for each single app in install-apps.sh (its APPS entries with an app:
# choice; the others belong to a group or the Ubuntu apps list).
APP_DESCRIPTIONS = {
    "app:chrome": "Google's browser, from Google's own update source",
    "app:code": "Microsoft's code editor, with the Catppuccin theme",
    "app:claude": "Anthropic's desktop app",
    "app:claude-code": "Anthropic's AI coding assistant for the terminal (the claude command)",
    "app:chatgpt": "OpenAI's desktop app, with Codex",
    "app:protonvpn": "Proton's VPN app",
    "app:obs": "Screen recording and streaming",
    "app:onlyoffice": "Office suite (documents, spreadsheets, slides)",
    "app:steam": "Valve's game store",
}

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
        m = re.match(r'\s*"(app:[^|]*)\|([^|]*)\|', line)   # choice|name|...
        if not m:
            continue
        token, name = m.group(1), m.group(2)
        if token not in APP_DESCRIPTIONS:
            sys.exit(f"build-site.py: install-apps.sh has a new app '{token}': add it to APP_DESCRIPTIONS")
        apps.append({"token": token, "name": name, "desc": APP_DESCRIPTIONS[token]})
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
