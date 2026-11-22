// Shared by the installer (app.js) and the docs (docs/docs.js), loaded before them: the
// light/dark switch, the toast, and the top bar's backing.
"use strict";

const $ = (id) => document.getElementById(id);
const THEME = "dotfiles-site-theme";
const CALM = matchMedia("(prefers-reduced-motion: reduce)").matches;

let toastTimer;
function toast(text) {
  const t = $("toast");
  t.querySelector("span").textContent = text;
  t.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("on"), 2600);
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

// The top bar gets a backing once the page moves under it.
function setupNav() {
  const nav = document.querySelector(".nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 30);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();
}
