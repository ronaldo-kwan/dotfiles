// The dotfiles installer page: builds the option lists from options.json (generated from
// the repo by scripts/build-site.py), and turns the picks into a one-line command. Runs
// entirely in the browser.
"use strict";

const $ = (id) => document.getElementById(id);
const STORE = "dotfiles-site-v1";
const LISTS = ["groups", "apps", "ubuntu", "flatpaks"];
const FIELDS = ["gitname", "gitemail"];
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

function option(item, checked) {
  const label = document.createElement("label");
  label.className = "row";
  label.dataset.search = `${item.name} ${item.desc || ""} ${item.token}`.toLowerCase();
  const box = document.createElement("input");
  box.type = "checkbox";
  box.className = "switch";
  box.value = item.token;
  box.checked = checked;
  box.addEventListener("change", update);
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
  label.append(box, text);
  return label;
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
        $(list).querySelectorAll("input.switch").forEach((i) => { if (!i.closest(".row").hidden) i.checked = value; });
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
      boxes().forEach((b) => { b.checked = on.has(b.value); });
      update();
    });
  });

  for (const id of FIELDS) {
    if (saved[id] !== undefined) $(id).value = saved[id];
    $(id).addEventListener("input", update);
  }
  if (saved.gitname || saved.gitemail) $("sec-you").open = true;

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
  return vars;
}

// --yes: the picks on this page are the answers, so setup doesn't ask how to answer.
function command(vars) {
  const prefix = vars.map(([k, v]) => `${k}=${sq(v)} `).join("");
  return `${prefix}bash <(wget -qO- ${data.raw}/bootstrap.sh) --yes`;
}

// Which preset the current picks match, if any.
function matchingPreset(on) {
  const set = new Set(on);
  for (const [name, rule] of Object.entries(PRESETS)) {
    if (allItems().every((i) => rule(i) === set.has(i.token))) return name;
  }
  return "custom";
}

function update() {
  const { all, on, off } = picks();
  const ok = validate();
  const vars = settings(on, all.length, off);

  $("cmd").textContent = ok.cmd ? command(vars) : "Fix your name and email for git first (on the left).";
  $("copy-cmd").disabled = !ok.cmd;
  if (!ok.cmd) $("sec-you").open = true;
  $("cmd-status").textContent = "";
  $("cmd-status").classList.remove("bad");

  // Counts: the panel, the phone bar and each section's badge.
  const summary = on.length === all.length ? `All ${all.length} picked` : `${on.length} of ${all.length} picked`;
  $("count").replaceChildren(Object.assign(document.createElement("strong"), { textContent: summary }));
  $("mcount").textContent = summary;
  for (const id of LISTS) {
    const list = [...$(id).querySelectorAll("input.switch")];
    const n = list.filter((i) => i.checked).length;
    document.querySelector(`[data-badge="${id}"]`).textContent = n === list.length ? `all ${n}` : `${n} of ${list.length}`;
  }
  const name = $("gitname").value.trim();
  $("you-badge").textContent = name && ok.cmd ? name : "optional";

  const preset = matchingPreset(on);
  document.querySelectorAll('input[name="preset"]').forEach((r) => { r.checked = r.value === preset; });

  const state = { picked: on };
  for (const id of FIELDS) state[id] = $(id).value;
  save(state);
}

async function copy() {
  try {
    await navigator.clipboard.writeText($("cmd").textContent);
    $("cmd-status").textContent = "Copied. Paste it into the new computer's terminal.";
  } catch {
    const range = document.createRange();
    range.selectNodeContents($("cmd"));
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    $("cmd-status").textContent = "Selected: press Ctrl+C to copy.";
  }
}

fetch("options.json")
  .then((r) => r.json())
  .then((json) => {
    data = json;
    build(load());
    $("copy-cmd").addEventListener("click", copy);
    $("reset").addEventListener("click", () => { save({}); location.reload(); });
    // Phones: hide the "Get your installer" bar while the installer is on screen.
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([e]) => { document.querySelector(".mbar").hidden = e.isIntersecting; })
        .observe($("installer"));
    }
    update();
  })
  .catch(() => {
    $("cmd").textContent = "Couldn't load the options. Reload the page.";
    $("cmd-status").textContent = "Couldn't load the options.";
    $("cmd-status").classList.add("bad");
  });
