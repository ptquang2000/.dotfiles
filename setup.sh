#!/usr/bin/env bash

set -euo pipefail

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/ptquang2000/.dotfiles.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

is_repo() {
    [[ -f "$1/setup.sh" && -f "$1/packages/pacman" ]]
}

bootstrap() {
    local name="$1"; shift
    local src_dir
    src_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)"

    if is_repo "$src_dir"; then
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        err "git is required to bootstrap. Install it first: sudo pacman -S git"
        exit 1
    fi

    if [[ -e "$DOTFILES_DIR" ]]; then
        if is_repo "$DOTFILES_DIR" || [[ -d "$DOTFILES_DIR/.git" ]]; then
            log "Existing dotfiles checkout found: $DOTFILES_DIR"
        else
            err "Path exists but is not a dotfiles checkout: $DOTFILES_DIR"
            exit 1
        fi
    else
        log "Cloning $REPO_URL -> $DOTFILES_DIR"
        git clone --recurse-submodules "$REPO_URL" "$DOTFILES_DIR"
    fi

    log "Re-running $name from $DOTFILES_DIR"
    exec bash "$DOTFILES_DIR/$name" "$@"
}

bootstrap "setup.sh" "$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
DOTS="$SCRIPT_DIR"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
PKG_DIR="$DOTS/packages"
STAMP="$(date +%Y%m%d-%H%M%S)"

PACMAN_FILE="$PKG_DIR/pacman"
AUR_FILE="$PKG_DIR/yay"
CARGO_FILE="$PKG_DIR/cargo"
NPM_FILE="$PKG_DIR/package.json"
PIP_FILE="$PKG_DIR/requirements.txt"

SDDM_THEME_DIR="/usr/share/sddm/themes/where_is_my_sddm_theme"
SDDM_THEME_REPO="https://github.com/ptquang2000/where-is-my-sddm-theme.git"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_sudo() {
    if [[ $EUID -ne 0 ]] && ! need_cmd sudo; then
        err "This script requires root privileges or sudo."
        exit 1
    fi
}

as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

link() {
    local src="$1" dest="$2" sudo=""
    [[ "$dest" == "$HOME"/* ]] || sudo="sudo"

    if [[ ! -e "$src" ]]; then
        log "skip, source missing: $src"
        return 0
    fi
    if [[ "$(readlink "$dest" 2>/dev/null)" == "$src" ]]; then
        return 0
    fi

    $sudo mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" || -L "$dest" ]]; then
        log "backing up $dest -> $dest.bak.$STAMP"
        $sudo mv "$dest" "$dest.bak.$STAMP"
    fi
    $sudo ln -sfn "$src" "$dest"
    log "linked $dest -> $src"
}

read_pkg_file() {
    local file="$1"
    [[ -r "$file" ]] || return 0
    grep -vE '^\s*(#|$)' "$file" || true
}

install_arch_pacman() {
    [[ -r "$PACMAN_FILE" ]] || { warn "No $PACMAN_FILE; skipping pacman."; return 0; }
    log "Installing pacman packages from $PACMAN_FILE"
    local pkgs
    mapfile -t pkgs < <(read_pkg_file "$PACMAN_FILE")
    [[ ${#pkgs[@]} -gt 0 ]] || { warn "pacman list is empty."; return 0; }

    as_root pacman -Syu --noconfirm --needed --quiet
    as_root pacman -S --noconfirm --needed "${pkgs[@]}"
    ok "pacman batch install succeeded (${#pkgs[@]} pkgs)."
}

bootstrap_yay() {
    if need_cmd yay; then return 0; fi
    log "yay not found; bootstrapping."
    as_root pacman -S --noconfirm --needed base-devel git
    local build
    build="$(mktemp -d)"
    (
        cd "$build"
        git clone --depth=1 https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
    )
    rm -rf "$build"
}

install_arch_aur() {
    [[ -r "$AUR_FILE" ]] || { warn "No $AUR_FILE; skipping AUR."; return 0; }
    local pkgs
    mapfile -t pkgs < <(read_pkg_file "$AUR_FILE")
    [[ ${#pkgs[@]} -gt 0 ]] || { warn "AUR list is empty."; return 0; }

    log "Installing AUR packages with yay"
    yay -S --noconfirm --needed "${pkgs[@]}"
    ok "yay batch install succeeded (${#pkgs[@]} pkgs)."
}

install_cargo_crates() {
    [[ -r "$CARGO_FILE" ]] || return 0
    local crates
    mapfile -t crates < <(read_pkg_file "$CARGO_FILE")
    [[ ${#crates[@]} -gt 0 ]] || return 0

    log "Installing cargo crates: ${crates[*]}"
    local c
    for c in "${crates[@]}"; do
        cargo install --locked "$c"
        ok "cargo: $c"
    done
}

install_npm_packages() {
    [[ -r "$NPM_FILE" ]] || return 0
    if ! need_cmd npm; then
        warn "npm not found; skipping npm packages."
        return 0
    fi
    log "Installing npm packages from $NPM_FILE"
    local deps
    deps=$(node -e "const p=require('$NPM_FILE'); console.log(Object.keys(p.dependencies||{}).join(' '))")
    [[ -n "$deps" ]] && as_root npm install -g $deps
    ok "npm packages installed."
}

install_pip_packages() {
    [[ -r "$PIP_FILE" ]] || return 0
    if ! need_cmd pipx; then
        warn "pipx not found; skipping pip packages."
        return 0
    fi
    log "Installing pip packages from $PIP_FILE"
    local pkgs
    mapfile -t pkgs < <(read_pkg_file "$PIP_FILE")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    local pkg
    for pkg in "${pkgs[@]}"; do
        pipx install "$pkg" || pipx upgrade "$pkg"
    done
    ok "pip packages installed."
}

configure_default_apps() {
    log "Configuring default applications"
    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" != "/usr/bin/zsh" ]]; then
        chsh -s /usr/bin/zsh
    fi
    need_cmd xdg-mime && xdg-mime default org.pwmt.zathura.desktop application/pdf
}

install_sddm_theme() {
    if [[ -d "$SDDM_THEME_DIR" ]]; then
        log "SDDM theme already installed; skipping."
    else
        log "Installing SDDM theme from $SDDM_THEME_REPO"
        local tmp
        tmp="$(mktemp -d)"
        trap "rm -rf '$tmp'" RETURN
        (
            cd "$tmp"
            git clone --depth=1 "$SDDM_THEME_REPO" where-is-my-sddm-theme
            cd where-is-my-sddm-theme
            sudo sh install.sh
        )
        as_root cp "${SCRIPT_DIR}/assets/wallpaper.jpg" "${SDDM_THEME_DIR}/"
        rm -rf "$tmp"
        trap - RETURN
        ok "SDDM theme installed."
    fi
    as_root systemctl enable sddm
}

setup_waydroid() {
    if ! need_cmd waydroid; then
        warn "waydroid not installed; skipping."
        return 0
    fi
    log "Configuring waydroid"
    if [[ -d /var/lib/waydroid/images ]]; then
        log "waydroid already initialized; skipping init."
    else
        as_root waydroid init -s GAPPS
    fi
    as_root systemctl enable --now waydroid-container.service

    if need_cmd waydroid-extras; then
        as_root waydroid-extras install libndk
        as_root waydroid-extras install libhoudini
    else
        warn "waydroid-extras not found; skipping libndk/libhoudini."
    fi
    warn "Manual step remaining: run 'sudo waydroid-extras certified' after launching a browser inside waydroid."
}

sync_submodules() {
    [[ -f "$DOTS/.gitmodules" && -d "$DOTS/.git" ]] || return 0
    log "Updating git submodules (recursive)"
    git -C "$DOTS" submodule update --init --recursive
}

switch_personal_submodule_remotes() {
    local remotes=(
        "nvim-init|git@github.com:ptquang2000/nvim-init.git"
        "powershell|git@github.com:ptquang2000/powershell.git"
        "virutils|git@github.com:ptquang2000/virutils.git"
    )
    local entry path remote
    for entry in "${remotes[@]}"; do
        path="${entry%%|*}"; remote="${entry##*|}"
        if [[ ! -e "$DOTS/$path/.git" ]]; then
            warn "submodule not initialized, skipping: $path"
            continue
        fi
        if [[ "$(git -C "$DOTS/$path" remote get-url origin)" == "$remote" ]]; then
            continue
        fi
        git -C "$DOTS/$path" remote set-url origin "$remote"
        log "submodule $path remote -> $remote"
    done
}

link_configs() {
    log "Linking configs"

    link "$DOTS/hypr"             "$CONFIG/hypr"
    link "$DOTS/waybar"           "$CONFIG/waybar"
    link "$DOTS/mako"             "$CONFIG/mako"
    link "$DOTS/fcitx5"           "$CONFIG/fcitx5"
    link "$DOTS/ghostty"          "$CONFIG/ghostty"
    link "$DOTS/mpv"              "$CONFIG/mpv"
    link "$DOTS/zathura"          "$CONFIG/zathura"
    link "$DOTS/sioyek"           "$CONFIG/sioyek"
    link "$DOTS/nvim-init"        "$CONFIG/nvim"
    link "$DOTS/zsh"              "$CONFIG/zsh"
    link "$DOTS/tmux"             "$CONFIG/tmux"
    link "$DOTS/tmux-sessionizer" "$CONFIG/tmux-sessionizer"
    link "$DOTS/opencode/skills"  "$CONFIG/opencode/skills"

    link "$DOTS/.zshenv"          "$HOME/.zshenv"
    link "$DOTS/.bashrc"          "$HOME/.bashrc"

    if [[ -L "$BIN" ]]; then
        log "replacing the $BIN symlink with a real directory"
        rm -f "$BIN"
    fi
    mkdir -p "$BIN"
    local src
    for src in "$DOTS"/scripts/* "$DOTS"/virutils/vir*; do
        link "$src" "$BIN/${src##*/}"
    done

    link "$DOTS/sddm.conf.d"              "/etc/sddm.conf.d"
    link "$DOTS/systemd/resolved.conf.d"  "/etc/systemd/resolved.conf.d"
}

main() {
    require_sudo
    log "Repo: $DOTS"

    sync_submodules
    install_arch_pacman
    bootstrap_yay
    install_arch_aur
    install_cargo_crates
    install_npm_packages
    install_pip_packages
    configure_default_apps
    install_sddm_theme
    setup_waydroid
    switch_personal_submodule_remotes
    link_configs

    ok "Done."
}

main "$@"
