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

// "/" jumps to the app search (or the docs search, in the docs); Escape clears it.
function setupKeys() {
  addEventListener("keydown", (e) => {
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName);
    if (e.key === "/" && !typing && !e.ctrlKey && !e.metaKey && !e.altKey && docsInView()) {
      e.preventDefault();
      if ($("doc-menu").offsetParent) { $("doc-side").classList.add("open"); $("doc-menu").setAttribute("aria-expanded", "true"); }
      $("doc-q").focus();
    } else if (e.key === "/" && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) {
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
const GH_ICON = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.41-2.7 5.38-5.26 5.67.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5Z"/></svg>';
const COPY_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/></svg>';
const CHECK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
const el = (tag, props = {}, ...kids) => { const e = Object.assign(document.createElement(tag), props); e.append(...kids); return e; };
const docs = { pages: [], index: [], current: null, toc: [] };
// A heading's text, without its # link
const headText = (h) => [...h.childNodes].filter((n) => !n.classList?.contains("anchor")).map((n) => n.textContent).join("").trim();

function renderDocs(json) {
  docs.pages = json.pages;
  $("doc-body").replaceChildren(...docs.pages.map((p, n) => {
    const content = el("div", { className: "doc-content" });
    content.innerHTML = p.html; // built by build-site.py from the repo's own files
    const src = el("p", { className: "doc-src" });
    src.innerHTML = GH_ICON;
    src.append(el("a", { href: p.source, textContent: p.source.split("/blob/main/")[1] }), " on GitHub");
    const pager = el("nav", { className: "doc-pager" });
    pager.setAttribute("aria-label", "Previous and next page");
    for (const [q, cls, word] of [[docs.pages[n - 1], "prev", "← Previous"], [docs.pages[n + 1], "next", "Next →"]]) {
      if (q) pager.append(el("a", { href: `#doc-${q.id}`, className: cls }, el("small", { textContent: word }), el("b", { textContent: q.title })));
    }
    const page = el("div", { className: "doc-page", id: `doc-${p.id}`, hidden: true },
      el("p", { className: "doc-crumb", textContent: `Docs · ${n + 1} of ${docs.pages.length}` }), el("h1", { textContent: p.title }), src, content, pager);
    // Headings get a link to themselves; headings inside a closed <details> stay out of the contents.
    page.querySelectorAll("h2[id], h3[id]").forEach((h) => {
      const a = el("a", { className: "anchor", href: "#" + h.id, textContent: "#" });
      a.setAttribute("aria-label", `Link to this section: ${h.textContent}`);
      a.dataset.anchor = "";
      h.append(a);
      h.tabIndex = -1; // so a jump can move the keyboard focus there
    });
    page.dataset.toc = JSON.stringify(p.toc.filter((t) => !page.querySelector("#" + CSS.escape(t.id))?.closest("details")));
    return page;
  }));
  $("doc-pages").replaceChildren(...docs.pages.map((p) => el("li", {}, el("a", { href: `#doc-${p.id}`, textContent: p.title }))));

  // Copy buttons on command blocks
  $("doc-body").querySelectorAll("pre.lang-bash").forEach((pre) => {
    const btn = el("button", { type: "button", className: "copy-code" });
    const idle = () => { btn.innerHTML = COPY_ICON + "<span>Copy</span>"; btn.classList.remove("done"); };
    idle();
    btn.setAttribute("aria-label", "Copy these commands");
    let timer;
    btn.addEventListener("click", async () => {
      const code = pre.querySelector("code");
      try {
        await navigator.clipboard.writeText(code.textContent);
        btn.innerHTML = CHECK_ICON + "<span>Copied</span>";
        btn.classList.add("done");
        toast("Copied.");
      } catch { getSelection().selectAllChildren(code); toast("Selected: press Ctrl+C to copy."); }
      clearTimeout(timer);
      timer = setTimeout(idle, 1800);
    });
    pre.append(btn);
  });

  buildIndex();
  setupDocNav();
  showDoc(`doc-${docs.pages[0].id}`, false);
}

// showDoc <id> <scroll>: show the page holding that id, and scroll to it if asked.
function showDoc(id, scroll) {
  const target = document.getElementById(id);
  const page = target?.closest(".doc-page");
  if (!page) return false;
  if (docs.current !== page) {
    document.querySelectorAll(".doc-page").forEach((p) => { p.hidden = p !== page; });
    docs.current = page;
    docs.toc = JSON.parse(page.dataset.toc);
    const info = docs.pages.find((p) => `doc-${p.id}` === page.id);
    const toc = docs.toc;
    const tocItems = () => toc.map((t) => {
      const a = el("a", { href: "#" + t.id });
      a.innerHTML = t.text;
      a.dataset.to = t.id;
      return el("li", { className: "l" + t.level }, a);
    });
    $("doc-pages").querySelectorAll(":scope > li").forEach((li) => {
      const a = li.firstElementChild, on = a.getAttribute("href") === "#" + page.id;
      on ? a.setAttribute("aria-current", "page") : a.removeAttribute("aria-current");
      li.querySelector(".doc-sub")?.remove();
      if (on && toc.length) li.append(el("ul", { className: "doc-sub" }, ...tocItems()));
    });
    $("doc-toc").replaceChildren(...tocItems());
    $("doc-aside").hidden = !toc.length;
    $("doc-gh").href = info.source;
    $("doc-menu-page").textContent = info.title;
  }
  target.closest("details:not([open])")?.setAttribute("open", "");
  // Instant: the page under you has just changed, and a smooth scroll across it takes seconds.
  if (scroll) {
    (target === page ? $("docs-cols") : target).scrollIntoView({ behavior: "instant" });
    // The top bar's marker may not see a jump this big as crossing into the docs
    document.querySelectorAll("[data-spy]").forEach((a) => a.classList.toggle("on", a.dataset.spy === "docs"));
  }
  spyDoc();
  return true;
}

// The heading you're reading, marked in the contents (and named on the phone menu button).
function spyDoc() {
  const page = docs.current;
  if (!page) return;
  const line = ($("doc-menu").offsetParent ? $("doc-side").getBoundingClientRect().bottom : 84) + 24;
  let on = null;
  for (const t of docs.toc) {
    const h = document.getElementById(t.id);
    if (h && h.getBoundingClientRect().top <= line) on = t; else if (h) break;
  }
  document.querySelectorAll("#doc-pages a[data-to], #doc-toc a").forEach((a) => {
    const is = on && a.dataset.to === on.id;
    a.classList.toggle("on", !!is);
    is ? a.setAttribute("aria-current", "location") : a.removeAttribute("aria-current");
  });
  $("doc-menu-sec").textContent = on ? headText(document.getElementById(on.id)) : "";
  // Keep the marked heading in view in the scrolling lists
  for (const box of [$("doc-nav"), $("doc-aside")]) {
    const a = box.querySelector("a.on");
    if (!a || box.scrollHeight <= box.clientHeight) continue;
    if (a.offsetTop < box.scrollTop + 40 || a.offsetTop > box.scrollTop + box.clientHeight - 60) box.scrollTop = a.offsetTop - box.clientHeight / 3;
  }
}

// The search: every section (a page's heading and the text under it), ranked by where the words are.
function buildIndex() {
  docs.index = [];
  document.querySelectorAll(".doc-page").forEach((page) => {
    const info = docs.pages.find((p) => `doc-${p.id}` === page.id);
    let sec = { page: info.title, id: page.id, title: info.title, text: "" };
    docs.index.push(sec);
    const walk = (parent) => {
      for (const node of parent.children) {
        if (/^H[23]$/.test(node.tagName)) {
          sec = { page: info.title, id: node.id, title: headText(node), text: "" };
          docs.index.push(sec);
        } else if (node.tagName === "DETAILS") walk(node);
        else sec.text += " " + node.textContent.replace(/\s+/g, " ").trim();
      }
    };
    walk(page.querySelector(".doc-content"));
  });
  for (const s of docs.index) { s.hay = (s.title + " " + s.text).toLowerCase(); s.text = s.text.trim(); }
}

function searchDocs(q) {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const box = $("doc-results");
  box.hidden = !words.length;
  $("doc-pages").hidden = !!words.length;
  if (!words.length) { $("doc-q-status").textContent = ""; return; }
  const hits = docs.index
    .filter((s) => words.every((w) => s.hay.includes(w)))
    .map((s, n) => ({ s, n, score: words.reduce((sum, w) => sum + (s.title.toLowerCase().includes(w) ? 10 : 0) + Math.min(5, s.hay.split(w).length - 1), 0) }))
    .sort((a, b) => b.score - a.score || a.n - b.n)
    .slice(0, 20);
  const mark = (text) => {
    const re = new RegExp(`(${words.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})`, "gi");
    return text.split(re).map((part, i) => (i % 2 ? el("mark", { textContent: part }) : document.createTextNode(part)));
  };
  const snippet = (text) => {
    const at = Math.max(0, ...[text.toLowerCase().indexOf(words.find((w) => text.toLowerCase().includes(w)) ?? "")]);
    let from = Math.max(0, at - 50), to = Math.min(text.length, at + 110);
    if (from > 0) from = text.indexOf(" ", from) + 1;
    if (to < text.length) to = text.lastIndexOf(" ", to);
    return (from > 0 ? "…" : "") + text.slice(from, to) + (to < text.length ? "…" : "");
  };
  box.replaceChildren(
    el("p", { textContent: hits.length ? `${hits.length}${hits.length === 20 ? "+" : ""} result${hits.length === 1 ? "" : "s"}` : `Nothing found for “${q.trim()}”.` }),
    ...hits.map(({ s }) => el("a", { href: "#" + s.id }, el("small", { textContent: s.page }), el("b", {}, ...mark(s.title)),
      ...(s.text ? [el("span", {}, ...mark(snippet(s.text)))] : []))));
  $("doc-q-status").textContent = hits.length ? `${hits.length} results` : "No results";
}

function setupDocNav() {
  const side = $("doc-side"), menu = $("doc-menu"), q = $("doc-q");
  const openMenu = (open) => {
    side.classList.toggle("open", open);
    menu.setAttribute("aria-expanded", String(open));
  };
  menu.addEventListener("click", () => {
    const open = !side.classList.contains("open");
    openMenu(open);
    if (open) (q.value ? q : $("doc-nav").querySelector('[aria-current="page"]') || q).focus();
  });
  document.addEventListener("click", (e) => { if (side.classList.contains("open") && !side.contains(e.target)) openMenu(false); });
  side.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && side.classList.contains("open")) { openMenu(false); menu.focus(); }
  });

  // Links to a page or heading: open that page, and remember it in the address (Back works).
  // A heading's own # link also copies the address.
  $("docs").addEventListener("click", (e) => {
    const a = e.target.closest('a[href^="#doc-"]');
    if (!a || e.ctrlKey || e.metaKey || e.shiftKey) return;
    e.preventDefault();
    const id = a.getAttribute("href").slice(1);
    if (!showDoc(id, true)) return;
    history.pushState(null, "", "#" + id);
    openMenu(false);
    if (a.dataset.anchor !== undefined) navigator.clipboard?.writeText(location.href).then(() => toast("Link copied."), () => {});
    // Keyboard users land on what they picked
    const target = document.getElementById(id);
    const land = target.matches(".doc-page") ? target.querySelector("h1") : target;
    land.tabIndex = -1;
    land.focus({ preventScroll: true });
  });
  addEventListener("popstate", () => {
    const id = location.hash.slice(1);
    if (id.startsWith("doc-")) showDoc(id, true);
  });

  q.addEventListener("input", () => searchDocs(q.value));
  q.addEventListener("keydown", (e) => {
    const first = $("doc-results").querySelector("a");
    if (e.key === "ArrowDown" && first) { e.preventDefault(); first.focus(); }
    else if (e.key === "Enter" && first) { e.preventDefault(); first.click(); }
    else if (e.key === "Escape" && q.value) { e.stopPropagation(); q.value = ""; searchDocs(""); }
  });
  $("doc-results").addEventListener("keydown", (e) => {
    const links = [...$("doc-results").querySelectorAll("a")], i = links.indexOf(document.activeElement);
    if (e.key === "ArrowDown" && i < links.length - 1) { e.preventDefault(); links[i + 1].focus(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); (i > 0 ? links[i - 1] : q).focus(); }
  });

  let ticking = false;
  addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { ticking = false; spyDoc(); });
  }, { passive: true });
  addEventListener("resize", spyDoc, { passive: true });
}

// "/" goes to the docs search while you're in the docs
function docsInView() {
  const r = $("docs").getBoundingClientRect();
  return docs.pages.length > 0 && r.top < innerHeight / 2 && r.bottom > innerHeight / 2;
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
