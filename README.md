# dotfiles

My terminal and desktop setup for Ubuntu (GNOME): bash, ble.sh, Starship, fzf, zoxide, eza, bat, Ghostty, btop, lazygit, and VS Code. Everything uses Catppuccin Mocha and JetBrainsMono Nerd Font.

## What's here

The linked folders are laid out for [GNU Stow](https://www.gnu.org/software/stow/). Each one is a "package" whose contents mirror your home folder, and the real files in `~` are symlinks into this repo.

| Package | Links to | What it is |
|---|---|---|
| `bash` | `~/.bashrc` | Aliases, history, and loading for ble.sh, Starship, zoxide, fzf, eza and bat |
| `git` | `~/.gitconfig` | Name and email, `main` as the default branch, `gh` for GitHub sign-in |
| `starship` | `~/.config/starship.toml` | Minimal prompt (`pure-preset`) |
| `ghostty` | `~/.config/ghostty/config` | Catppuccin Mocha, Nerd Font, padding |
| `btop` | `~/.config/btop/` | Catppuccin Mocha theme and settings |
| `lazygit` | `~/.config/lazygit/config.yml` | Catppuccin Mocha and Nerd Font icons |
| `terminal-default` | `~/.config/xdg-terminals.list` | Makes Ghostty the default terminal |
| `vscode` | `~/.config/Code/User/settings.json` | Theme, fonts, ligatures |
| `claude` | `~/.claude/CLAUDE.md` | Personal instructions for Claude Code |

These folders aren't linked. Their contents are installed by hand (see below):

| Folder | What it is |
|---|---|
| `setup/` | VS Code extension list, GNOME keyboard shortcuts, GNOME extension list, wallpaper |
| `system/` | Weekly automatic update script |

## Making changes

Edit files at their usual place (for example `~/.bashrc`) or in this folder. Both are the same file. Then save the change:

```bash
cd ~/dotfiles
git add -A
git commit -m "Describe the change"
```

If you add a VS Code extension or change a keyboard shortcut, refresh the saved lists before committing:

```bash
code --list-extensions > ~/dotfiles/setup/vscode-extensions.txt
dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > ~/dotfiles/setup/gnome-shortcuts.dconf
```

## Setting up a new computer

### 1. Install the tools

```bash
sudo apt install git gh stow starship eza bat fzf zoxide fastfetch ble.sh ghostty btop lazygit
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

### 3. Get this repo and link the config files

```bash
gh auth login
gh repo clone dotfiles ~/dotfiles
```

Stow won't replace files that already exist. Move the default `.bashrc`, and the `.gitconfig` that `gh auth login` may have created, out of the way first:

```bash
mv ~/.bashrc ~/.bashrc.orig
mv ~/.gitconfig ~/.gitconfig.orig 2>/dev/null
cd ~/dotfiles
stow bash git starship ghostty btop lazygit terminal-default vscode claude
```

### 4. VS Code extensions

The Catppuccin theme in `settings.json` only works once its extension is installed:

```bash
xargs -n1 code --install-extension < ~/dotfiles/setup/vscode-extensions.txt
```

### 5. Keyboard shortcuts

Restores all custom shortcuts: Super+C Chrome, Super+X Claude, Super+T terminal, Super+E VS Code, Super+F Files, Super+O Obsidian. This replaces any custom shortcuts already on the computer.

```bash
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < ~/dotfiles/setup/gnome-shortcuts.dconf
```

The apps themselves (Chrome, Claude, VS Code, Obsidian) need installing separately.

### 6. GNOME extensions

Install the extensions listed in `setup/gnome-extensions.txt` (Alphabetical App Grid, Caffeine, Clipboard Indicator) with Extension Manager:

```bash
sudo apt install gnome-shell-extension-manager
```

### 7. Wallpaper

```bash
mkdir -p ~/Pictures/Wallpapers/current
cp ~/dotfiles/setup/wallpaper/catppuccin-tropic-island-night.jpg ~/Pictures/Wallpapers/current/
W="file://$HOME/Pictures/Wallpapers/current/catppuccin-tropic-island-night.jpg"
gsettings set org.gnome.desktop.background picture-uri "$W"
gsettings set org.gnome.desktop.background picture-uri-dark "$W"
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
```

### 8. System extras (optional)

**Weekly automatic updates.** First change `DESKTOP_USER=` in the script to the new username, then:

```bash
sudo cp ~/dotfiles/system/etc/cron.weekly/system-update /etc/cron.weekly/
sudo chmod +x /etc/cron.weekly/system-update
```

**Ptyxis font** (if you still use Ptyxis):

```bash
gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 10'
```
