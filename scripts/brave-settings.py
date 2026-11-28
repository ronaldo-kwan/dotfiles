#!/usr/bin/env python3
"""Save and put back Brave Origin's own settings: an allowlist of them, never the rest.

Brave keeps settings in its profile's Preferences file (JSON), together with things that
mustn't go in a public repo: your account and sync details, open tabs, and the per-site
lists (Shields and permissions for each site you've changed, which amount to part of your
browsing history). So only the settings named in KEEP are saved, and of those, nothing that
changes by itself (counters, timestamps, migration markers).

  brave-settings.py save <Preferences> [<saved.json>]   the kept settings, as JSON, to stdout
      (the saved file: to keep its search engine and startup choice when this profile
      hasn't picked them)
  brave-settings.py restore <saved.json> <Preferences> [<images folder>]
      put them into the profile, and the content filtering ones into the Local State file
      above it (creating either if Brave hasn't run yet); Brave must be closed.
      A new tab page background of your own is copied from the images folder (the dotfiles'
      setup/wallpaper/); if it isn't there, the background stays Brave's own.
  brave-settings.py missing <saved.json> <Preferences>
      the saved extensions this profile doesn't have, one "<id> <name>" per line (dot check
      offers to open their Chrome Web Store pages)
  brave-settings.py policy <saved.json>
      the saved search engine and startup choice as Brave policies (recommended: you can
      still change them), or nothing if none is saved. install-apps.sh puts them in
      /etc/brave/policies/recommended/.

Whole groups are saved and put back as Brave wrote them, not single values: Brave works some
settings out from others (the bookmarks bar's old on/off from its newer visibility_state),
so one changed without the other is undone when Brave starts. Paths inside your home folder
are stored as @HOME@. Used by save-app-settings.sh (dot push, and dot check to spot unsaved
changes) and install.sh (restore_app_settings).

Two settings can't be put back that way: Brave guards them against changes from outside
(written in, the search engine is replaced with Google). So the search engine for normal
windows is saved as "search_engine" (name, keyword and addresses, as Brave has them) and what
Brave opens on start as "startup" (and its pages, if you chose some: those go in the repo,
which is public), and both are put back as recommended policies. Brave records neither when
only a policy chose it, so a profile without its own choice keeps the saved one. Private
windows' engine isn't guarded, so it's an ordinary setting.

Shields' levels for every site (trackers and ads: standard or aggressive; fingerprinting)
are kept with the per-site ones, as entries for the pattern "*,*" (every site), so they're
saved apart, as "shields": only those entries, never a site's own. Brave clears the ads one
on a profile without its migration marker, so that's kept too.

Content filtering (brave://settings/shields/filters) isn't in Preferences but in the
"Local State" file next to the profile's folder, which Brave shares between profiles and
which also holds the key your saved passwords are encrypted with. So only the settings
named in LOCAL_KEEP are read from it and saved apart, as "local_state", and written back
into it, leaving the rest as it is: which filter lists are on or off, your own filters
(they go in the repo, which is public), and the lists you subscribed to by address (only
the address and whether it's on: Brave downloads the list again). Brave keeps a list only
by its ID, so each one's name is saved next to it, for you to read: from Brave's list
catalog (a file it downloads), or a subscribed list's own title. Restore leaves names out.
Developer mode, on the same page, is a profile setting Brave guards like the search engine,
so it isn't saved.

Extensions (and themes, which are extensions) from the Chrome Web Store are saved as a list
of their IDs and names, "extensions", never their data. They aren't installed for you: dot
check lists the ones a computer is missing and offers to open their store pages, to add them.
"""
import glob
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
    "brave.new_tab_page.background",          # Brave's images, a colour, or one of yours
    "brave.new_tab_page.custom_background_image_list",  # (file names; the files: restore)
    "brave.enable_window_closing_confirm",
    "brave.enable_closing_last_tab",
    "brave.mru_cycling_enabled",
    "brave.show_fullscreen_reminder",
    "brave.autocomplete_enabled",
    "brave.top_site_suggestions_enabled",
    "brave.omnibox.bookmark_suggestions_enabled",
    "browser.show_home_button",
    "browser.show_forward_button",
    "browser.pin_split_tab_button",
    "toolbar.pinned_actions",                # Customize toolbar: what's pinned (downloads...)
    "tab_search.pinned_to_tabstrip",
    "extensions.pinned_extensions",          # which extensions' icons are on the toolbar
    "brave.web_view_rounded_corners",
    "ntp.custom_links_visible",              # shortcuts on the new tab page
    "ntp.shortcust_visible",                 # (Chromium's own spelling)
    "custom_links",                          # the new tab page's shortcuts you added: their
                                             # titles and addresses go in the repo (public)
    "homepage_is_newtabpage",
    "browser.enable_spellchecking",
    "spellcheck.dictionaries",
    "spellcheck.use_spelling_service",
    "intl.selected_languages",
    "intl.accept_languages",
    "translate.enabled",
    "translate_allowlists",                  # always translate these languages (into which)
    "translate_blocked_languages",           # never offer to translate these
    "translate_recent_target",               # translate into (not the sites never translated)
    "download.prompt_for_download",
    "download.default_directory",
    "https_only_mode_enabled",               # always use HTTPS: strict or balanced
    "https_first_balanced_mode_enabled",
    "webkit.webprefs",                       # fonts and font sizes
    "profile.default_content_setting_values",  # the defaults for every site (not per site)
    "brave.cosmetic_filtering_migration",    # (without it Brave clears the ads level below)
    "brave.default_private_search_provider_guid",  # private windows' engine (built-in ones
                                                   # have the same ID on every computer)
]
# The same, in Local State: content filtering (brave://settings/shields/filters).
LOCAL_KEEP = [
    "brave.ad_block.regional_filters",       # filter lists on or off, by Brave's list ID
    "brave.ad_block.custom_filters",         # your own filters, one per line
    "brave.ad_block.list_subscriptions",     # lists added by address (address and on/off)
    # Without these Brave thinks it hasn't set up the lists yet, and switches its defaults
    # back on (the ones for your region, the cookie notices and mobile notifications lists),
    # over ones you turned off.
    "brave.ad_block.checked_all_default_regions",
    "brave.ad_block.checked_default_region",
    "brave.ad_block.cookie_list_setting_touched",
    "brave.ad_block.mobile_notifications_list_setting_touched",
]
LOCAL = "local_state"
REGIONAL = "brave.ad_block.regional_filters"
SUBSCRIPTIONS = "brave.ad_block.list_subscriptions"
SEARCH = "search_engine"   # normal windows' engine: put back as a policy, not into Preferences
SHIELDS = "shields"        # every site's Shields levels: {"<type>": <setting>} for "*,*"
EVERY_SITE = "*,*"
EXTENSIONS = "extensions"  # Chrome Web Store extensions and themes: IDs and names only
STARTUP = "startup"        # what opens on start (1 last session, 4 pages, 5 new tab, 6 both):
                           # the same

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


def local_state_file(prefs_file):
    """Brave's Local State: in the folder above the profile's (…/Brave-Origin/Local State)."""
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(prefs_file))), "Local State")


def list_names(root):
    """Brave's filter lists by ID: {ID: name}, from the list catalog Brave downloads (a
    component folder next to the profile's), or {} if there isn't one yet."""
    catalogs = glob.glob(os.path.join(glob.escape(root), "*", "*", "list_catalog.json"))
    if not catalogs:
        return {}
    try:
        with open(max(catalogs, key=os.path.getmtime)) as f:   # the newest, if Brave kept two
            return {e["uuid"]: e["title"] for e in json.load(f)
                    if isinstance(e, dict) and isinstance(e.get("uuid"), str) and isinstance(e.get("title"), str)}
    except (OSError, ValueError, TypeError):
        return {}


def filters(local, names=None):
    """The content filtering settings from Local State (see LOCAL_KEEP): each list only as
    on or off. With names (saving), each list's name too, for you to read; Brave doesn't keep
    one, so restore leaves it out."""
    out = {}
    for path in LOCAL_KEEP:
        v = get(local, path)
        if v is None:
            continue
        if path in (REGIONAL, SUBSCRIPTIONS) and isinstance(v, dict):
            # (A subscription's other entries are Brave's record of downloading it.)
            lists = {}
            for key, e in sorted(v.items()):
                if not (isinstance(e, dict) and isinstance(e.get("enabled"), bool)):
                    continue
                lists[key] = {"enabled": e["enabled"]}
                name = (names or {}).get(key) if path == REGIONAL else e.get("title")
                if names is not None and isinstance(name, str) and name:
                    lists[key]["name"] = name
            v = lists
        elif isinstance(v, dict):
            v = clean(v)
        out[path] = v
    return out


def merge(d, v):
    """v into d, one dict inside another: what's saved changes, what's only in d stays (a
    subscription's download record, a list Brave switched on that wasn't saved)."""
    for k, x in v.items():
        if isinstance(x, dict) and isinstance(d.get(k), dict):
            merge(d[k], x)
        else:
            d[k] = x


def put(d, path, v, merge_dicts=True):
    """Set a dotted path in d; a dict merges into the one there (merge) unless told not to."""
    *parents, last = path.split(".")
    for k in parents:
        d = d.setdefault(k, {})
    if merge_dicts and isinstance(v, dict) and isinstance(d.get(last), dict):
        merge(d[last], v)
    else:
        d[last] = v


def write_private(path, data):
    """Write JSON as Brave does, readable by you only (both files hold more than settings)."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".dotfiles-new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.chmod(tmp, 0o600)   # (os.open's mode is only used for a new file)
    os.replace(tmp, path)


def home_out(v):
    return json.loads(json.dumps(v).replace(json.dumps(os.path.expanduser("~"))[1:-1], "@HOME@"))


def home_in(v):
    return json.loads(json.dumps(v).replace("@HOME@", json.dumps(os.path.expanduser("~"))[1:-1]))


def search_engine(prefs):
    """The engine picked in Brave's settings, or None if it's Brave's default or a policy's
    (then Brave records none in the profile)."""
    t = get(prefs, "default_search_provider_data.template_url_data")
    if not isinstance(t, dict) or not t.get("url"):
        return None
    out = {"name": t.get("short_name", ""), "keyword": t.get("keyword", ""), "url": t["url"]}
    if t.get("suggestions_url"):
        out["suggest_url"] = t["suggestions_url"]
    return out


def startup(prefs):
    """What Brave opens on start, if it was picked in its settings (else None)."""
    mode = get(prefs, "session.restore_on_startup")
    if not isinstance(mode, int):
        return None
    out = {"restore_on_startup": mode}
    urls = get(prefs, "session.startup_urls")
    if mode in (4, 6) and urls:
        out["startup_urls"] = urls
    return out


def extensions(prefs):
    """The extensions and themes installed from the Chrome Web Store, sorted by name."""
    out = []
    for ext_id, e in (get(prefs, "extensions.settings") or {}).items():
        m = e.get("manifest") or {}
        if e.get("from_webstore") and e.get("location") == 1 and m.get("name") \
                and not e.get("was_installed_by_default") and not e.get("was_installed_by_oem"):
            item = {"id": ext_id, "name": m["name"]}
            if "theme" in m:
                item["theme"] = True
            out.append(item)
    return sorted(out, key=lambda x: (x["name"].lower(), x["id"]))


def missing(saved_file, prefs_file):
    with open(saved_file) as f:
        saved = json.load(f).get(EXTENSIONS) or []
    have = set()
    if os.path.exists(prefs_file):
        with open(prefs_file) as f:
            have = {e["id"] for e in extensions(json.load(f))}
    for e in saved:
        if e["id"] not in have:
            print(e["id"], e["name"])


def save(prefs_file, previous_file=None):
    with open(prefs_file) as f:
        prefs = json.load(f)
    previous = {}
    if previous_file and os.path.exists(previous_file):
        with open(previous_file) as f:
            previous = json.load(f)
    kept = {}
    # Picked here, or else the one saved before (Brave records none a policy chose)
    for key, value in ((SEARCH, search_engine(prefs)), (STARTUP, startup(prefs))):
        value = value if value is not None else previous.get(key)
        if value:
            kept[key] = value
    shields = {t: e[EVERY_SITE]["setting"]
               for t, e in (get(prefs, "profile.content_settings.exceptions") or {}).items()
               if isinstance(e, dict) and isinstance(e.get(EVERY_SITE), dict) and "setting" in e[EVERY_SITE]}
    if shields:
        kept[SHIELDS] = dict(sorted(shields.items()))
    exts = extensions(prefs)
    if exts:
        kept[EXTENSIONS] = exts
    local_file = local_state_file(prefs_file)
    if os.path.exists(local_file):
        with open(local_file) as f:
            local = filters(json.load(f), list_names(os.path.dirname(local_file)))
        if local:
            kept[LOCAL] = local
    for path in KEEP:
        v = get(prefs, path)
        if v is None:
            continue
        v = clean(v)
        if path == "custom_links" and isinstance(v.get("list"), list):
            # Only shortcuts you added: one Brave filled in from your history isn't saved
            v["list"] = [x for x in v["list"] if isinstance(x, dict) and not x.get("isMostVisited")]
        if v != {}:   # a group with nothing left but counters and the like
            kept[path] = v
    json.dump(home_out(kept), sys.stdout, indent=1, sort_keys=True)
    print()


def own_background(saved, images_dir, profile_dir):
    """Copy a new tab page background of your own into the profile, from images_dir. Drops
    the background settings when its image isn't there (Brave would show nothing)."""
    bg = saved.get("brave.new_tab_page.background") or {}
    names = list(saved.get("brave.new_tab_page.custom_background_image_list") or [])
    if bg.get("type") != "custom_image" and not names:
        return
    wanted = set(names) | ({bg.get("selected_value")} if bg.get("type") == "custom_image" else set())
    have = set()
    for name in sorted(n for n in wanted if n):
        src = os.path.join(images_dir or "", os.path.basename(name))
        dst = os.path.join(profile_dir, "sanitized_background_images", os.path.basename(name))
        if os.path.exists(dst):
            have.add(name)
        elif images_dir and os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), mode=0o700, exist_ok=True)
            with open(src, "rb") as a, open(os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as b:
                b.write(a.read())
            have.add(name)
    saved["brave.new_tab_page.custom_background_image_list"] = [n for n in names if n in have]
    if bg.get("type") == "custom_image" and bg.get("selected_value") not in have:
        saved.pop("brave.new_tab_page.background", None)
        print(f"brave-settings.py: {bg.get('selected_value')} isn't in {images_dir}; "
              "the new tab page keeps Brave's background", file=sys.stderr)


def restore(saved_file, prefs_file, images_dir=None):
    with open(saved_file) as f:
        saved = home_in(json.load(f))
    own_background(saved, images_dir, os.path.dirname(prefs_file))
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
    # Readable by you only, as Brave writes it (it holds more than these settings).
    shields = saved.get(SHIELDS) or {}
    if shields:   # only the "*,*" entries: a site's own stay as they are
        ex = prefs.setdefault("profile", {}).setdefault("content_settings", {}).setdefault("exceptions", {})
        for t, setting in shields.items():
            ex.setdefault(t, {})[EVERY_SITE] = {"setting": setting}
        if "cosmeticFilteringV2" in shields:
            prefs.setdefault("brave", {})["cosmetic_filtering_migration"] = True
    write_private(prefs_file, prefs)
    # Content filtering, into Local State (created if Brave hasn't run yet): only the
    # settings named in LOCAL_KEEP, and only as filters() would save them.
    local_saved = saved.get(LOCAL) if isinstance(saved.get(LOCAL), dict) else {}
    as_local = {}
    for path in LOCAL_KEEP:
        if path in local_saved:
            put(as_local, path, local_saved[path], merge_dicts=False)
    wanted = filters(as_local)
    if wanted:
        local_file = local_state_file(prefs_file)
        local = {}
        if os.path.exists(local_file):
            with open(local_file) as f:
                local = json.load(f)
        for path, v in wanted.items():
            put(local, path, v)
        write_private(local_file, local)


def policy(saved_file):
    with open(saved_file) as f:
        saved = json.load(f)
    out = {}
    engine = saved.get(SEARCH)
    if engine:
        out.update({"DefaultSearchProviderEnabled": True,
                    "DefaultSearchProviderName": engine["name"],
                    "DefaultSearchProviderKeyword": engine["keyword"],
                    "DefaultSearchProviderSearchURL": engine["url"]})
        if engine.get("suggest_url"):
            out["DefaultSearchProviderSuggestURL"] = engine["suggest_url"]
    start = saved.get(STARTUP)
    if start:
        out["RestoreOnStartup"] = start["restore_on_startup"]
        if start.get("startup_urls"):
            out["RestoreOnStartupURLs"] = start["startup_urls"]
    if not out:
        return
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    print()


if __name__ == "__main__":
    if len(sys.argv) in (3, 4) and sys.argv[1] == "save":
        save(*sys.argv[2:])
    elif len(sys.argv) == 4 and sys.argv[1] == "missing":
        missing(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "policy":
        policy(sys.argv[2])
    elif len(sys.argv) in (4, 5) and sys.argv[1] == "restore":
        restore(*sys.argv[2:])
    else:
        sys.exit(__doc__)
