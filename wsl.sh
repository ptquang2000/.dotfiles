#!/usr/bin/env bash
# =====================================================================
#  wsl.sh — provision the WSL workstation.
#
#  SYNOPSIS
#    ./wsl.sh            Install packages, set the login shell, restore
#                        Windows interop, link configs. Then exit; it
#                        does not start a session.
#    ./wsl.sh --force    Reinstall packages even when they look present.
#
#  DESCRIPTION
#    This is the only provisioning script to run on a WSL distro.
#    install.sh and setup.sh are for bare-metal Arch and must NOT be run
#    here: they install hyprland, sddm and waydroid, none of which work
#    in the WSL VM, and they link a desktop config set this host has no
#    use for. Everything WSL-specific lives in this file, packages/wsl,
#    sway/ and scripts/sway-session.
#
#      1. Packages      packages/wsl, an inclusive list; entries also in
#                       packages/yay come from the AUR, the rest from the
#                       repos. Then the cargo/npm/pip lists, unfiltered.
#      2. Login shell   zsh, via chsh. Takes effect the next time the
#                       distro is launched, not in this shell.
#      3. Interop       Re-registers the WSLInterop binfmt handler that
#                       systemd wipes on boot, so .exe stays runnable.
#      4. Links         The subset of the repo that applies here. The
#                       only /etc write is the binfmt config in step 3.
#
#    Every step is idempotent and skipped when it has nothing to do, and
#    none of them can abort the others: a package that fails to build is
#    reported but the shell and link steps still run.
#
#    Starting the desktop is a separate concern, handled by
#    scripts/sway-session, which is on PATH once this script has run:
#
#        sway-session              # foreground; Ctrl-C ends it
#        sway-session -d           # detached, logging to /tmp/sway.log
#        sway-session --stop
#        sway-session -d --port 5901 --bind 127.0.0.1
#
#    Then connect TigerVNC Viewer on Windows to localhost:<port>.
#
#  NOTES
#    - WSLg cannot be used for GUI work: its rdprail-shell does not
#      forward xdg_popup implicit grabs across the RDP boundary, so every
#      dropdown opens and never dismisses. Running a real compositor
#      fixes it. Nesting one inside WSLg still leaves RAIL owning the
#      host window, which Windows cannot move, resize or position; the
#      headless backend plus a VNC client sidesteps RAIL entirely and
#      gives an ordinary, resizable Windows window. Hence sway on the
#      wlroots headless backend, exported over VNC by wayvnc.
#    - Everything is software-rendered; there is no /dev/dri here.
#    - systemd=true costs Windows interop. WSL registers its MZ handler in
#      binfmt_misc before hand-off, then systemd mounts binfmt_misc over
#      it and the registration is gone, so every .exe dies with
#      "exec format error". systemd-binfmt would restore it, but it is
#      ConditionDirectoryNotEmpty on the binfmt.d dirs and those are empty
#      out of the box, so the unit never runs. Dropping the handler into
#      /etc/binfmt.d/ satisfies the condition and survives reboots.
#    - There is no audio: VNC has no audio channel and
#      /mnt/wslg/PulseServer is not reachable from that session.
# =====================================================================

set -euo pipefail

DOTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG="$DOTS/packages"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"

ZSH_BIN="/usr/bin/zsh"

# Windows interop, re-registered for systemd's benefit. The interpreter is
# /init, WSL's own hand-off binary; P passes the original argv[0] through and
# F loads the interpreter now rather than at exec time, so it keeps working
# inside mount namespaces that cannot see /init.
BINFMT_CONF="/etc/binfmt.d/WSLInterop.conf"
BINFMT_LINE=":WSLInterop:M::MZ::/init:PF"

# Present once the package set is installed; their absence is what triggers
# the install step.
SESSION_CMDS=(sway swaybg wayvnc ghostty)

FORCE=0
case "${1:-}" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,/^# ===/p' "$0" | sed 's/^#\ \?//'; exit 0 ;;
    "") ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }
as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# --- packages ----------------------------------------------------------
# Failures warn rather than abort; the later steps do not depend on them.
# Membership in packages/yay is what marks an entry as AUR rather than repo.
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

# The cargo/npm/pip lists are not WSL-filtered — every entry works here.
# One entry that fails to build must not take the rest of the run with it.
install_lang_packages() {
    local item deps

    if have cargo; then
        for item in $(pkg_list "$PKG/cargo"); do
            cargo install --locked "$item" || warn "cargo: $item failed."
        done
    fi

    if have npm && [[ -r "$PKG/package.json" ]]; then
        deps="$(node -e "const p=require('$PKG/package.json'); console.log(Object.keys(p.dependencies||{}).join(' '))")"
        # shellcheck disable=SC2086
        [[ -n "$deps" ]] && { as_root npm install -g $deps || warn "npm install failed."; }
    fi

    if have pipx; then
        for item in $(pkg_list "$PKG/requirements.txt"); do
            pipx install "$item" || pipx upgrade "$item" || warn "pipx: $item failed."
        done
    fi
}

# --- login shell -------------------------------------------------------
# chsh authenticates through PAM on its own, separately from the sudo above,
# so it prompts for a password and can be declined. Nothing else in the repo
# depends on it, so a refusal is not fatal.
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

# --- windows interop ---------------------------------------------------
# WSL names the handler WSLInterop, or WSLInterop-late on builds that defer
# the registration; either one means .exe files run.
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

# --- links -------------------------------------------------------------
# Everything lands under $HOME, so none of this needs sudo. Deliberately
# absent: hypr and waybar (Hyprland-only), fcitx5, mpv, zathura and sioyek
# (not in packages/wsl), and the /etc links, which are bare-metal concerns.
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
    link "$DOTS/sway"              "$CONFIG/sway"
    link "$DOTS/ghostty"           "$CONFIG/ghostty"
    link "$DOTS/mako"              "$CONFIG/mako"
    link "$DOTS/nvim-init"         "$CONFIG/nvim"
    link "$DOTS/zsh"               "$CONFIG/zsh"
    link "$DOTS/tmux"              "$CONFIG/tmux"
    link "$DOTS/tmux-sessionizer"  "$CONFIG/tmux-sessionizer"
    link "$DOTS/opencode/skills"   "$CONFIG/opencode/skills"
    link "$DOTS/.zshenv"           "$HOME/.zshenv"
    link "$DOTS/.bashrc"           "$HOME/.bashrc"

    # One link per executable, because the tools come from two directories:
    # scripts/ and the virutils submodule. Older runs made ~/.local/bin a
    # symlink to scripts/; that has to go, or every link below lands inside
    # the repo.
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

# --- main --------------------------------------------------------------
main() {
    if [[ -z "${WSL_DISTRO_NAME:-}" ]] &&
       ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        err "Not running under WSL. On bare metal, use install.sh + setup.sh."
        exit 1
    fi

    local missing=()
    for cmd in "${SESSION_CMDS[@]}"; do
        have "$cmd" || missing+=("$cmd")
    done

    if (( FORCE )) || (( ${#missing[@]} )); then
        (( ${#missing[@]} )) && log "Missing: ${missing[*]}"
        install_packages
    else
        ok "Session packages present."
    fi

    set_shell
    fix_interop
    link_all

    echo
    ok "Provisioned. Start the desktop with: sway-session"
}

main "$@"
