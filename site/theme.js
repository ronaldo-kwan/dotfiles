// Loaded in <head> by both pages, before anything is drawn: the saved light/dark choice is
// put on the page first, so it doesn't flash the other theme. Without a saved choice, the
// system's is used (style.css). A file, not inline, so the pages' Content-Security-Policy
// can allow only scripts from the site itself.
"use strict";
try { const t = localStorage.getItem("dotfiles-site-theme"); if (t) document.documentElement.dataset.theme = t; } catch { /* storage blocked: the system's theme */ }
