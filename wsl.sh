#!/usr/bin/env bash

set -euo pipefail

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/ptquang2000/.dotfiles.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

is_repo() {
    [[ -f "$1/wsl.sh" && -f "$1/packages/wsl" ]]
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

bootstrap "wsl.sh" "$@"

DOTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-.}")" && pwd)"
PKG="$DOTS/packages"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"

ZSH_BIN="/usr/bin/zsh"
BINFMT_CONF="/etc/binfmt.d/WSLInterop.conf"
BINFMT_LINE=":WSLInterop:M::MZ::/init:PF"

case "${1:-}" in
    "") ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }
as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

pkg_list() { grep -vE '^\s*(#|$)' "$1" 2>/dev/null | sort -u || true; }

install_packages() {
    local repo aur
    mapfile -t repo < <(comm -23 <(pkg_list "$PKG/wsl") <(pkg_list "$PKG/yay"))
    mapfile -t aur  < <(comm -12 <(pkg_list "$PKG/wsl") <(pkg_list "$PKG/yay"))

    if (( ${#repo[@]} )); then
        log "Installing ${#repo[@]} repo packages"
        as_root pacman -Syu --noconfirm --needed --quiet &&
        as_root pacman -S --noconfirm --needed "${repo[@]}" ||
            warn "pacman install failed; continuing."
    fi

    if (( ${#aur[@]} )); then
        if have yay || bootstrap_yay; then
            log "Installing ${#aur[@]} AUR packages"
            yay -S --noconfirm --needed "${aur[@]}" || warn "yay install failed; continuing."
        else
            warn "yay unavailable; skipped ${#aur[@]} AUR packages."
        fi
    fi

    install_lang_packages
}

bootstrap_yay() {
    log "yay not found; bootstrapping."
    as_root pacman -S --noconfirm --needed base-devel git || return 1
    local build
    build="$(mktemp -d)"
    (
        cd "$build"
        git clone --depth=1 https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
    ) || { rm -rf "$build"; return 1; }
    rm -rf "$build"
}

install_lang_packages() {
    local item deps

    if have cargo; then
        for item in $(pkg_list "$PKG/cargo"); do
            cargo install --locked "$item" || warn "cargo: $item failed."
        done
    fi

    if have npm && [[ -r "$PKG/npm.json" ]]; then
        deps="$(node -e "const p=require('$PKG/npm.json'); console.log(Object.keys(p.dependencies||{}).join(' '))")"
        [[ -n "$deps" ]] && { as_root npm install -g $deps || warn "npm install failed."; }
    fi

    if have pipx; then
        for item in $(pkg_list "$PKG/requirements.txt"); do
            pipx install "$item" || pipx upgrade "$item" || warn "pipx: $item failed."
        done
    fi
}

set_shell() {
    [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$ZSH_BIN" ]] && return 0
    if [[ ! -x "$ZSH_BIN" ]]; then
        warn "$ZSH_BIN not installed; login shell left alone."
        return 0
    fi
    if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
        warn "$ZSH_BIN is not in /etc/shells; chsh will refuse it."
        return 0
    fi

    log "Setting login shell to zsh (takes effect next distro start)"
    chsh -s "$ZSH_BIN" || warn "chsh failed or was declined; run 'chsh -s $ZSH_BIN' by hand."
}

interop_live() {
    [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ||
       -e /proc/sys/fs/binfmt_misc/WSLInterop-late ]]
}

fix_interop() {
    if [[ "$(cat "$BINFMT_CONF" 2>/dev/null)" != "$BINFMT_LINE" ]]; then
        log "Registering the WSLInterop handler in $BINFMT_CONF"
        as_root install -Dm644 /dev/stdin "$BINFMT_CONF" <<<"$BINFMT_LINE" ||
            warn "Could not write $BINFMT_CONF; .exe files will break on reboot."
    fi

    interop_live && { ok "Windows interop registered."; return 0; }

    if [[ ! -d /run/systemd/system ]]; then
        warn "Interop is dead and systemd is not running; restart the distro."
        return 0
    fi
    if as_root systemctl restart systemd-binfmt && interop_live; then
        ok "Windows interop restored."
    else
        warn "systemd-binfmt did not register the handler; restart the distro."
    fi
}

link() {
    local src="$1" dest="$2"

    if [[ ! -e "$src" ]]; then
        warn "skip, source missing: $src"
        return 0
    fi
    [[ "$(readlink "$dest" 2>/dev/null)" == "$src" ]] && return 0

    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" || -L "$dest" ]]; then
        log "backing up $dest -> $dest.bak.$STAMP"
        mv "$dest" "$dest.bak.$STAMP"
    fi
    log "linking $dest -> $src"
    ln -sfn "$src" "$dest"
}

link_all() {
    link "$DOTS/ghostty"           "$CONFIG/ghostty"
    link "$DOTS/mako"              "$CONFIG/mako"
    link "$DOTS/nvim-init"         "$CONFIG/nvim"
    link "$DOTS/zsh"               "$CONFIG/zsh"
    link "$DOTS/tmux"              "$CONFIG/tmux"
    link "$DOTS/tmux-sessionizer"  "$CONFIG/tmux-sessionizer"
    link "$DOTS/opencode/skills"   "$CONFIG/opencode/skills"
    link "$DOTS/.zshenv"           "$HOME/.zshenv"
    link "$DOTS/.bashrc"           "$HOME/.bashrc"

    if [[ -L "$BIN" ]]; then
        log "replacing the $BIN symlink with a real directory"
        rm -f "$BIN"
    fi
    mkdir -p "$BIN"
    local src
    for src in "$DOTS"/scripts/* "$DOTS"/virutils/vir*; do
        link "$src" "$BIN/${src##*/}"
    done

    ok "Configs and executables linked."
}

sync_submodules() {
    [[ -f "$DOTS/.gitmodules" && -d "$DOTS/.git" ]] || return 0
    log "Updating git submodules (recursive)"
    git -C "$DOTS" submodule update --init --recursive
}

main() {
    if [[ -z "${WSL_DISTRO_NAME:-}" ]] &&
       ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        err "Not running under WSL. On bare metal, use setup.sh."
        exit 1
    fi

    sync_submodules
    set_shell
    fix_interop
    link_all

    echo
    ok "Provisioned."
}

main "$@"
