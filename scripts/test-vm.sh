#!/usr/bin/env bash
# Tests the dotfiles like a new computer, in a GNOME Boxes virtual machine: a fresh Ubuntu
# 26.04, the website's command (what's on GitHub: push first), the restart it ends with,
# then dot check. Nothing to click; watch it in Boxes if you like.
#
#   dot vm            test (makes the fresh Ubuntu first, if there isn't one)
#   dot vm --no-cache test, downloading everything again (see "The download cache" below)
#   dot vm create     make the fresh Ubuntu again (about 15 minutes)
#   dot vm open       show the machine in Boxes
#   dot vm delete     remove the machine, its disk and the download cache
# (dot vm runs this script; bash scripts/test-vm.sh works the same.)
#
# The website's choices go in front, like on the website:
#   DOTFILES_CHOICES='terminal desktop' dot vm
# (also DOTFILES_SKIP, DOTFILES_REF, DOTFILES_GIT_NAME and DOTFILES_GIT_EMAIL).
#
# Exits 0 if the setup finished and dot check found nothing wrong except what a new
# computer can't have yet (EXPECTED below), 1 if not. Each run's output and a screenshot
# are kept in ~/.cache/dotfiles-vm/runs/.
#
# The download cache: each test starts from a fresh Ubuntu, so it would download the same
# 2.5 GB of packages every time (the connection is the slow part). A second disk that isn't
# part of the snapshot, dotfiles-test-cache.qcow2, keeps apt's downloads between tests. apt
# still gets the signed package lists and checks every file against them, so the setup is
# the same; only new versions download. --no-cache leaves it out (the makers' servers
# themselves are checked by GitHub's weekly check either way).
#
# How: the Ubuntu installer answers itself (autoinstall), with the answers served from this
# computer for the length of the install. The machine is then kept as a snapshot ("clean"),
# and each test starts from it. Commands get into the machine through qemu-guest-agent, so
# no network setup or SSH is needed. In the machine: user tester, password dotfiles (it
# only exists there), signed in automatically, sudo without a password.
# Needs: GNOME Boxes (Flatpak; dot install adds it), python3, openssl. Uses the Boxes
# Flatpak's own virsh, qemu-img and isoinfo.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib.sh
source "$ROOT/bin/lib.sh"   # header, note, warn, ask, have, fmt_time, C_*

VM=dotfiles-test
# The machine's login: a test value, only in that machine and written in the docs.
GUEST_USER=tester GUEST_PASS=dotfiles
BOXES="$HOME/.var/app/org.gnome.Boxes/data/gnome-boxes"   # where Boxes keeps its disks and ISOs
DISK="$BOXES/images/$VM.qcow2"
CACHE_DISK="$BOXES/images/$VM-cache.qcow2" CACHE_SIZE=40G   # sparse: only what's in it
NO_CACHE=0
WORK="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-vm"        # kernel, answers, runs
UBUNTU_RELEASES=https://releases.ubuntu.com/26.04
# Cores and memory apply to each test (see test_run). 8 cores measured no faster than 4:
# the setup waits on downloads, not on the processor.
MEMORY_MIB=8192 CPUS=4 DISK_SIZE=64G
INSTALL_TIMEOUT=$((90 * 60)) BOOT_TIMEOUT=$((10 * 60)) SETUP_TIMEOUT=$((3 * 60 * 60))
# dot check's ✘ lines a new computer always has, until you do these by hand (the setup's
# own "After the restart" list): they don't fail the test. Patterns for the whole line.
EXPECTED=(
  "^commits aren't signed"                                  # dot ssh, after gh auth login
  "^Obsidian vault not cloned"                              # gh auth login, then dot install
  "^automatic backups haven't run yet"                       # Backups: connect Google Drive
  "^Brave extensions you saved that aren't added here"      # added by hand, from the Web Store
  "^snapshots out of date: apps/brave-settings\.json →"     # the same: its list of extensions
)

ok()  { printf '%s✔%s %s\n' "$C_OK" "$C_N" "$*"; }
die() { printf '%s✘%s %s\n' "$C_ERR" "$C_N" "$*" >&2; exit 1; }
vsh() { flatpak run --command=virsh org.gnome.Boxes -c qemu:///session "$@"; }
in_boxes() { local c="$1"; shift; flatpak run --command="$c" org.gnome.Boxes "$@"; }
exists() { vsh domuuid "$VM" >/dev/null 2>&1; }
state() { vsh domstate "$VM" 2>/dev/null | head -1; }
has_clean() { vsh snapshot-info "$VM" clean >/dev/null 2>&1; }

# --- Talking to the machine (qemu-guest-agent) -------------------------------------------
# guest exec <command> [seconds]: run it in the machine as root; prints its output and
#   returns its exit code (255: the agent didn't answer, 124: it took too long).
# guest ping: is the agent there?
# guest follow <file in the machine> <file here> <seconds>: print the file as it grows (and
#   copy it here) until a line "==> dotfiles-test: exit N" (returns N), the machine stops
#   answering for a minute, as when it restarts (100), or the time is up (124).
# shellcheck disable=SC2016  # Python, not shell
GUEST_PY='
import base64, json, re, subprocess, sys, time
vm, what = sys.argv[1], sys.argv[2]
VIRSH = ["flatpak", "run", "--command=virsh", "org.gnome.Boxes", "-c", "qemu:///session"]
def agent(cmd, **args):
    msg = json.dumps({"execute": cmd, "arguments": args} if args else {"execute": cmd})
    r = subprocess.run(VIRSH + ["qemu-agent-command", vm, msg, "--timeout", "10"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)["return"]
def run(command, timeout):
    started = agent("guest-exec", path="/bin/bash", arg=["-c", command], **{"capture-output": True})
    if started is None:
        return 255, b""
    end = time.time() + timeout
    while time.time() < end:
        st = agent("guest-exec-status", pid=started["pid"])
        if st is None:
            return 255, b""
        if st.get("exited"):
            out = base64.b64decode(st.get("out-data", "")) + base64.b64decode(st.get("err-data", ""))
            return st.get("exitcode", 255), out
        time.sleep(0.5)
    return 124, b""
if what == "ping":
    sys.exit(0 if agent("guest-ping") is not None else 1)
if what == "exec":
    rc, out = run(sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 60)
    sys.stdout.buffer.write(out)
    sys.exit(rc)
if what == "follow":
    path, copy, timeout = sys.argv[3], sys.argv[4], float(sys.argv[5])
    end, offset, silent_since, tail = time.time() + timeout, 0, None, b""
    with open(copy, "ab") as f:
        offset = f.tell()
        while time.time() < end:
            rc, out = run("tail -c +%d %s 2>/dev/null" % (offset + 1, path), 30)
            if rc == 255:
                silent_since = silent_since or time.time()
                if time.time() - silent_since > 60:
                    sys.exit(100)
                time.sleep(3)
                continue
            silent_since = None
            if out:
                sys.stdout.buffer.write(out); sys.stdout.flush()
                f.write(out); f.flush()
                offset += len(out)
                tail = (tail + out)[-4096:]
                m = re.search(rb"==> dotfiles-test: exit (\d+)", tail)
                if m:
                    sys.exit(int(m.group(1)))
            time.sleep(2)
    sys.exit(124)
sys.exit(2)
'
guest() { python3 -I -c "$GUEST_PY" "$VM" "$@"; }

# guest_session <command>: run it as $GUEST_USER inside the desktop session (its systemd
# --user manager, which has GNOME's environment), like a command typed in a terminal.
guest_session() {
  local uid; uid="$(guest exec "id -u $GUEST_USER")" || return 255
  guest exec "runuser -u $GUEST_USER -- env XDG_RUNTIME_DIR=/run/user/$uid \
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus $1" "${2:-60}"
}

# wait_until <seconds> <what> <command...>: until the command succeeds, with a dot a minute.
wait_until() {
  local limit="$1" what="$2" t0=$SECONDS; shift 2
  printf '    %s…%s %s ' "$C_DIM" "$C_N" "$what"
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS - t0 > limit )); then echo; return 1; fi
    (( (SECONDS - t0) % 60 < 5 && SECONDS - t0 > 5 )) && printf '.'
    sleep 5
  done
  printf '%s(%s)%s\n' "$C_DIM" "$(fmt_time $((SECONDS - t0)))" "$C_N"
}
boot_id() { guest exec "cat /proc/sys/kernel/random/boot_id" 15; }   # new on every start
session_ready() { guest_session "systemctl --user show-environment" 20 | grep -q '^WAYLAND_DISPLAY='; }
shut_off() { [[ "$(state)" == "shut off" ]]; }
# Closing the Boxes window saves every running machine (it's then "shut off", with its
# state kept): resume_if_saved starts it again from there, so watching in Boxes and
# closing it doesn't end a test.
saved() { vsh dominfo "$VM" 2>/dev/null | grep -q '^Managed save: *yes'; }
resume_if_saved() {
  shut_off && saved || return 1
  printf '\n'; warn "Boxes saved the machine when its window closed; starting it again from there"
  vsh start "$VM" >/dev/null
}
answers_ping() { resume_if_saved; guest ping; }   # the agent answers (resuming a saved machine first)
# boot: start the machine and wait until you're signed in to the desktop.
boot() {
  shut_off && ! saved && { vsh start "$VM" >/dev/null || die "the machine didn't start"; }
  wait_until "$BOOT_TIMEOUT" "starting" answers_ping || die "no answer from the machine after $(fmt_time "$BOOT_TIMEOUT"); look at it in Boxes"
  wait_until "$BOOT_TIMEOUT" "signing in to the desktop" session_ready || die "the desktop didn't start; look at it in Boxes"
}
fit_machine() {   # this script's cores and memory, from the machine's next start
  vsh setvcpus "$VM" "$CPUS" --config --maximum >/dev/null && vsh setvcpus "$VM" "$CPUS" --config >/dev/null &&
    vsh setmaxmem "$VM" "${MEMORY_MIB}M" --config >/dev/null && vsh setmem "$VM" "${MEMORY_MIB}M" --config >/dev/null
}
power_off() {
  shut_off && return 0
  vsh shutdown "$VM" >/dev/null 2>&1
  wait_until 180 "shutting down" shut_off || { vsh destroy "$VM" >/dev/null 2>&1; shut_off; }
}

# --- The machine --------------------------------------------------------------------------
# domain_xml install|normal [uuid]: the machine's description for libvirt. install boots the
# installer's kernel straight from the ISO, with the autoinstall answers' address; normal
# boots the disk. (Not UEFI: libvirt can't snapshot a machine with UEFI's variable store.)
domain_xml() {
  local phase="$1" uuid="${2:-}" os cdrom
  if [[ "$phase" == install ]]; then
    os="<kernel>$WORK/vmlinuz</kernel><initrd>$WORK/initrd</initrd>
    <cmdline>autoinstall ds=nocloud-net;s=http://10.0.2.2:$ANSWERS_PORT/ --- quiet splash</cmdline>"
    cdrom="<source file='$ISO'/>"
  else
    os="<boot dev='hd'/>"; cdrom=""
  fi
  cat <<EOF
<domain type='kvm'>
  <name>$VM</name>${uuid:+
  <uuid>$uuid</uuid>}
  <title>Dotfiles test</title>
  <description>A fresh Ubuntu 26.04 for testing the dotfiles, made by scripts/test-vm.sh (snapshot "clean": before the dotfiles). User $GUEST_USER, password $GUEST_PASS.</description>
  <memory unit='MiB'>$MEMORY_MIB</memory>
  <vcpu>$CPUS</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    $os
  </os>
  <features><acpi/><apic/></features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>$([[ "$phase" == install ]] && echo destroy || echo restart)</on_reboot>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source file='$DISK'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      $cdrom
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='user'><model type='virtio'/></interface>
    <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
    <channel type='spicevmc'><target type='virtio' name='com.redhat.spice.0'/></channel>
    <input type='tablet' bus='usb'/>
    <graphics type='spice'><listen type='none'/><image compression='off'/><gl enable='no'/></graphics>
    <video><model type='virtio' heads='1' primary='yes'/></video>
    <sound model='ich9'/>
    <audio id='1' type='spice'/>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
  </devices>
</domain>
EOF
}
define() { # define <xml file>
  vsh define "$1" >/dev/null || die "libvirt didn't accept the machine (see above)"
}

# find_iso: the newest Ubuntu 26.04 desktop ISO in Boxes' folder, checked against Ubuntu's
# checksums; offers to download it (about 6 GB) if there's none.
find_iso() {
  local name sums="$BOXES/isos/SHA256SUMS"
  local isos=("$BOXES"/isos/ubuntu-26.04*-desktop-amd64.iso)
  ISO=""; [[ -e "${isos[0]}" ]] && ISO="$(printf '%s\n' "${isos[@]}" | sort -V | tail -1)"
  if [[ -z "$ISO" ]]; then
    mkdir -p "$BOXES/isos"
    curl -fsSL -o "$sums" "$UBUNTU_RELEASES/SHA256SUMS" || die "couldn't reach $UBUNTU_RELEASES"
    name="$(grep -o 'ubuntu-26.04[^ ]*-desktop-amd64.iso' "$sums" | sort -V | tail -1)"
    [[ -n "$name" ]] || die "no desktop ISO listed in $UBUNTU_RELEASES/SHA256SUMS"
    ask "Download $name (about 6 GB) into Boxes' ISO folder?" || die "no Ubuntu ISO to install from"
    curl -fL --progress-bar -o "$BOXES/isos/$name.part" "$UBUNTU_RELEASES/$name" || die "the download failed"
    mv "$BOXES/isos/$name.part" "$BOXES/isos/$name"
    ISO="$BOXES/isos/$name"
  fi
  if [[ -f "$sums" ]] && grep -q " \*\?${ISO##*/}\$" "$sums"; then
    note "Checking ${ISO##*/} against Ubuntu's checksums"
    (cd "$BOXES/isos" && grep " \*\?${ISO##*/}\$" SHA256SUMS | sha256sum -c --quiet) \
      || die "${ISO##*/} doesn't match Ubuntu's checksum: delete it and run this again"
  else
    warn "no SHA256SUMS next to ${ISO##*/}, so it isn't checked"
  fi
}

# answers <folder>: the installer's answers (autoinstall), as cloud-init NoCloud files.
# The late-commands set up what the test needs: the guest agent (installed like the
# installer's own packages, so dot check doesn't count it as an app you added), sudo
# without a password, automatic sign-in, and no welcome wizard on the first sign-in.
answers() {
  local hash kb tz
  hash="$(openssl passwd -6 "$GUEST_PASS")"
  kb="$(localectl status 2>/dev/null | awk -F': ' '/X11 Layout/ {print $2; exit}')"
  tz="$(timedatectl show -p Timezone --value 2>/dev/null)"
  mkdir -p "$1"
  printf 'instance-id: %s-%s\n' "$VM" "$(date +%s)" > "$1/meta-data"
  : > "$1/vendor-data"   # none; without the file, cloud-init asks again for 10 seconds
  cat > "$1/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  interactive-sections: []
  identity:
    realname: Dotfiles Test
    hostname: $VM
    username: $GUEST_USER
    password: '$hash'
  locale: ${LANG:-en_US.UTF-8}
  keyboard: {layout: ${kb:-us}}
  timezone: ${tz:-UTC}
  storage: {layout: {name: direct}}
  updates: security
  codecs: {install: false}
  drivers: {install: false}
  shutdown: poweroff
  late-commands:
    - curtin in-target -- sh -c 'apt-get update -q && apt-get install -y -o Dpkg::Options::=--force-unsafe-io qemu-guest-agent'
    - sh -c 'curtin in-target -- apt-get remove -y gnome-initial-setup || true'
    - sh -c 'echo "$GUEST_USER ALL=(ALL) NOPASSWD:ALL" > /target/etc/sudoers.d/dotfiles-test && chmod 440 /target/etc/sudoers.d/dotfiles-test'
    - sh -c 'printf "# Made by the dotfiles test (scripts/test-vm.sh)\n[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$GUEST_USER\n" > /target/etc/gdm3/custom.conf'
EOF
}

# create: a fresh Ubuntu, installed by itself, kept as the snapshot "clean".
create() {
  local t0=$SECONDS pid uuid
  header "Test machine: a fresh Ubuntu 26.04" "Installs by itself in GNOME Boxes ($VM). About 20 minutes."
  if ! have flatpak || ! flatpak info org.gnome.Boxes >/dev/null 2>&1; then
    die "GNOME Boxes isn't installed: flatpak install flathub org.gnome.Boxes"
  fi
  [[ -w /dev/kvm ]] || die "no access to /dev/kvm (is virtualisation on in the BIOS?)"
  local tool; for tool in python3 openssl; do have "$tool" || die "needs $tool"; done
  if exists; then
    ask "Replace the test machine $VM (its disk and snapshot)?" || exit 0
    delete_vm
  fi
  find_iso
  mkdir -p "$WORK" "$BOXES/images"
  note "Taking the installer's kernel out of ${ISO##*/}"
  in_boxes isoinfo -R -i "$ISO" -x /casper/vmlinuz > "$WORK/vmlinuz" && [[ -s "$WORK/vmlinuz" ]] \
    && in_boxes isoinfo -R -i "$ISO" -x /casper/initrd > "$WORK/initrd" && [[ -s "$WORK/initrd" ]] \
    || die "couldn't read the kernel from the ISO"
  answers "$WORK/answers"
  ANSWERS_PORT="$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  # Only while installing, only on this computer (the machine reaches it as 10.0.2.2).
  python3 -I -m http.server "$ANSWERS_PORT" --bind 127.0.0.1 --directory "$WORK/answers" \
    > "$WORK/answers.log" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null' EXIT
  in_boxes qemu-img create -q -f qcow2 "$DISK" "$DISK_SIZE" || die "couldn't make the disk"
  domain_xml install > "$WORK/install.xml"; define "$WORK/install.xml"
  vsh start "$VM" >/dev/null || die "the machine didn't start"
  note "Installing Ubuntu: open \"Dotfiles test\" in Boxes to watch (dot vm open)"
  local asked=0
  answered() { grep -q 'GET /user-data' "$WORK/answers.log"; }
  installed_and_off() {   # (off because Boxes saved it isn't finished: resumed instead)
    (( asked )) || ! answered || { asked=1; printf '%s(answers read)%s ' "$C_DIM" "$C_N"; }
    resume_if_saved && return 1
    shut_off
  }
  wait_until "$INSTALL_TIMEOUT" "installing" installed_and_off || {
    answered || die "the installer never read its answers, so it's waiting for you in Boxes. Close it there, then run this again"
    die "the install didn't finish in $(fmt_time "$INSTALL_TIMEOUT"); look at it in Boxes"
  }
  answered || die "the machine stopped without reading its answers; look at it in Boxes"
  kill "$pid" 2>/dev/null; trap - EXIT
  # From now on, boot the disk.
  uuid="$(vsh domuuid "$VM" | head -1)"
  domain_xml normal "$uuid" > "$WORK/normal.xml"; define "$WORK/normal.xml"
  note "First start of the new system"
  boot
  sleep 20   # let the first sign-in finish its own setup
  power_off
  vsh snapshot-create-as "$VM" clean "Fresh Ubuntu 26.04, before the dotfiles" >/dev/null \
    || die "couldn't take the snapshot"
  ok "Test machine ready in $(fmt_time $((SECONDS - t0))): $VM, snapshot \"clean\""
}

# --- The download cache ------------------------------------------------------------------
# cache_attach: the cache disk (made the first time) as the machine's second disk, from its
# next start. The snapshot doesn't have it, so this comes after each revert.
cache_attach() {
  if [[ ! -f "$CACHE_DISK" ]]; then
    in_boxes qemu-img create -q -f qcow2 "$CACHE_DISK" "$CACHE_SIZE" || return 1
  fi
  vsh attach-disk "$VM" "$CACHE_DISK" vdb --config --driver qemu --subdriver qcow2 --targetbus virtio >/dev/null
}
# cache_mount_script / cache_prune_script: what runs in the machine, as root (text, so the
# tests can read it). Mount: the disk (formatted the first time) and apt's download folder
# on it, until the setup's restart; prints how many bytes it holds. Prune (after the test):
# apt autoclean drops what can't be downloaded any more (old versions), so it doesn't grow.
cache_mount_script() {
  cat <<'EOF'
set -e
blkid /dev/vdb >/dev/null 2>&1 || mkfs.ext4 -q -L dotfiles-cache /dev/vdb
mkdir -p /mnt/dotfiles-cache
mountpoint -q /mnt/dotfiles-cache || mount /dev/vdb /mnt/dotfiles-cache
install -d -o _apt -g root -m 700 /mnt/dotfiles-cache/apt/partial
mountpoint -q /var/cache/apt/archives || mount --bind /mnt/dotfiles-cache/apt /var/cache/apt/archives
du -sb /mnt/dotfiles-cache/apt | cut -f1
EOF
}
cache_prune_script() {
  cat <<'EOF'
set -e
mkdir -p /mnt/dotfiles-cache
mountpoint -q /mnt/dotfiles-cache || mount /dev/vdb /mnt/dotfiles-cache
apt-get -q autoclean -o Dir::Cache::archives=/mnt/dotfiles-cache/apt/ >/dev/null
du -sb /mnt/dotfiles-cache/apt | cut -f1
umount /mnt/dotfiles-cache
EOF
}
# in_machine <script text> [seconds]: run it in the machine as root; prints its last line.
in_machine() {
  local out
  out="$(guest exec "echo $(base64 -w0 <<< "$1") | base64 -d | bash" "${2:-120}")" || return 1
  printf '%s\n' "${out##*$'\n'}"
}
mb() { echo "$(( ${1:-0} / 1000000 )) MB"; }

delete_vm() {
  exists || return 0
  shut_off || vsh destroy "$VM" >/dev/null 2>&1
  vsh undefine "$VM" --snapshots-metadata >/dev/null || die "couldn't remove $VM from Boxes"
  rm -f "$DISK"
}

# --- The test -----------------------------------------------------------------------------
# website_command: what the website gives you to paste, for what's on GitHub, with the
# DOTFILES_* choices from this shell in front. The git name and email are filled in as on
# the website's form (a test identity unless you give one): otherwise the setup asks for
# them at the start, and no one is there to press Enter.
website_command() {
  local url repo v cmd=""
  local DOTFILES_GIT_NAME="${DOTFILES_GIT_NAME:-Dotfiles Test}"
  local DOTFILES_GIT_EMAIL="${DOTFILES_GIT_EMAIL:-tester@dotfiles-test.invalid}"
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
  repo="$(sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' <<< "$url")"
  [[ "$repo" == */* ]] || repo=ronaldo-kwan/dotfiles
  for v in DOTFILES_CHOICES DOTFILES_SKIP DOTFILES_REF DOTFILES_GIT_NAME DOTFILES_GIT_EMAIL; do
    [[ -n "${!v:-}" ]] && cmd+="$v=$(printf '%q' "${!v}") "
  done
  [[ "$repo" != ronaldo-kwan/dotfiles ]] && cmd+="DOTFILES_REPO=https://github.com/$repo.git "
  printf '%sbash <(wget -qO- https://raw.githubusercontent.com/%s/main/bootstrap.sh) --yes' "$cmd" "$repo"
}

test_run() {
  local run cmd rc setup_ok=0 check_rc line bad=() t0=$SECONDS
  header "Dotfiles test in a virtual machine" "A fresh Ubuntu, the website's command, a restart, then dot check."
  if ! exists || ! has_clean; then create; fi
  # What's tested is GitHub's: say if this computer has something it doesn't.
  local unpushed; unpushed="$(git -C "$ROOT" log --oneline '@{u}..' 2>/dev/null | wc -l)"
  (( unpushed )) && warn "$unpushed commit(s) here aren't on GitHub, so they aren't tested (dot push first)"
  [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]] && warn "uncommitted changes here aren't tested"
  run="$WORK/runs/$(date +%Y-%m-%d_%H%M%S)"; mkdir -p "$run"
  plain_log() { sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\r$//; s/.*\r//' "$run/setup.log" > "$run/setup.txt"; }

  note "Back to the fresh Ubuntu (snapshot \"clean\")"
  shut_off || vsh destroy "$VM" >/dev/null 2>&1
  vsh managedsave-remove "$VM" >/dev/null 2>&1   # a state Boxes saved: the snapshot replaces it
  vsh snapshot-revert "$VM" clean >/dev/null || die "couldn't go back to the snapshot"
  # The snapshot brings back the cores and memory it was made with: these settings win, so
  # changing them above needs no new machine.
  fit_machine || warn "couldn't set the machine to $CPUS cores and $MEMORY_MIB MiB; testing with the snapshot's"
  local cache=0 bytes
  if (( NO_CACHE )); then note "No download cache (--no-cache): everything downloads"
  elif cache_attach; then cache=1
  else warn "couldn't attach the download cache; everything downloads"; fi
  boot
  if (( cache )); then
    if bytes="$(in_machine "$(cache_mount_script)")" && [[ "$bytes" =~ ^[0-9]+$ ]]; then
      note "Download cache: $(mb "$bytes") from earlier tests (dot vm --no-cache downloads everything)"
    else
      warn "couldn't use the download cache; everything downloads"; cache=0
    fi
  fi

  cmd="$(website_command)"
  note "In the machine's terminal: $cmd"
  printf '%s\n' "$cmd" > "$run/command.txt"
  # In a terminal of its own (script gives it one, 120 by 40), as when you paste it, logged
  # to ~/dotfiles-test.log in the machine. The last line says how it ended.
  local inner="stty cols 120 rows 40 2>/dev/null; $cmd" boot0
  boot0="$(boot_id)"; [[ -n "$boot0" ]] || die "no answer from the machine"   # to tell when it has restarted
  guest_session "systemd-run --user --unit=dotfiles-test --collect --quiet --working-directory=/home/$GUEST_USER \
bash -c $(printf '%q' "script -qefc $(printf '%q' "$inner") ~/dotfiles-test.log; echo \"==> dotfiles-test: exit \$?\" >> ~/dotfiles-test.log")" \
    >/dev/null || die "couldn't start the command in the machine"
  echo
  # The machine goes quiet when it restarts at the end, or when Boxes saved it: then it's
  # started again from where it was, and the output carries on.
  while :; do
    guest follow "/home/$GUEST_USER/dotfiles-test.log" "$run/setup.log" "$SETUP_TIMEOUT"; rc=$?
    if (( rc != 100 )) || ! resume_if_saved; then break; fi
    wait_until "$BOOT_TIMEOUT" "carrying on" guest ping || die "no answer after starting it again; look at it in Boxes"
  done
  echo
  (( rc == 124 )) && die "the setup didn't finish in $(fmt_time "$SETUP_TIMEOUT"); look at it in Boxes"
  (( rc == 100 )) && shut_off && die "the machine stopped instead of restarting; look at it in Boxes"
  plain_log
  # It ends with sudo reboot, which returns at once: its last lines can come before the
  # restart has even begun, so wait for a new boot, not just for the machine to answer.
  if (( rc == 100 )) || grep -q 'Restarting in' "$run/setup.txt"; then
    note "The machine is restarting (the setup ends with a restart)"
    restarted() { local b; resume_if_saved; b="$(boot_id)" && [[ -n "$b" && "$b" != "$boot0" ]]; }
    wait_until "$BOOT_TIMEOUT" "starting again" restarted || die "no answer after the restart; look at it in Boxes"
    wait_until "$BOOT_TIMEOUT" "signing in to the desktop" session_ready || die "the desktop didn't start after the restart"
    # The whole log, with what was written in the last seconds before the restart.
    guest exec "cat /home/$GUEST_USER/dotfiles-test.log" > "$run/setup.log"; plain_log
  else
    warn "the setup stopped without restarting (exit code $rc)"
  fi
  grep -q '✔ All done' "$run/setup.txt" && setup_ok=1

  if (( setup_ok || rc == 100 )); then
    note "dot check, in a new terminal after the restart"
    guest_session "bash -lc '~/code/github/dotfiles/dot check < /dev/null'" 600 > "$run/check.log"; check_rc=$?
    sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$run/check.log" > "$run/check.txt"
    while IFS= read -r line; do
      local e hit=0
      for e in "${EXPECTED[@]}"; do [[ "$line" =~ $e ]] && hit=1; done
      (( hit )) || bad+=("$line")
    done < <(grep '✘' "$run/check.txt" | grep -v 'thing.* need' | sed 's/^ *✘ //')
  else
    check_rc=0   # nothing to check: it would only list everything the setup didn't get to
    bad+=("dot check not run: the setup stopped early")
  fi
  vsh screenshot "$VM" --file "$run/screen.png" >/dev/null 2>&1 || true
  if (( cache )) && bytes="$(in_machine "$(cache_prune_script)" 300)"; then
    note "Download cache: $(mb "$bytes") kept for the next test"
  fi

  echo
  if (( setup_ok )); then ok "the setup finished (✔ All done)"
  else printf '%s✘%s the setup didn'"'"'t finish: its summary is in %s\n' "$C_ERR" "$C_N" "${run/#$HOME/\~}/setup.txt"
       grep -E '✘|FAILED|failed' "$run/setup.txt" | tail -8 | sed 's/^/      /'; fi
  if (( check_rc == 255 || check_rc == 124 )); then printf '%s✘%s dot check didn'"'"'t run (exit code %s)\n' "$C_ERR" "$C_N" "$check_rc"; bad+=("dot check didn't run")
  elif (( ${#bad[@]} == 0 )); then ok "dot check: nothing wrong but what a new computer can't have yet"
  else printf '%s✘%s dot check found:\n' "$C_ERR" "$C_N"; printf '      %s\n' "${bad[@]}"; fi
  note "Output and a screenshot: ${run/#$HOME/\~}  (took $(fmt_time $((SECONDS - t0))))"
  note "The machine is still running as the test left it: dot vm open"
  (( setup_ok && ${#bad[@]} == 0 ))
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0   # sourced (scripts/test-helpers.sh): only the functions
args=()
for a in "$@"; do
  if [[ "$a" == --no-cache ]]; then NO_CACHE=1; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
case "${1:-test}" in
  test)   test_run ;;
  create) create ;;
  open)   exists || die "no test machine yet: dot vm"
          shut_off && vsh start "$VM" >/dev/null
          flatpak run org.gnome.Boxes --open-uuid "$(vsh domuuid "$VM" | head -1)" >/dev/null 2>&1 & disown ;;
  delete) exists || [[ -f "$CACHE_DISK" ]] || { echo "There's no test machine."; exit 0; }
          ask "Delete the test machine $VM, its disk ($(du -h "$DISK" 2>/dev/null | cut -f1)) and the download cache ($(du -h "$CACHE_DISK" 2>/dev/null | cut -f1))?" || exit 0
          delete_vm; rm -f "$CACHE_DISK"; ok "Deleted $VM and its download cache" ;;
  -h|--help|help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) echo "Unknown: $1 (test, create, open or delete; and --no-cache)"; exit 2 ;;
esac
