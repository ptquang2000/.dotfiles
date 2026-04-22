#!/usr/bin/env bash
# =====================================================================
#  install.sh
#
#  SYNOPSIS
#    Installs all packages declared in the sibling packages/ directory
#    for a Linux system. This is the Linux counterpart to install.bat.
#
#  DESCRIPTION
#    - Detects the host distribution via /etc/os-release.
#    - On Arch Linux (and derivatives): installs `packages/pacman` via
#      pacman, `packages/yay` via an AUR helper (yay or paru; will
#      bootstrap yay if neither is present), and `packages/cargo`
#      crates via cargo (installing rust via pacman if needed).
#    - On Debian/Ubuntu: best-effort install of the pacman list via
#      apt-get. Some names may not map; failures are logged and the
#      script continues.
#    - Idempotent: safe to re-run. Uses --needed / already-installed
#      checks where possible.
#
#  USAGE
#    ./install.sh
#
#  NOTES
#    - Requires sudo for system package installation.
#    - Cargo crates are installed into the invoking user's ~/.cargo.
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/packages"

PACMAN_FILE="${PKG_DIR}/pacman"
AUR_FILE="${PKG_DIR}/yay"
CARGO_FILE="${PKG_DIR}/cargo"

# --- result tracking ---------------------------------------------------
declare -a FAILED_PKGS=()
declare -a INSTALLED_GROUPS=()

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

# --- distro detection --------------------------------------------------
detect_distro() {
    if [[ ! -r /etc/os-release ]]; then
        err "/etc/os-release not found; cannot detect distribution."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    local id="${ID:-}"
    local id_like="${ID_LIKE:-}"

    case "$id" in
        arch|cachyos|endeavouros|manjaro|artix) echo "arch"; return ;;
        debian|ubuntu|linuxmint|pop|raspbian)   echo "debian"; return ;;
    esac
    case " $id_like " in
        *" arch "*)   echo "arch"; return ;;
        *" debian "*) echo "debian"; return ;;
        *" ubuntu "*) echo "debian"; return ;;
    esac
    echo "unknown"
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

    as_root pacman -Syu --noconfirm --needed --quiet || warn "pacman -Syu reported issues; continuing."

    if as_root pacman -S --noconfirm --needed "${pkgs[@]}"; then
        ok "pacman batch install succeeded."
        INSTALLED_GROUPS+=("pacman: ${#pkgs[@]} pkgs")
    else
        warn "Batch pacman install failed; retrying per-package."
        local p
        for p in "${pkgs[@]}"; do
            if as_root pacman -S --noconfirm --needed "$p"; then
                ok "pacman: $p"
            else
                err "pacman failed: $p"
                FAILED_PKGS+=("pacman:$p")
            fi
        done
    fi
}

bootstrap_yay() {
    if need_cmd yay || need_cmd paru; then return 0; fi
    log "No AUR helper found; bootstrapping yay."
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

aur_helper() {
    if need_cmd yay;  then echo yay;  return; fi
    if need_cmd paru; then echo paru; return; fi
    echo ""
}

install_arch_aur() {
    [[ -r "$AUR_FILE" ]] || { warn "No $AUR_FILE; skipping AUR."; return 0; }
    local pkgs
    mapfile -t pkgs < <(read_pkg_file "$AUR_FILE")
    [[ ${#pkgs[@]} -gt 0 ]] || { warn "AUR list is empty."; return 0; }

    if [[ $EUID -eq 0 ]]; then
        warn "Refusing to run AUR helper as root; skipping AUR packages."
        return 0
    fi

    bootstrap_yay
    local helper
    helper="$(aur_helper)"
    if [[ -z "$helper" ]]; then
        err "AUR helper still unavailable; skipping AUR packages."
        for p in "${pkgs[@]}"; do FAILED_PKGS+=("aur:$p"); done
        return 0
    fi

    log "Installing AUR packages with $helper"
    if "$helper" -S --noconfirm --needed "${pkgs[@]}"; then
        ok "$helper batch install succeeded."
        INSTALLED_GROUPS+=("aur: ${#pkgs[@]} pkgs")
    else
        warn "Batch AUR install failed; retrying per-package."
        local p
        for p in "${pkgs[@]}"; do
            if "$helper" -S --noconfirm --needed "$p"; then
                ok "aur: $p"
            else
                err "aur failed: $p"
                FAILED_PKGS+=("aur:$p")
            fi
        done
    fi
}

install_cargo_crates() {
    [[ -r "$CARGO_FILE" ]] || return 0
    local crates
    mapfile -t crates < <(read_pkg_file "$CARGO_FILE")
    [[ ${#crates[@]} -gt 0 ]] || return 0

    if ! need_cmd cargo; then
        warn "cargo not on PATH; attempting to install rust via pacman."
        if need_cmd pacman; then
            as_root pacman -S --noconfirm --needed rust || true
        fi
    fi
    if ! need_cmd cargo; then
        err "cargo still unavailable; skipping cargo crates."
        for c in "${crates[@]}"; do FAILED_PKGS+=("cargo:$c"); done
        return 0
    fi

    log "Installing cargo crates: ${crates[*]}"
    local c
    for c in "${crates[@]}"; do
        if cargo install --locked "$c"; then
            ok "cargo: $c"
        else
            err "cargo failed: $c"
            FAILED_PKGS+=("cargo:$c")
        fi
    done
    INSTALLED_GROUPS+=("cargo: ${#crates[@]} crates")
}

# --- debian/ubuntu fallback -------------------------------------------
install_debian() {
    warn "Debian/Ubuntu detected. Best-effort install; Arch-specific"
    warn "packages (hyprland, ghostty, fcitx5-unikey, waydroid, etc.)"
    warn "may not exist in apt repos and will be logged as failures."

    [[ -r "$PACMAN_FILE" ]] || { err "No $PACMAN_FILE to translate."; return 0; }

    export DEBIAN_FRONTEND=noninteractive
    as_root apt-get update -y || warn "apt-get update had issues; continuing."

    local pkgs
    mapfile -t pkgs < <(read_pkg_file "$PACMAN_FILE")
    local p
    for p in "${pkgs[@]}"; do
        if as_root apt-get install -y --no-install-recommends "$p" >/dev/null 2>&1; then
            ok "apt: $p"
        else
            err "apt unavailable or failed: $p"
            FAILED_PKGS+=("apt:$p")
        fi
    done
    INSTALLED_GROUPS+=("apt: attempted ${#pkgs[@]} pkgs")

    if [[ -r "$AUR_FILE" ]]; then
        warn "AUR list exists but has no apt equivalent; skipping."
        while IFS= read -r p; do FAILED_PKGS+=("aur-unsupported:$p"); done < <(read_pkg_file "$AUR_FILE")
    fi

    install_cargo_crates
}

# --- summary -----------------------------------------------------------
print_summary() {
    echo
    log "Install summary:"
    if [[ ${#INSTALLED_GROUPS[@]} -gt 0 ]]; then
        local g
        for g in "${INSTALLED_GROUPS[@]}"; do ok "  $g"; done
    fi
    if [[ ${#FAILED_PKGS[@]} -eq 0 ]]; then
        ok "All packages installed successfully."
        return 0
    fi
    warn "The following packages failed or were skipped (${#FAILED_PKGS[@]}):"
    local f
    for f in "${FAILED_PKGS[@]}"; do printf '      - %s\n' "$f" >&2; done
    return 1
}

# --- main --------------------------------------------------------------
main() {
    require_sudo
    local distro
    distro="$(detect_distro)"
    log "Detected distro family: ${distro}"

    case "$distro" in
        arch)
            install_arch_pacman
            install_arch_aur
            install_cargo_crates
            ;;
        debian)
            install_debian
            ;;
        *)
            err "Unsupported distribution. Supported: Arch, Debian/Ubuntu."
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
