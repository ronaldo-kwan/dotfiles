#!/usr/bin/env python3
"""Write the dotfiles website's data from the repo itself, so the site can't drift from it:
  site/options.json  what the picker offers, from the repo's own lists (what the scripts install)
  site/docs.json     the Docs section, from README.md, docs/*.md and the dot command's own help
Run by the GitHub Pages workflow (and by hand to preview:
python3 scripts/build-site.py && python3 -m http.server -d site).
"""
import html
import json
import pathlib
import posixpath
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETUP = ROOT / "setup"
REPO = "https://github.com/ronaldo-kwan/dotfiles"
SITE_URL = "https://ronaldo-kwan.github.io/dotfiles"

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


def latest_release():
    """The newest release tag (v1.2.3), for "set up from the latest release"; None without
    one (or outside a git checkout). The website workflow fetches the tags for this."""
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "tag", "--list", "v*", "--sort=-v:refname"],
                             capture_output=True, text=True, check=True).stdout.split()
    except (OSError, subprocess.CalledProcessError):
        return None
    return next((t for t in out if re.fullmatch(r"v\d+\.\d+\.\d+", t)), None)


# --- The docs ----------------------------------------------------------------------------
# The Docs section's pages, in order: (id, tab label, title, source). The source is a file
# in docs/, the README's sections from one heading up to (not including) another, or the
# dot command's own table and help.
DOC_PAGES = [
    ("start", "Start", "Getting started", ("README.md", "What's inside", "Documentation")),
    ("dot", "dot", "The dot command", "dot"),
    ("new-computer", "New computer", None, "docs/new-computer.md"),
    ("apps", "Apps", None, "docs/apps.md"),
    ("maintenance", "Maintenance", None, "docs/maintenance.md"),
    ("files", "Files", None, "docs/files.md"),
]
ALERTS = {"NOTE": "Note", "TIP": "Tip", "IMPORTANT": "Important", "WARNING": "Warning", "CAUTION": "Caution"}
INLINE_TAGS = re.compile(r"&lt;(/?(?:kbd|br|sub|b|strong|em))&gt;")
LIST_ITEM = re.compile(r"( *)([-*]|\d+\.) +(.*)")
HTML_BLOCK = re.compile(r"</?(details|summary|div|img|br|p)\b")   # lines passed through as they are


def slug(text):
    """GitHub's id for a heading: lower case, punctuation dropped, spaces to hyphens."""
    text = re.sub(r"<[^>]+>|`|\*\*?", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return re.sub(r"[^\w\- ]", "", text.strip().lower()).replace(" ", "-")


class Page:
    """One page being converted: where its links point, and the ids it has."""

    def __init__(self, pid, source):
        self.id, self.source = pid, source
        self.ids, self.toc, self.links = set(), [], []

    def heading_id(self, text):
        base = f"doc-{self.id}-{slug(text)}"
        hid, n = base, 0
        while hid in self.ids:
            n += 1
            hid = f"{base}-{n}"
        self.ids.add(hid)
        return hid

    def href(self, url, pages):
        """A link as the site needs it: a page's heading becomes #doc-<page>-<heading>, any
        other file in the repo a link to it on GitHub."""
        if url.rstrip("/") == SITE_URL:
            return "#build"
        if re.match(r"[a-z]+:", url):
            return url
        path, _, anchor = url.partition("#")
        if not path:
            target = self.source
        else:
            base = posixpath.dirname(self.source) if self.source != "dot" else ""
            target = posixpath.normpath(posixpath.join(base, path))
        page = pages.get(target)
        if page and (target != "README.md" or not anchor or anchor in page["readme_slugs"]):
            hid = f"doc-{page['id']}-{anchor}" if anchor else f"doc-{page['id']}"
            self.links.append((url, hid))
            return "#" + hid
        kind = "tree" if path.endswith("/") or (ROOT / target).is_dir() else "blob"
        return f"{REPO}/{kind}/main/{target}" + (f"#{anchor}" if anchor else "")


def inline(text, page, pages):
    """Inline Markdown: code, links, bold, italics, and the few HTML tags the docs use."""
    keep = []

    def stash(s):
        keep.append(s)
        return f"\x00{len(keep) - 1}\x00"

    text = re.sub(r"`([^`]+)`", lambda m: stash(f"<code>{html.escape(m.group(1), quote=False)}</code>"), text)
    text = html.escape(text, quote=False)
    text = INLINE_TAGS.sub(r"<\1>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  lambda m: stash(f'<a href="{html.escape(page.href(html.unescape(m.group(2)), pages))}">{m.group(1)}</a>'), text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])", r"<em>\1</em>", text)
    while "\x00" in text:
        text = re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], text)
    return text


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def starts_block(s):
    return s.startswith(("```", "#", "|", ">")) or HTML_BLOCK.match(s) is not None or LIST_ITEM.match(s) is not None


def blocks(lines, page, pages, tight=False):
    """Block Markdown (the lines are already dedented): headings, paragraphs, lists, tables,
    code, quotes and GitHub's alerts. Lines starting with an HTML tag pass through."""
    out, i = [], 0
    while i < len(lines):
        line, s = lines[i], lines[i].strip()
        if not s:
            i += 1
        elif s.startswith("```"):
            ind, lang, code = indent_of(line), s[3:].strip(), []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i][ind:] if not lines[i][:ind].strip() else lines[i].lstrip())
                i += 1
            i += 1
            cls = f' class="lang-{lang}"' if lang else ""
            out.append(f"<pre{cls}><code>{html.escape(chr(10).join(code), quote=False)}</code></pre>")
        elif m := re.match(r"(#{2,4}) +(.*)", s):
            level, text = len(m.group(1)), m.group(2)
            hid = page.heading_id(text)
            if level == 2:
                page.toc.append({"id": hid, "text": inline(text, page, pages)})
            out.append(f'<h{level} id="{hid}">{inline(text, page, pages)}</h{level}>')
            i += 1
        elif s.startswith("|") and i + 1 < len(lines) and re.match(r"\|? *:?-{3,}", lines[i + 1].strip()):
            cells = lambda row: [c.strip() for c in row.strip().strip("|").split("|")]
            head = "".join(f"<th>{inline(c, page, pages)}</th>" for c in cells(s))
            i, rows = i + 2, []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append("<tr>" + "".join(f"<td>{inline(c, page, pages)}</td>" for c in cells(lines[i])) + "</tr>")
                i += 1
            out.append(f'<div class="tbl"><table><thead><tr>{head}</tr></thead><tbody>{"".join(rows)}</tbody></table></div>')
        elif s.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(re.sub(r"^ *> ?", "", lines[i]))
                i += 1
            m = re.match(r"\[!(\w+)\]$", quote[0].strip())
            if m and m.group(1) in ALERTS:
                kind = m.group(1).lower()
                out.append(f'<div class="alert {kind}"><p class="alert-title">{ALERTS[m.group(1)]}</p>{blocks(quote[1:], page, pages)}</div>')
            else:
                out.append(f"<blockquote>{blocks(quote, page, pages)}</blockquote>")
        elif LIST_ITEM.match(line):
            i, html_list = list_block(lines, i, page, pages)
            out.append(html_list)
        elif HTML_BLOCK.match(s):
            out.append(s)
            i += 1
        else:
            para = [s]
            i += 1
            while i < len(lines) and lines[i].strip() and not starts_block(lines[i].strip()):
                para.append(lines[i].strip())
                i += 1
            text = inline(" ".join(para), page, pages)
            out.append(text if tight else f"<p>{text}</p>")
    return "\n".join(out)


def list_block(lines, i, page, pages):
    first = LIST_ITEM.match(lines[i])
    ind, ordered = len(first.group(1)), first.group(2)[0].isdigit()
    items, loose = [], False
    while i < len(lines):
        m = LIST_ITEM.match(lines[i])
        if not m or len(m.group(1)) != ind or m.group(2)[0].isdigit() != ordered:
            break
        content = m.start(3)
        body = [m.group(3)]
        i += 1
        while i < len(lines):
            if not lines[i].strip():
                k = i
                while k < len(lines) and not lines[k].strip():
                    k += 1
                if k < len(lines) and indent_of(lines[k]) >= content:
                    body += [""] * (k - i)
                    i = k
                    loose = loose or not LIST_ITEM.match(lines[k][content:])
                    continue
                break
            if indent_of(lines[i]) >= content:
                body.append(lines[i][content:])
            elif indent_of(lines[i]) > ind and not LIST_ITEM.match(lines[i]):
                body.append(lines[i].strip())
            else:
                break
            i += 1
        items.append(body)
        # A blank line between items makes the list loose (paragraphs); only between them
        if i < len(lines) and not lines[i].strip():
            k = i
            while k < len(lines) and not lines[k].strip():
                k += 1
            nxt = LIST_ITEM.match(lines[k]) if k < len(lines) else None
            if nxt and len(nxt.group(1)) == ind and nxt.group(2)[0].isdigit() == ordered:
                loose, i = True, k
    tag, parts = ("ol" if ordered else "ul"), []
    for body in items:
        task = re.match(r"\[( |x)\] +", body[0])
        if task:
            body = [body[0][task.end():]] + body[1:]
        inner = blocks(body, page, pages, tight=not loose)
        box = f'<input type="checkbox" disabled{" checked" if task and task.group(1) == "x" else ""}> ' if task else ""
        parts.append(f'<li{" class=task" if task else ""}>{box}{inner}</li>')
    return i, f"<{tag}>{''.join(parts)}</{tag}>"


def doc_source(source):
    """The Markdown for one page, and its title from its first heading."""
    if source == "dot":
        return dot_markdown(), None
    if isinstance(source, tuple):
        name, first, stop = source
        text = (ROOT / name).read_text()
        start = text.index(f"\n## {first}\n")
        end = text.index(f"\n## {stop}\n")
        return text[start:end], None
    lines = (ROOT / source).read_text().splitlines()
    lines = [ln for ln in lines if not ln.startswith("[README](../README.md) ·")]   # the pages' own nav
    title = next(ln[2:] for ln in lines if ln.startswith("# "))
    text = "\n".join(ln for ln in lines if not ln.startswith("# "))
    # The page's own table of contents: the site shows one
    text = re.sub(r"\n\*\*Contents\*\*\n\n(?:- .*\n)+", "\n", text + "\n")
    return text, title


def dot_commands():
    """The dot command's table and help, read from the dot script itself."""
    text = (ROOT / "dot").read_text()
    table = re.search(r"^COMMANDS=\(\n(.*?)^\)", text, re.S | re.M).group(1)
    commands = []
    for line in table.splitlines():
        m = re.match(r'\s*"([^"]*)"', line)
        if m:
            name, args, group, label, what = m.group(1).split("|")
            commands.append({"name": name, "args": args, "group": group, "label": label, "what": what})
    groups = dict(re.findall(r'\[(\w+)\]="([^"]*)"', re.search(r"^declare -A GROUP_TITLES=\((.*)\)", text, re.M).group(1)))
    moved = dict(re.findall(r'\[(\w+)\]="([^"]*)"', re.search(r"^declare -A MOVED=\((.*)\)", text, re.M).group(1)))
    body = re.search(r"^details\(\) \{\n(.*?)^\}", text, re.S | re.M).group(1)
    help_text = {}
    for m in re.finditer(r"^    (\w+)\) +cat <<'EOF'\n(.*?)\nEOF\n|^    (\w+)\) +echo \"((?:[^\"\\]|\\.)*)\" ;;", body, re.S | re.M):
        name = m.group(1) or m.group(3)
        help_text[name] = m.group(2) if m.group(1) else re.sub(r"\\(.)", r"\1", m.group(4))
    missing = [c["name"] for c in commands if c["name"] not in help_text]
    if missing:
        sys.exit(f"build-site.py: dot has no help (in details) for: {' '.join(missing)}")
    return commands, groups, moved, help_text


def dot_markdown():
    """The dot page, as Markdown: each command's line from the table, then its own help."""
    commands, groups, moved, help_text = dot_commands()
    md = ["Everything goes through one command. `dot` on its own opens a menu ([how it works](docs/maintenance.md#the-dot-menu)); "
          "`dot help` lists the commands below and `dot help <command>` explains one, the same as here. "
          "<kbd>Tab</kbd> completes commands and options.", ""]
    for group, title in groups.items():
        md += [f"## {title}", ""]
        for c in (c for c in commands if c["group"] == group):
            usage = f"dot {c['name']}" + (f" {c['args']}" if c["args"] else "")
            md += [f"### `{usage}`", ""]
            md += [f"{c['what']}." + (f" In the menu: **{c['label']}**." if c["label"] else ""), ""]
            prose, examples = [], []
            for line in help_text[c["name"]].splitlines():
                if line.startswith("  "):
                    run, _, does = line.strip().partition("  ")
                    examples.append(f"| `{run}` | {does.strip()} |")
                elif line.strip():
                    prose.append(line.strip())
            if prose:
                md += [" ".join(prose), ""]
            if examples:
                md += ["| Run | What it does |", "|---|---|", *examples, ""]
    if moved:
        md += ["> [!NOTE]", "> Old names still work, and say what to type now: " +
               ", ".join(f"`dot {old}` → `{new}`" for old, new in moved.items()) + ".", ""]
    return "\n".join(md)


def build_docs():
    """The Docs section's pages. Stops if a link points at a heading that doesn't exist."""
    pages, sources = [], {}
    for pid, tab, title, source in DOC_PAGES:
        key = source[0] if isinstance(source, tuple) else source
        text, own_title = doc_source(source)
        sources[key] = {"id": pid, "readme_slugs": {slug(h) for h in re.findall(r"^#+ (.*)", text, re.M)}}
        pages.append((pid, tab, title or own_title, key, text))
    out, links, ids = [], [], set()
    for pid, tab, title, key, text in pages:
        page = Page(pid, key)
        body = blocks(text.splitlines(), page, sources)
        out.append({"id": pid, "tab": tab, "title": title, "toc": page.toc, "html": body,
                    "source": f"{REPO}/blob/main/{key}"})
        links += [(pid, url, hid) for url, hid in page.links]
        ids |= page.ids | {f"doc-{pid}"}
    broken = [f"  {pid}: {url}" for pid, url, hid in links if hid not in ids]
    if broken:
        sys.exit("build-site.py: these doc links point at a heading that doesn't exist:\n" + "\n".join(broken))
    return out


def main():
    data = {
        "repo": REPO,
        # bootstrap.sh always comes from main (older releases' copies don't know DOTFILES_REF);
        # with "latest release" ticked, it then sets up from that release.
        "raw": "https://raw.githubusercontent.com/ronaldo-kwan/dotfiles/main",
        "release": latest_release(),
        "groups": [{"token": t, "name": n, "desc": d, "default": t not in GROUP_DEFAULT_OFF} for t, n, d in GROUPS],
        "apps": outside_apps(),
        "ubuntu": ubuntu_apps(),
        "flatpaks": flatpaks(),
    }
    docs = build_docs()
    site = ROOT / "site"
    site.mkdir(exist_ok=True)
    (site / "options.json").write_text(json.dumps(data, indent=1) + "\n")
    (site / "docs.json").write_text(json.dumps({"pages": docs}, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote site/options.json: {len(data['groups'])} groups, {len(data['apps'])} apps, "
          f"{len(data['ubuntu'])} Ubuntu apps, {len(data['flatpaks'])} Flatpaks, "
          f"latest release {data['release'] or '(none)'}")
    print(f"wrote site/docs.json: {len(docs)} pages ({', '.join(p['tab'] for p in docs)})")


if __name__ == "__main__":
    main()
