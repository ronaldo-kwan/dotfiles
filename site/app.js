// The dotfiles installer page: builds the option lists from options.json (generated from
// the repo by scripts/build-site.py), and turns the picks into a one-line command. Shows
// the docs from docs.json (generated from README.md, docs/ and dot's own help). Runs
// entirely in the browser.
"use strict";

const $ = (id) => document.getElementById(id);
const STORE = "dotfiles-site-v1";
const THEME = "dotfiles-site-theme";
const LISTS = ["groups", "apps", "ubuntu", "flatpaks"];
const FIELDS = ["gitname", "gitemail"];
const CALM = matchMedia("(prefers-reduced-motion: reduce)").matches;
let data;

// Shell single-quoting: 'it'\''s'
const sq = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";

// Starting points. Each returns whether an item is on.
const PRESETS = {
  everything: (item) => item.default !== false,
  essentials: (item) =>
    ["terminal", "desktop", "updates", "firewall", "nvidia", "firmware", "safety", "nosnapfirefox",
     "app:chrome", "app:code", "flatpak:org.mozilla.firefox", "flatpak:com.github.tchx84.Flatseal"].includes(item.token) ||
    item.token.startsWith("pkg:"),
  terminal: (item) => item.token === "terminal",
};

const allItems = () => LISTS.flatMap((id) => data[id]);
const boxes = () => [...document.querySelectorAll("main input.switch")];

// Each tile gets a Catppuccin accent, the same one every time for the same name.
const ACCENTS = ["mauve", "blue", "teal", "green", "peach", "pink", "yellow", "red", "sky", "lavender"];
function accent(name) {
  let h = 0;
  for (const ch of name) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  return `var(--${ACCENTS[h % ACCENTS.length]})`;
}
function monogram(name) {
  const words = name.replace(/[^\p{L}\p{N} ]/gu, " ").trim().split(/\s+/);
  return (words.length > 1 ? words[0][0] + words[1][0] : name.slice(0, 2)).toUpperCase();
}

function option(item, checked) {
  const label = document.createElement("label");
  label.className = "row";
  label.style.setProperty("--c", accent(item.name));
  label.dataset.search = `${item.name} ${item.desc || ""} ${item.token}`.toLowerCase();
  const av = document.createElement("span");
  av.className = "av";
  av.setAttribute("aria-hidden", "true");
  av.textContent = monogram(item.name);
  const box = document.createElement("input");
  box.type = "checkbox";
  box.className = "switch";
  box.value = item.token;
  box.checked = checked;
  box.addEventListener("change", () => { pop(label); update(); });
  const text = document.createElement("span");
  text.className = "txt";
  const b = document.createElement("b");
  b.textContent = item.name;
  text.append(b);
  if (item.desc) {
    const small = document.createElement("small");
    small.textContent = item.desc;
    text.append(small);
  }
  label.append(av, text, box);
  return label;
}

function pop(el) {
  if (CALM) return;
  el.classList.remove("pop");
  void el.offsetWidth; // restart the animation
  el.classList.add("pop");
}

function load() {
  try { return JSON.parse(localStorage.getItem(STORE)) || {}; } catch { return {}; }
}
function save(state) {
  try { localStorage.setItem(STORE, JSON.stringify(state)); } catch { /* private mode: fine */ }
}

function build(saved) {
  const picked = saved.picked ? new Set(saved.picked) : null;
  const isOn = (item) => (picked ? picked.has(item.token) : PRESETS.everything(item));
  for (const id of LISTS) $(id).replaceChildren(...data[id].map((item) => option(item, isOn(item))));

  document.querySelectorAll("[data-tools]").forEach((span) => {
    const list = span.dataset.tools;
    for (const [word, value] of [["Select all", true], ["Clear", false]]) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "small";
      btn.textContent = word;
      btn.setAttribute("aria-label", `${word}: ${span.closest("details").querySelector(".sec-title").firstChild.textContent.trim()}`);
      btn.addEventListener("click", () => {
        $(list).querySelectorAll("input.switch").forEach((i) => {
          if (!i.closest(".row").hidden && i.checked !== value) { i.checked = value; pop(i.closest(".row")); }
        });
        update();
      });
      span.append(btn);
    }
  });

  document.querySelectorAll('input[name="preset"]').forEach((radio) => {
    radio.addEventListener("change", () => {
      const rule = PRESETS[radio.value];
      if (!rule) return; // Custom: keep the current picks
      const on = new Set(allItems().filter(rule).map((i) => i.token));
      boxes().forEach((b) => {
        if (b.checked !== on.has(b.value)) { b.checked = on.has(b.value); pop(b.closest(".row")); }
      });
      update();
    });
  });

  for (const id of FIELDS) {
    if (saved[id] !== undefined) $(id).value = saved[id];
    $(id).addEventListener("input", update);
  }
  if (saved.gitname || saved.gitemail) $("sec-you").open = true;

  // "The latest release" switch, only when there is one (off unless you ticked it before).
  if (data.release) {
    $("release-name").textContent = `The latest release (${data.release})`;
    $("release").checked = saved.release === true;
    $("release-row").hidden = false;
    $("release").addEventListener("change", update);
  }

  $("filter").addEventListener("input", filter);
}

// Show only the apps whose name or description matches; open the sections that have matches.
function filter() {
  const q = $("filter").value.trim().toLowerCase();
  for (const id of ["apps", "ubuntu", "flatpaks"]) {
    const rows = [...$(id).children];
    let shown = 0;
    for (const row of rows) {
      row.hidden = q !== "" && !row.dataset.search.includes(q);
      if (!row.hidden) shown++;
    }
    const sec = $("sec-" + id);
    sec.querySelector(".empty").hidden = shown > 0;
    if (q) sec.open = shown > 0;
  }
}

// Check the typed fields. Returns whether the command can be made (the name and email are fine).
function validate() {
  const rules = {
    gitname: [(v) => !/[\n\r]/.test(v), "One line, please."],
    gitemail: [(v) => v === "" || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), "That doesn't look like an email address."],
  };
  const good = {};
  for (const [id, [test, msg]] of Object.entries(rules)) {
    good[id] = test($(id).value.trim());
    $(id).setAttribute("aria-invalid", String(!good[id]));
    $(id + "-err").textContent = good[id] ? "" : msg;
  }
  const name = $("gitname").value.trim(), email = $("gitemail").value.trim();
  if ((name === "") !== (email === "")) {
    const missing = name ? "gitemail" : "gitname";
    good[missing] = false;
    $(missing + "-err").textContent = "Fill in both, or leave both empty.";
  }
  return { cmd: good.gitname && good.gitemail };
}

function picks() {
  const all = boxes();
  return { all, on: all.filter((i) => i.checked).map((i) => i.value),
           off: all.filter((i) => !i.checked).map((i) => i.value) };
}

// The variables the scripts read (bootstrap.sh, lib.sh).
function settings(on, total, off) {
  const vars = [];
  // Everything picked: nothing to say. Otherwise whichever list is shorter.
  if (off.length && off.join(" ").length <= on.join(" ").length) vars.push(["DOTFILES_SKIP", off.join(" ")]);
  else if (off.length) vars.push(["DOTFILES_CHOICES", on.join(" ")]);
  const name = $("gitname").value.trim(), email = $("gitemail").value.trim();
  if (name && email) vars.push(["DOTFILES_GIT_NAME", name], ["DOTFILES_GIT_EMAIL", email]);
  // Set up from the latest release instead of main (bootstrap.sh switches to it).
  if (data.release && $("release").checked) vars.push(["DOTFILES_REF", data.release]);
  return vars;
}

// --yes: the picks on this page are the answers, so setup doesn't ask how to answer.
// Returned as [text, colour class] pieces; joined, they are the command exactly.
function command(vars) {
  const parts = [];
  for (const [k, v] of vars) parts.push([k, "t-var"], ["=", ""], [sq(v), "t-val"], [" ", ""]);
  parts.push(["bash", "t-cmd"], [" <(", ""], ["wget", "t-cmd"], [" -qO- ", ""], [`${data.raw}/bootstrap.sh`, "t-url"], [") ", ""], ["--yes", "t-flag"]);
  return parts;
}

function paint(pre, parts) {
  pre.replaceChildren(...parts.map(([text, cls]) => {
    if (!cls) return document.createTextNode(text);
    const span = document.createElement("span");
    span.className = cls;
    span.textContent = text;
    return span;
  }));
}

// Which preset the current picks match, if any.
function matchingPreset(on) {
  const set = new Set(on);
  for (const [name, rule] of Object.entries(PRESETS)) {
    if (allItems().every((i) => rule(i) === set.has(i.token))) return name;
  }
  return "custom";
}

const SOURCE_NAMES = { groups: "setup", apps: "makers", ubuntu: "ubuntu", flatpaks: "flathub" };

function update() {
  const { all, on, off } = picks();
  const ok = validate();
  const vars = settings(on, all.length, off);

  if (ok.cmd) paint($("cmd"), command(vars));
  else paint($("cmd"), [["Fix your name and email for git first (on the left).", "t-err"]]);
  $("copy-cmd").disabled = !ok.cmd;
  if (!ok.cmd) $("sec-you").open = true;
  $("cmd-status").textContent = "";
  $("cmd-status").classList.remove("bad");

  // Counts: the panel, its ring, the phone bar, the jump chips and each section's badge.
  const summary = on.length === all.length ? `All ${all.length} picked` : `${on.length} of ${all.length} picked`;
  $("count").replaceChildren(Object.assign(document.createElement("strong"), { textContent: summary }));
  $("mcount").textContent = summary;
  $("ring-n").textContent = on.length;
  $("ring-of").textContent = `of ${all.length}`;
  $("ring").style.strokeDashoffset = String(263.9 * (1 - (all.length ? on.length / all.length : 0)));
  const split = [];
  for (const id of LISTS) {
    const list = [...$(id).querySelectorAll("input.switch")];
    const n = list.filter((i) => i.checked).length;
    document.querySelector(`[data-badge="${id}"]`).textContent = n === list.length ? `all ${n}` : `${n} of ${list.length}`;
    document.querySelector(`[data-jump="${id}"]`).textContent = n;
    const chip = document.createElement("span");
    chip.append(`${SOURCE_NAMES[id]} `, Object.assign(document.createElement("b"), { textContent: n }));
    split.push(chip);
  }
  $("split").replaceChildren(...split);
  const name = $("gitname").value.trim();
  $("you-badge").textContent = name && ok.cmd ? name : "optional";

  const preset = matchingPreset(on);
  document.querySelectorAll('input[name="preset"]').forEach((r) => { r.checked = r.value === preset; });

  const state = { picked: on, release: $("release").checked };
  for (const id of FIELDS) state[id] = $(id).value;
  save(state);
}

let toastTimer;
function toast(text) {
  const t = $("toast");
  t.querySelector("span").textContent = text;
  t.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("on"), 2600);
}

let copiedTimer;
async function copy() {
  const btn = $("copy-cmd");
  try {
    await navigator.clipboard.writeText($("cmd").textContent);
    $("cmd-status").textContent = "";
    btn.classList.add("copied");
    clearTimeout(copiedTimer);
    copiedTimer = setTimeout(() => btn.classList.remove("copied"), 2000);
    toast("Copied. Paste it into the new computer's terminal.");
  } catch {
    const range = document.createRange();
    range.selectNodeContents($("cmd"));
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    $("cmd-status").textContent = "Selected: press Ctrl+C to copy.";
  }
}

// Light or dark: the switch flips whatever is showing now and remembers it.
function setupTheme() {
  $("theme").addEventListener("click", () => {
    const dark = getComputedStyle(document.documentElement).colorScheme.includes("dark");
    const next = dark ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem(THEME, next); } catch { /* fine */ }
  });
}

// "/" jumps to the app search; Escape clears it.
function setupKeys() {
  addEventListener("keydown", (e) => {
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName);
    if (e.key === "/" && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault();
      $("filter").focus();
      $("filter").scrollIntoView({ block: "center", behavior: CALM ? "auto" : "smooth" });
    } else if (e.key === "Escape" && document.activeElement === $("filter")) {
      $("filter").value = "";
      filter();
    }
  });
}

// The top bar shows which section you're in.
function setupScroll() {
  if (!("IntersectionObserver" in window)) return;
  const links = [...document.querySelectorAll("[data-spy]")];
  const spy = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      links.forEach((a) => a.classList.toggle("on", a.dataset.spy === e.target.id));
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  links.forEach((a) => { const t = $(a.dataset.spy); if (t) spy.observe(t); });

  // The top bar gets a backing once the page moves under it.
  const nav = document.querySelector(".nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 30);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Phones: hide the "Get your installer" bar while the installer is on screen.
  new IntersectionObserver(([e]) => { document.querySelector(".mbar").hidden = e.isIntersecting; }).observe($("installer"));
}

// The hero's numbers count up once.
function countUp() {
  const items = allItems().length;
  const sources = LISTS.length - 1;
  document.querySelectorAll("[data-count]").forEach((el) => {
    const target = el.dataset.count === "items" ? items : sources;
    if (CALM) { el.textContent = target; return; }
    const start = performance.now(), dur = 1100;
    const step = (now) => {
      const t = Math.min(1, (now - start) / dur);
      el.textContent = Math.round(target * (1 - Math.pow(1 - t, 3)));
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });
}

// The hero terminal types the command and plays a short, made-up run of the setup.
function demo() {
  const pre = $("demo");
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const line = (parts) => parts.map(([t, c]) => (c ? `<span class="${c}">${esc(t)}</span>` : esc(t))).join("");
  const typed = "bash <(wget -qO- https://…/dotfiles/main/bootstrap.sh)";
  const groups = data.groups.filter((g) => g.default !== false).slice(0, 6);
  const apps = data.apps.length + data.ubuntu.length + data.flatpaks.length;
  const out = [
    line([["Checking this computer… ", "dim"], ["Ubuntu 26.04, GNOME ", ""], ["✔", "ok"]]),
    line([["Installing git, gum and gh…", "dim"]]),
    ...groups.map((g) => {
      const d = (g.desc || "").split(/[;(]/)[0].trim();
      return line([["✔ ", "ok"], [g.name, "hl"], ["  " + (d.length > 40 ? d.slice(0, 38).replace(/[ ,]+\S*$/, "") + "…" : d), "dim"]]);
    }),
    line([["✔ ", "ok"], [`${apps} apps`, "hl"], [" from their makers, Ubuntu and Flathub", "dim"]]),
    "",
    line([["All done. ", "ok"], ["Restarting in 10 s…", "warn"]]),
  ];
  const prompt = '<span class="p">❯</span> ';
  if (CALM) { pre.innerHTML = prompt + esc(typed) + "\n" + out.join("\n") + "\n" + prompt; return; }

  let i = 0;
  const caret = '<span class="caret"></span>';
  const type = () => {
    pre.innerHTML = prompt + esc(typed.slice(0, i)) + caret;
    if (i++ < typed.length) return setTimeout(type, 28 + Math.random() * 40);
    setTimeout(() => run(0), 450);
  };
  const run = (n) => {
    pre.innerHTML = prompt + esc(typed) + "\n" + out.slice(0, n).join("\n") + (n < out.length ? "\n" + caret : "\n" + prompt + caret);
    if (n < out.length) setTimeout(() => run(n + 1), n < 2 ? 520 : 300);
  };
  setTimeout(type, 600);
}

// --- The docs: one page at a time, with links between pages and to their headings ---
// An address like #doc-maintenance-health-check opens that page at that heading.
function renderDocs(json) {
  const body = $("doc-body"), tabs = $("doc-tabs");
  const pages = json.pages;
  body.replaceChildren(...pages.map((p, n) => {
    const page = document.createElement("div");
    page.className = "doc-page";
    page.id = `doc-${p.id}`;
    page.hidden = true;
    page.dataset.toc = JSON.stringify(p.toc);
    const h1 = Object.assign(document.createElement("h1"), { textContent: p.title });
    const src = document.createElement("p");
    src.className = "doc-src";
    src.append("From ", Object.assign(document.createElement("a"), { href: p.source, textContent: p.source.split("/blob/main/")[1] }), " on GitHub");
    const content = document.createElement("div");
    content.innerHTML = p.html; // built by build-site.py from the repo's own files
    const pager = document.createElement("nav");
    pager.className = "doc-pager";
    pager.setAttribute("aria-label", "Previous and next page");
    for (const [q, cls, word] of [[pages[n - 1], "prev", "Previous"], [pages[n + 1], "next", "Next"]]) {
      if (!q) continue;
      const a = Object.assign(document.createElement("a"), { href: `#doc-${q.id}`, className: cls });
      a.append(Object.assign(document.createElement("small"), { textContent: word }), Object.assign(document.createElement("b"), { textContent: q.title }));
      pager.append(a);
    }
    page.append(h1, src, content, pager);
    return page;
  }));
  tabs.replaceChildren(...pages.map((p) => Object.assign(document.createElement("a"), { href: `#doc-${p.id}`, textContent: p.tab })));

  // A copy button on each command block
  body.querySelectorAll("pre.lang-bash").forEach((pre) => {
    const btn = Object.assign(document.createElement("button"), { type: "button", className: "copy-code", textContent: "Copy" });
    btn.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(pre.querySelector("code").textContent); toast("Copied."); }
      catch { getSelection().selectAllChildren(pre.querySelector("code")); toast("Selected: press Ctrl+C to copy."); }
    });
    pre.append(btn);
  });

  // Links to a page or heading: open that page, and remember it in the address (Back works).
  $("docs").addEventListener("click", (e) => {
    const a = e.target.closest('a[href^="#doc-"]');
    if (!a || e.ctrlKey || e.metaKey || e.shiftKey) return;
    e.preventDefault();
    const id = a.getAttribute("href").slice(1);
    if (showDoc(id, true)) history.pushState(null, "", "#" + id);
  });
  addEventListener("popstate", () => {
    const id = location.hash.slice(1);
    if (id.startsWith("doc-")) showDoc(id, true);
  });
  showDoc(`doc-${pages[0].id}`, false);
}

// showDoc <id> <scroll>: show the page holding that id, and scroll to it if asked.
function showDoc(id, scroll) {
  const target = document.getElementById(id);
  const page = target?.closest(".doc-page");
  if (!page) return false;
  document.querySelectorAll(".doc-page").forEach((p) => { p.hidden = p !== page; });
  $("doc-tabs").querySelectorAll("a").forEach((a) => {
    if (a.getAttribute("href") === "#" + page.id) {
      a.setAttribute("aria-current", "page");
      const strip = $("doc-tabs"); // on phones the tabs scroll sideways: bring this one into view
      strip.scrollTo({ left: a.offsetLeft - strip.offsetLeft - 8 });
    }
    else a.removeAttribute("aria-current");
  });
  const toc = JSON.parse(page.dataset.toc);
  $("doc-toc").replaceChildren(...(toc.length ? [Object.assign(document.createElement("b"), { textContent: "On this page" })] : []),
    ...toc.map((t) => Object.assign(document.createElement("a"), { href: "#" + t.id, innerHTML: t.text })));
  // Instant: the page under you has just changed, and a smooth scroll across it takes seconds.
  if (scroll) {
    (target === page ? $("docs-cols") : target).scrollIntoView({ behavior: "instant" });
    // The top bar's marker may not see a jump this big as crossing into the docs
    document.querySelectorAll("[data-spy]").forEach((a) => a.classList.toggle("on", a.dataset.spy === "docs"));
  }
  return true;
}

const docsReady = fetch("docs.json")
  .then((r) => r.json())
  .then(renderDocs)
  .catch(() => {
    const p = document.createElement("p");
    p.className = "empty";
    p.append("Couldn't load the docs. Reload the page, or read them ",
      Object.assign(document.createElement("a"), { href: "https://github.com/ronaldo-kwan/dotfiles#readme", textContent: "on GitHub" }), ".");
    $("doc-body").replaceChildren(p);
  });

setupTheme();
setupKeys();
setupScroll();

fetch("options.json")
  .then((r) => r.json())
  .then((json) => {
    data = json;
    build(load());
    $("copy-cmd").addEventListener("click", copy);
    $("reset").addEventListener("click", () => { save({}); location.reload(); });
    update();
    countUp();
    demo();
    // A link to a section (#sec-apps) or a doc (#doc-apps-steam): jump again now the lists
    // and the docs are filled in and the page is its full height.
    docsReady.then(() => {
      const id = location.hash.slice(1);
      if (id.startsWith("doc-")) showDoc(id, true);
      else if (id && document.getElementById(id)) document.getElementById(id).scrollIntoView();
    });
  })
  .catch(() => {
    paint($("cmd"), [["Couldn't load the options. Reload the page.", "t-err"]]);
    $("cmd-status").textContent = "Couldn't load the options.";
    $("cmd-status").classList.add("bad");
  });
