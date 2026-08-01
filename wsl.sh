#!/usr/bin/env bash
# =====================================================================
#  wsl.sh
#
#  SYNOPSIS
#    Self-contained bootstrap for the WSL workstation: installs
#    packages, links configs, and hands off to sway-session.
#
#  DESCRIPTION
#    This is the only script to run on a WSL distro. install.sh and
#    setup.sh are for bare-metal Arch and must NOT be run here: they
#    install hyprland, sddm and waydroid, none of which can work in the
#    WSL VM, and they link a desktop config set this host has no use for.
#    Everything WSL-specific lives in this file, packages/wsl, sway/ and
#    scripts/sway-session.
#
#      1. Install packages    packages/wsl, an inclusive list; entries
#                             also present in packages/yay come from the
#                             AUR, the rest from the repos. Then the
#                             cargo/npm/pip lists, which are unfiltered.
#      2. Link configs        The subset of the repo that applies here —
#                             see LINKS below. No /etc links, so sudo is
#                             needed only for the package install.
#      3. Start the session   Hands off to scripts/sway-session.
#
#    Steps 1 and 2 are skipped when they have nothing to do. Once the
#    machine is provisioned, `sway-session` on its own is enough — it is
#    on PATH, because scripts/ is linked to ~/.local/bin.
#
#    WSLg cannot be used for GUI work: its rdprail-shell does not forward
#    xdg_popup implicit grabs across the RDP boundary, so every dropdown
#    opens and never dismisses. Running a real compositor fixes it.
#    Nesting one inside WSLg still leaves RAIL owning the host window,
#    which Windows cannot move, resize or position; the headless backend
#    plus a VNC client sidesteps RAIL entirely and gives an ordinary,
#    resizable Windows window.
#
#  USAGE
#    ./wsl.sh                 Provision if needed, then start the session.
#    ./wsl.sh -d              ... detached, logging to /tmp/sway.log.
#    ./wsl.sh --check         Report what is missing and exit.
#    ./wsl.sh --provision     Install and link, then exit without starting.
#    ./wsl.sh --no-provision  Start the session and nothing else.
#
#    --port, --bind, --stop and -d are passed through to sway-session.
#    Then connect TigerVNC Viewer on Windows to localhost:<port>.
#
#  NOTES
#    - The client must be TigerVNC. wayvnc resizes the desktop to the
#      viewer window via SetDesktopSize, which TightVNC and RealVNC do
#      not implement. Enable it under Options -> Screen -> "Resize
#      remote session to the local window size".
#    - wayvnc binds 0.0.0.0 by default, not 127.0.0.1: WSL2's localhost
#      relay reaches the VM over its network interface, so a
#      loopback-only bind is invisible from Windows. The VM is NAT'd so
#      this is not LAN-visible, but the listener is unauthenticated and
#      unencrypted — any process on the Windows host can connect.
#    - Everything is software-rendered; there is no /dev/dri here.
#    - There is no audio: VNC has no audio channel and
#      /mnt/wslg/PulseServer is not reachable from this session.
#    - The distro must stay running; wayvnc dies with the VM.
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/packages"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

WSL_FILE="${PKG_DIR}/wsl"
AUR_FILE="${PKG_DIR}/yay"
CARGO_FILE="${PKG_DIR}/cargo"
NPM_FILE="${PKG_DIR}/package.json"
PIP_FILE="${PKG_DIR}/requirements.txt"

LAUNCHER="${SCRIPT_DIR}/scripts/sway-session"

PROVISION="auto"        # auto | only | never
CHECK_ONLY=0
LAUNCH_ARGS=()

# The repo subset that applies to a headless WSL host, as "src:dest" pairs.
# Everything lands under $HOME, so none of this needs sudo. Deliberately
# absent: hypr and waybar (Hyprland-only), fcitx5, mpv, zathura and sioyek
# (not in packages/wsl), and the /etc links, which are bare-metal concerns.
LINKS=(
    "sway:$CONFIG_HOME/sway"
    "ghostty:$CONFIG_HOME/ghostty"
    "mako:$CONFIG_HOME/mako"
    "nvim-init:$CONFIG_HOME/nvim"
    "zsh:$CONFIG_HOME/zsh"
    "tmux:$CONFIG_HOME/tmux"
    "tmux-sessionizer:$CONFIG_HOME/tmux-sessionizer"
    "opencode/skills:$CONFIG_HOME/opencode/skills"
    "scripts:$HOME/.local/bin"
    ".zshenv:$HOME/.zshenv"
    ".bashrc:$HOME/.bashrc"
)

# Commands that must exist before the session can come up. Anything missing
# means the package set has not been installed yet.
SESSION_CMDS=(sway swaybg wayvnc ghostty)

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }

as_root() {
    if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

usage() { sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^#\ \?//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provision) PROVISION="only"; shift ;;
        --no-provision) PROVISION="never"; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        # Everything else belongs to sway-session.
        --port|--bind) LAUNCH_ARGS+=("$1" "$2"); shift 2 ;;
        *) LAUNCH_ARGS+=("$1"); shift ;;
    esac
done

# --- package lists -----------------------------------------------------
read_pkg_file() {
    # Strips blank lines and comments; prints one package per line.
    local file="$1"
    [[ -r "$file" ]] || return 0
    grep -vE '^\s*(#|$)' "$file" || true
}

# Membership in packages/yay is what marks an entry as AUR rather than repo.
repo_pkgs() {
    comm -23 <(read_pkg_file "$WSL_FILE" | sort -u) \
             <(read_pkg_file "$AUR_FILE" | sort -u)
}

aur_pkgs() {
    comm -12 <(read_pkg_file "$WSL_FILE" | sort -u) \
             <(read_pkg_file "$AUR_FILE" | sort -u)
}

# --- state probes ------------------------------------------------------
missing_cmds() {
    local cmd
    for cmd in "${SESSION_CMDS[@]}"; do
        need_cmd "$cmd" || printf '%s\n' "$cmd"
    done
}

unlinked() {
    local entry src dest
    for entry in "${LINKS[@]}"; do
        src="${SCRIPT_DIR}/${entry%%:*}"
        dest="${entry#*:}"
        [[ "$(readlink "$dest" 2>/dev/null)" == "$src" ]] || printf '%s\n' "${entry%%:*}"
    done
}

sway_running() { pgrep -x sway >/dev/null 2>&1; }

# --- install -----------------------------------------------------------
install_packages() {
    if [[ ! -r "$WSL_FILE" ]]; then
        err "$WSL_FILE is missing; nothing to install."
        exit 1
    fi

    local repo aur
    mapfile -t repo < <(repo_pkgs)
    mapfile -t aur < <(aur_pkgs)

    if (( ${#repo[@]} )); then
        log "Installing ${#repo[@]} repo packages from packages/wsl"
        as_root pacman -Syu --noconfirm --needed --quiet
        as_root pacman -S --noconfirm --needed "${repo[@]}"
        ok "pacman batch install succeeded."
    fi

    if (( ${#aur[@]} )); then
        bootstrap_yay
        log "Installing ${#aur[@]} AUR packages with yay"
        yay -S --noconfirm --needed "${aur[@]}"
        ok "yay batch install succeeded."
    fi

    install_lang_packages
    configure_shell
}

bootstrap_yay() {
    need_cmd yay && return 0
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

# The cargo/npm/pip lists are not WSL-filtered — every entry works here.
install_lang_packages() {
    local items item

    mapfile -t items < <(read_pkg_file "$CARGO_FILE")
    if (( ${#items[@]} )) && need_cmd cargo; then
        for item in "${items[@]}"; do
            cargo install --locked "$item"
        done
        ok "cargo crates installed."
    fi

    if [[ -r "$NPM_FILE" ]] && need_cmd npm; then
        local deps
        deps="$(node -e "const p=require('$NPM_FILE'); console.log(Object.keys(p.dependencies||{}).join(' '))")"
        if [[ -n "$deps" ]]; then
            # shellcheck disable=SC2086
            as_root npm install -g $deps
            ok "npm packages installed."
        fi
    fi

    mapfile -t items < <(read_pkg_file "$PIP_FILE")
    if (( ${#items[@]} )) && need_cmd pipx; then
        for item in "${items[@]}"; do
            pipx install "$item" || pipx upgrade "$item"
        done
        ok "pip packages installed."
    fi
}

configure_shell() {
    local current
    current="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current" != "/usr/bin/zsh" ]] && [[ -x /usr/bin/zsh ]]; then
        log "Setting login shell to zsh"
        chsh -s /usr/bin/zsh
    fi
}

# --- link --------------------------------------------------------------
# Creates dest -> src, backing up anything already there that is not already
# the correct symlink. Everything is under $HOME, so no sudo path is needed.
link_one() {
    local src="$1" dest="$2"

    if [[ ! -e "$src" ]]; then
        warn "Source missing, skipping: $src"
        return 0
    fi
    if [[ "$(readlink "$dest" 2>/dev/null)" == "$src" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" || -L "$dest" ]]; then
        local backup="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
        log "Backing up $dest -> $backup"
        mv "$dest" "$backup"
    fi
    log "Linking $dest -> $src"
    ln -sfn "$src" "$dest"
}

link_configs() {
    local entry
    for entry in "${LINKS[@]}"; do
        link_one "${SCRIPT_DIR}/${entry%%:*}" "${entry#*:}"
    done
    ok "Configs linked."
}

provision() {
    local missing unlinked_now
    missing="$(missing_cmds)"
    unlinked_now="$(unlinked)"

    if [[ "$PROVISION" == "only" || -n "$missing" ]]; then
        [[ -n "$missing" ]] && log "Missing: $(tr '\n' ' ' <<<"$missing")"
        install_packages
    fi

    if [[ "$PROVISION" == "only" || -n "$unlinked_now" ]]; then
        [[ -n "$unlinked_now" ]] && log "Not linked: $(tr '\n' ' ' <<<"$unlinked_now")"
        link_configs
    fi

    missing="$(missing_cmds)"
    if [[ -n "$missing" ]]; then
        err "Still missing after provisioning: $(tr '\n' ' ' <<<"$missing")"
        exit 1
    fi
    unlinked_now="$(unlinked)"
    if [[ -n "$unlinked_now" ]]; then
        err "Still not linked: $(tr '\n' ' ' <<<"$unlinked_now")"
        exit 1
    fi
}

report_state() {
    local missing unlinked_now
    missing="$(missing_cmds)"
    if [[ -n "$missing" ]]; then
        warn "Packages not installed: $(tr '\n' ' ' <<<"$missing")"
    else
        ok "Session packages present."
    fi

    unlinked_now="$(unlinked)"
    if [[ -n "$unlinked_now" ]]; then
        warn "Not linked: $(tr '\n' ' ' <<<"$unlinked_now")"
    else
        ok "Configs linked (${#LINKS[@]} entries)."
    fi

    if sway_running; then
        ok "A sway session is running."
    else
        log "No sway session running."
    fi
}

# --- main --------------------------------------------------------------
main() {
    if ! is_wsl; then
        err "Not running under WSL. On bare metal, use install.sh + setup.sh."
        exit 1
    fi

    if (( CHECK_ONLY )); then
        report_state
        exit 0
    fi

    [[ "$PROVISION" == "never" ]] || provision
    if [[ "$PROVISION" == "only" ]]; then
        ok "Provisioned. Start the session with: sway-session"
        exit 0
    fi

    exec "$LAUNCHER" "${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}"
}

main "$@"
