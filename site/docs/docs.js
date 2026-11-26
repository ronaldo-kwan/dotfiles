// The docs site: the pages from docs.json (made by scripts/build-site.py from README.md, docs/
// and the dot command's own help), one at a time. An address like #maintenance-health-check
// opens that page at that heading. Uses common.js (loaded first): $, CALM, toast, the theme.
"use strict";

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
      if (q) pager.append(el("a", { href: `#${q.id}`, className: cls }, el("small", { textContent: word }), el("b", { textContent: q.title })));
    }
    const page = el("div", { className: "doc-page", id: p.id, hidden: true },
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
  $("doc-pages").replaceChildren(...docs.pages.map((p) => el("li", {}, el("a", { href: `#${p.id}`, textContent: p.title }))));

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
  // The page (and heading) in the address, else the first page
  const id = location.hash.slice(1);
  if (!showDoc(id, true)) showDoc(docs.pages[0].id, false);
}

// showDoc <id> <scroll>: show the page holding that id, and scroll to it if asked.
function showDoc(id, scroll) {
  const target = id ? document.getElementById(id) : null;
  const page = target?.closest(".doc-page");
  if (!page) return false;
  const samePage = docs.current === page;
  if (!samePage) {
    document.querySelectorAll(".doc-page").forEach((p) => { p.hidden = p !== page; });
    docs.current = page;
    docs.toc = JSON.parse(page.dataset.toc);
    const info = docs.pages.find((p) => p.id === page.id);
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
    document.title = `${info.title} · Dotfiles docs`;
  }
  target.closest("details:not([open])")?.setAttribute("open", "");
  // Smooth within the page you're reading. Instant when the page under you has just changed
  // (a smooth scroll across it takes seconds), and with reduced motion.
  const behavior = samePage && !CALM ? "smooth" : "instant";
  if (scroll) target === page ? scrollTo({ top: 0, behavior }) : target.scrollIntoView({ behavior });
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
    const info = docs.pages.find((p) => p.id === page.id);
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
  document.addEventListener("click", (e) => {
    const a = e.target.closest('a[href^="#"]');
    if (!a || e.ctrlKey || e.metaKey || e.shiftKey) return;
    const id = a.getAttribute("href").slice(1);
    if (!document.getElementById(id)?.closest(".doc-page")) return;
    e.preventDefault();
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
  addEventListener("popstate", () => { showDoc(location.hash.slice(1) || docs.pages[0].id, true); });

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

// "/" goes to the search (on phones, in the menu)
function setupKeys() {
  addEventListener("keydown", (e) => {
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName);
    if (e.key !== "/" || typing || e.ctrlKey || e.metaKey || e.altKey) return;
    e.preventDefault();
    if ($("doc-menu").offsetParent) { $("doc-side").classList.add("open"); $("doc-menu").setAttribute("aria-expanded", "true"); }
    $("doc-q").focus();
  });
}

setupTheme();
setupNav();
setupKeys();
fetch("docs.json")
  .then((r) => r.json())
  .then(renderDocs)
  .catch(() => {
    $("doc-body").replaceChildren(el("p", { className: "empty" }, "Couldn't load the docs. Reload the page, or read them ",
      el("a", { href: "https://github.com/ronaldo-kwan/dotfiles#readme", textContent: "on GitHub" }), "."));
  });
