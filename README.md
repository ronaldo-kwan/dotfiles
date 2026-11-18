# dotfiles

My terminal and desktop setup for Ubuntu (GNOME): bash, ble.sh, Starship, fzf, zoxide, eza, bat, Ghostty, btop, lazygit, and VS Code. Everything uses Catppuccin Mocha and JetBrainsMono Nerd Font.

## What's here

The folders are laid out for [GNU Stow](https://www.gnu.org/software/stow/). Each folder is a "package" whose contents mirror your home folder, and the real files in `~` are symlinks into this repo.

| Package | Links to | What it is |
|---|---|---|
| `bash` | `~/.bashrc` | Aliases, history, and loading for ble.sh, Starship, zoxide, fzf, eza and bat |
| `starship` | `~/.config/starship.toml` | Minimal prompt (`pure-preset`) |
| `ghostty` | `~/.config/ghostty/config` | Catppuccin Mocha, Nerd Font, padding |
| `btop` | `~/.config/btop/` | Catppuccin Mocha theme and settings |
| `lazygit` | `~/.config/lazygit/config.yml` | Catppuccin Mocha and Nerd Font icons |
| `terminal-default` | `~/.config/xdg-terminals.list` | Makes Ghostty the default terminal |
| `vscode` | `~/.config/Code/User/settings.json` | Theme, fonts, ligatures |
| `claude` | `~/.claude/CLAUDE.md` | Personal instructions for Claude Code |
| `system` | *not linked* | Weekly update script, installed by hand (see below) |

## Making changes

Edit files at their usual place (for example `~/.bashrc`) or in this folder. Both are the same file. Then save the change:

```bash
cd ~/dotfiles
git add -A
git commit -m "Describe the change"
```

## Setting up a new computer

### 1. Install the tools

```bash
sudo apt install git stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit
```

`lazygit` comes from Ubuntu Pro's extra app repository (`esm-apps`).

### 2. Install JetBrainsMono Nerd Font

```bash
mkdir -p ~/.local/share/fonts/JetBrainsMonoNerdFont
cd /tmp && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
mkdir -p /tmp/jbm && tar -xJf JetBrainsMono.tar.xz -C /tmp/jbm
cp /tmp/jbm/JetBrainsMonoNerdFont-*.ttf ~/.local/share/fonts/JetBrainsMonoNerdFont/
fc-cache -f
```

### 3. Link the config files

Stow won't replace files that already exist, so move the default `.bashrc` out of the way first:

```bash
mv ~/.bashrc ~/.bashrc.orig
cd ~/dotfiles
stow bash starship ghostty btop lazygit terminal-default vscode claude
```

### 4. System extras (optional)

**Weekly automatic updates.** First change `DESKTOP_USER=` in the script to the new username, then:

```bash
sudo cp ~/dotfiles/system/etc/cron.weekly/system-update /etc/cron.weekly/
sudo chmod +x /etc/cron.weekly/system-update
```

**Super+T opens the default terminal** (a custom GNOME shortcut):

```bash
KB=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$KB']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB name 'Terminal'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB binding '<Super>t'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB command 'xdg-terminal-exec'
```

The first `gsettings` line replaces the list of custom shortcuts. If the computer already has others, add this one to the existing list instead.

**Ptyxis font** (if you still use Ptyxis):

```bash
gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 10'
```
