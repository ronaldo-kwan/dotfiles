#!/usr/bin/env python3
"""Save and put back Brave Origin's own settings: an allowlist of them, never the rest.

Brave keeps settings in its profile's Preferences file (JSON), together with things that
mustn't go in a public repo: your account and sync details, open tabs, and the per-site
lists (Shields and permissions for each site you've changed, which amount to part of your
browsing history). So only the settings named in KEEP are saved, and of those, nothing that
changes by itself (counters, timestamps, migration markers).

  brave-settings.py save <Preferences>             the kept settings, as JSON, to stdout
  brave-settings.py restore <saved.json> <Preferences>
      put them into the profile (creating it if Brave hasn't run yet); Brave must be closed

Whole groups are saved and put back as Brave wrote them, not single values: Brave works some
settings out from others (the bookmarks bar's old on/off from its newer visibility_state),
so one changed without the other is undone when Brave starts. Paths inside your home folder
are stored as @HOME@. Used by save-app-settings.sh (dot push, and dot check to spot unsaved
changes) and install.sh (restore_app_settings).
"""
import json
import os
import re
import sys

# Dotted paths in Preferences: a group (everything under it) or a single setting. Each one
# was checked to exist in Brave Origin 1.100. Nothing here lists sites, accounts or history.
KEEP = [
    "bookmark_bar",                          # show it: always, never, new tab page only
    "brave.always_show_bookmark_bar_on_ntp",
    "brave.dark_mode",                       # light, dark or the system's
    "browser.theme",                         # colour, and its variant
    "brave.tabs",                            # vertical tabs and where, hover cards
    "brave.location_bar_is_wide",
    "brave.show_bookmarks_button",
    "brave.show_side_panel_button",
    "brave.sidebar.sidebar_show_option",     # (not the sidebar's items, which can be sites)
    "brave.new_tab_page.show_background_image",
    "brave.new_tab_page.show_clock",
    "brave.new_tab_page.show_stats",
    "brave.enable_window_closing_confirm",
    "brave.enable_closing_last_tab",
    "brave.mru_cycling_enabled",
    "brave.show_fullscreen_reminder",
    "brave.autocomplete_enabled",
    "brave.top_site_suggestions_enabled",
    "brave.omnibox.bookmark_suggestions_enabled",
    "browser.show_home_button",
    "homepage_is_newtabpage",
    "browser.enable_spellchecking",
    "spellcheck.dictionaries",
    "spellcheck.use_spelling_service",
    "intl.selected_languages",
    "intl.accept_languages",
    "translate.enabled",
    "download.prompt_for_download",
    "download.default_directory",
    "https_only_mode_enabled",               # always use HTTPS: strict or balanced
    "https_first_balanced_mode_enabled",
    "webkit.webprefs",                       # fonts and font sizes
    "profile.default_content_setting_values",  # the defaults for every site (not per site)
]

# Inside a kept group: what Brave changes by itself, or what belongs to this computer only.
SKIP = re.compile(r"(^|_)(p3a|time|count|migrat\w*|last|seen|version|window_placement"
                  r"|collapsed_state|uncollapsed_width|width|height)(_|$)")


def get(d, path):
    for k in path.split("."):
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def clean(v):
    if isinstance(v, dict):
        out = {k: clean(x) for k, x in sorted(v.items()) if not SKIP.search(k)}
        return {k: x for k, x in out.items() if x != {}}
    return v


def home_out(v):
    return json.loads(json.dumps(v).replace(json.dumps(os.path.expanduser("~"))[1:-1], "@HOME@"))


def home_in(v):
    return json.loads(json.dumps(v).replace("@HOME@", json.dumps(os.path.expanduser("~"))[1:-1]))


def save(prefs_file):
    with open(prefs_file) as f:
        prefs = json.load(f)
    kept = {}
    for path in KEEP:
        v = get(prefs, path)
        if v is None:
            continue
        v = clean(v)
        if v != {}:   # a group with nothing left but counters and the like
            kept[path] = v
    json.dump(home_out(kept), sys.stdout, indent=1, sort_keys=True)
    print()


def restore(saved_file, prefs_file):
    with open(saved_file) as f:
        saved = home_in(json.load(f))
    prefs = {}
    if os.path.exists(prefs_file):
        with open(prefs_file) as f:
            prefs = json.load(f)
    for path, v in saved.items():
        if path not in KEEP:   # a saved file is only trusted for the settings named here
            continue
        *parents, last = path.split(".")
        d = prefs
        for k in parents:
            d = d.setdefault(k, {})
        if isinstance(v, dict) and isinstance(d.get(last), dict):
            d[last].update(v)   # a group: its saved settings, keeping what Brave adds itself
        else:
            d[last] = v
    os.makedirs(os.path.dirname(prefs_file), exist_ok=True)
    tmp = prefs_file + ".dotfiles-new"
    with open(tmp, "w") as f:
        json.dump(prefs, f, separators=(",", ":"))
    os.replace(tmp, prefs_file)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "save":
        save(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "restore":
        restore(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
