// The dotfiles installer page: builds the option lists from options.json (generated from
// the repo by scripts/build-site.py), and turns the picks into a one-line command and an
// autoinstall.yaml. Runs entirely in the browser.
"use strict";

const $ = (id) => document.getElementById(id);
const STORE = "dotfiles-site-v1";
let data;

// Shell single-quoting: 'it'\''s'
const sq = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
const b64 = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));

function option(item, checked) {
  const label = document.createElement("label");
  label.className = "opt";
  const box = document.createElement("input");
  box.type = "checkbox";
  box.value = item.token;
  box.checked = checked;
  box.addEventListener("change", update);
  const text = document.createElement("span");
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
  const isOn = (item) => (picked ? picked.has(item.token) : item.default !== false);
  for (const [id, list] of [["groups", data.groups], ["apps", data.apps], ["ubuntu", data.ubuntu], ["flatpaks", data.flatpaks]]) {
    const box = $(id);
    box.replaceChildren(...list.map((item) => option(item, isOn(item))));
  }
  document.querySelectorAll(".mini").forEach((span) => {
    const list = span.dataset.list;
    for (const [word, value] of [["All", true], ["None", false]]) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = word;
      btn.addEventListener("click", () => {
        $(list).querySelectorAll("input").forEach((i) => { i.checked = value; });
        update();
      });
      span.append(btn);
    }
  });
  for (const id of ["gitname", "gitemail", "locale", "keyboard", "timezone"]) {
    if (saved[id] !== undefined) $(id).value = saved[id];
    $(id).addEventListener("input", update);
  }
  if (!$("timezone").value) {
    $("timezone").value = Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC";
  }
}

// Check the typed fields; returns false (and shows why) if something can't be used.
function validate() {
  const rules = {
    gitname: [(v) => !/[\n\r]/.test(v), "One line, please."],
    gitemail: [(v) => v === "" || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), "That doesn't look like an email address."],
    locale: [(v) => /^[A-Za-z]{2,3}(_[A-Z]{2})?(\.UTF-8)?$/.test(v), "Like en_US.UTF-8 or de_DE.UTF-8."],
    keyboard: [(v) => /^[a-z]{2,8}$/.test(v), "A layout code, like us, gb or de."],
    timezone: [(v) => /^[A-Za-z_]+(\/[A-Za-z0-9_+-]+){0,2}$/.test(v), "Like Europe/Berlin or America/New_York."],
  };
  let ok = true;
  for (const [id, [test, msg]] of Object.entries(rules)) {
    const good = test($(id).value.trim());
    $(id).setAttribute("aria-invalid", String(!good));
    $(id + "-err").textContent = good ? "" : msg;
    ok = ok && good;
  }
  const name = $("gitname").value.trim(), email = $("gitemail").value.trim();
  if ((name === "") !== (email === "")) {
    $((name ? "gitemail" : "gitname") + "-err").textContent = "Fill in both, or neither.";
    ok = false;
  }
  return ok;
}

function picks() {
  const all = [...document.querySelectorAll("main input[type=checkbox]")];
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

function command(vars) {
  const prefix = vars.map(([k, v]) => `${k}=${sq(v)} `).join("");
  return `${prefix}bash <(wget -qO- ${data.raw}/bootstrap.sh)`;
}

// The picks in words, for comments in autoinstall.yaml (lines of up to ~84 characters).
function describe(vars) {
  const names = new Map([...data.groups, ...data.apps, ...data.ubuntu, ...data.flatpaks]
    .map((i) => [i.token, i.name]));
  const v = Object.fromEntries(vars);
  const wrap = (head, items) => {
    const lines = [];
    let line = head;
    for (const [n, item] of items.entries()) {
      const piece = item + (n < items.length - 1 ? ", " : ".");
      if ((line + piece).length > 84) { lines.push(line.trimEnd()); line = "  "; }
      line += piece;
    }
    return [...lines, line];
  };
  const out = [];
  if (v.DOTFILES_SKIP) out.push(...wrap("Your choices: everything except ", v.DOTFILES_SKIP.split(" ").map((t) => names.get(t) || t)));
  if (v.DOTFILES_CHOICES) out.push(...wrap("Your choices: only ", v.DOTFILES_CHOICES.split(" ").map((t) => names.get(t) || t)));
  if (v.DOTFILES_GIT_NAME) out.push(`Git commits by: ${v.DOTFILES_GIT_NAME} <${v.DOTFILES_GIT_EMAIL}>`);
  return out;
}

function autoinstall(vars) {
  let y = data.autoinstall
    .replace(/^(\s*locale:).*$/m, `$1 ${$("locale").value.trim()}`)
    .replace(/^(\s*layout:).*$/m, `$1 ${$("keyboard").value.trim()}`)
    .replace(/^(\s*timezone:).*$/m, `$1 ${$("timezone").value.trim()}`)
    .replace(/^#cloud-config\n# Automated install[^]*?give it this file's address:\n#.*\n/,
      `#cloud-config\n# Made on the dotfiles website on ${new Date().toISOString().slice(0, 10)}. Put it online (for example\n` +
      "# a secret gist), choose the automated installation in the Ubuntu installer, and give it\n# the file's Raw address.\n");
  // Codecs during the install only if ubuntu-restricted-extras is ticked.
  const codecs = document.querySelector('input[value="pkg:ubuntu-restricted-extras"]');
  if (codecs && !codecs.checked) {
    y = y.replace(/^(\s*codecs:\n\s*install:) true.*$/m, "$1 false   # media codecs (unticked on the website)");
  }
  if (vars.length) {
    // What you picked, for the first-login setup (read from /etc/dotfiles-choices). It's
    // encoded so names with quotes can't break the YAML; the comments say it in words.
    const file = vars.map(([k, v]) => `${k}=${sq(v)}`).join("\n") + "\n";
    y = y.trimEnd() + "\n" + describe(vars).map((l) => `    # ${l}\n`).join("") +
      "    # (The line below holds exactly this, encoded; it's removed once the setup starts.)\n" +
      `    - curtin in-target -- sh -c 'echo ${b64(file)} | base64 -d > /etc/dotfiles-choices'\n`;
  }
  return y;
}

function update() {
  const { all, on, off } = picks();
  const ok = validate();
  const vars = settings(on, all.length, off);
  $("cmd").textContent = ok ? command(vars) : "Fix the highlighted fields above first.";
  $("yaml").textContent = ok ? autoinstall(vars) : "";
  $("copy-cmd").disabled = $("dl-yaml").disabled = !ok;
  $("count").textContent = on.length === all.length ? `Everything (${all.length} items)` : `${on.length} of ${all.length} picked`;
  $("copied").textContent = "";
  const state = { picked: on };
  for (const id of ["gitname", "gitemail", "locale", "keyboard", "timezone"]) state[id] = $(id).value;
  save(state);
}

async function copy() {
  try {
    await navigator.clipboard.writeText($("cmd").textContent);
    $("copied").textContent = "Copied. Paste it into the new computer's terminal.";
  } catch {
    const range = document.createRange();
    range.selectNodeContents($("cmd"));
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    $("copied").textContent = "Selected: press Ctrl+C to copy.";
  }
}

function download() {
  const blob = new Blob([$("yaml").textContent], { type: "text/yaml" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "autoinstall.yaml";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

fetch("options.json")
  .then((r) => r.json())
  .then((json) => {
    data = json;
    build(load());
    $("copy-cmd").addEventListener("click", copy);
    $("dl-yaml").addEventListener("click", download);
    $("reset").addEventListener("click", () => { save({}); location.reload(); });
    update();
  })
  .catch(() => { $("cmd").textContent = "Couldn't load the options. Reload the page."; });
