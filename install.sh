#!/usr/bin/env bash
# =====================================================================
#  install.sh
#
#  SYNOPSIS
#    Personal Arch Linux bootstrap. Installs packages declared in the
#    sibling packages/ directory, sets default apps, installs the SDDM
#    theme, and initializes waydroid.
#
#  DESCRIPTION
#    - Installs `packages/pacman` via pacman.
#    - Installs `packages/yay` via yay (bootstrapped if missing).
#    - Installs `packages/cargo` crates via cargo (rust assumed to be
#      provided by the pacman list).
#    - Configures default shell (zsh) and PDF handler (zathura).
#    - Installs the where-is-my-sddm-theme and enables sddm.
#    - Initializes waydroid with GAPPS and installs libndk/libhoudini.
#    - Idempotent: safe to re-run.
#
#  USAGE
#    ./install.sh
#
#  NOTES
#    - Arch Linux only. Requires sudo.
#    - Cargo crates are installed into the invoking user's ~/.cargo.
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/packages"

PACMAN_FILE="${PKG_DIR}/pacman"
AUR_FILE="${PKG_DIR}/yay"
CARGO_FILE="${PKG_DIR}/cargo"

SDDM_THEME_DIR="/usr/share/sddm/themes/where_is_my_sddm_theme"
SDDM_THEME_REPO="https://github.com/ptquang2000/where-is-my-sddm-theme.git"

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

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

# --- helpers -----------------------------------------------------------
read_pkg_file() {
    # Strips blank lines and comments; prints one package per line.
    local file="$1"
    [[ -r "$file" ]] || return 0
    grep -vE '^\s*(#|$)' "$file" || true
}

# --- arch --------------------------------------------------------------
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

# --- default apps ------------------------------------------------------
configure_default_apps() {
    log "Configuring default applications"
    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" != "/usr/bin/zsh" ]]; then
        chsh -s /usr/bin/zsh
    fi
    xdg-mime default org.pwmt.zathura.desktop application/pdf
}

# --- sddm theme --------------------------------------------------------
install_sddm_theme() {
    if [[ -d "$SDDM_THEME_DIR" ]]; then
        log "SDDM theme already installed; skipping."
    else
        log "Installing SDDM theme from $SDDM_THEME_REPO"
        local tmp
        tmp="$(mktemp -d)"
        # shellcheck disable=SC2064
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

# --- waydroid ----------------------------------------------------------
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

# --- main --------------------------------------------------------------
main() {
    require_sudo
    install_arch_pacman
    bootstrap_yay
    install_arch_aur
    install_cargo_crates
    configure_default_apps
    install_sddm_theme
    setup_waydroid
    ok "Done."
}

main "$@"
