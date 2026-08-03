#!/usr/bin/env bash
# =====================================================================
#  wsl.sh
#
#  SYNOPSIS
#    Provisions the WSL workstation: installs packages, sets the login
#    shell and links configs. It does not start a session.
#
#  DESCRIPTION
#    This is the only provisioning script to run on a WSL distro.
#    install.sh and setup.sh are for bare-metal Arch and must NOT be run
#    here: they install hyprland, sddm and waydroid, none of which can
#    work in the WSL VM, and they link a desktop config set this host has
#    no use for. Everything WSL-specific lives in this file, packages/wsl,
#    sway/ and scripts/sway-session.
#
#      1. Install packages    packages/wsl, an inclusive list; entries
#                             also present in packages/yay come from the
#                             AUR, the rest from the repos. Then the
#                             cargo/npm/pip lists, which are unfiltered.
#      2. Set the login shell zsh, via chsh. Takes effect the next time
#                             the distro is launched, not in this shell.
#      3. Restore interop     Re-registers the WSLInterop binfmt handler
#                             that systemd wipes on boot, so .exe files
#                             stay runnable. See NOTES.
#      4. Link configs        The subset of the repo that applies here —
#                             see LINKS below. The only /etc write is the
#                             binfmt config in step 3; otherwise sudo is
#                             needed only for the package install.
#
#    Every step is idempotent and skipped when it has nothing to do, so
#    re-running is cheap. Steps are also independent: a package that
#    fails to build is reported but does not stop the shell and link
#    steps from running. The exit status reflects the final state, so a
#    clean exit means the host is fully provisioned.
#
#    Starting the desktop is a separate concern, handled by
#    scripts/sway-session. It is on PATH once this script has run,
#    because scripts/ is linked to ~/.local/bin:
#
#        sway-session              # foreground; Ctrl-C ends it
#        sway-session -d           # detached, logging to /tmp/sway.log
#        sway-session --stop
#        sway-session -d --port 5901 --bind 127.0.0.1
#
#    Then connect TigerVNC Viewer on Windows to localhost:<port>.
#
#  USAGE
#    ./wsl.sh                 Provision whatever is missing, then exit.
#    ./wsl.sh --force         Re-run every step even if it looks done.
#    ./wsl.sh --check         Report what is missing and exit.
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
#      /etc/binfmt.d/ satisfies the condition and makes the fix survive
#      reboots.
#    - There is no audio: VNC has no audio channel and
#      /mnt/wslg/PulseServer is not reachable from that session.
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

ZSH_BIN="/usr/bin/zsh"

# Windows interop, re-registered for systemd's benefit. The interpreter is
# /init, WSL's own hand-off binary; P passes the original argv[0] through and
# F loads the interpreter now rather than at exec time, so it keeps working
# inside mount namespaces that cannot see /init.
BINFMT_CONF="/etc/binfmt.d/WSLInterop.conf"
BINFMT_LINE=":WSLInterop:M::MZ::/init:PF"

FORCE=0
CHECK_ONLY=0

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

# Commands that must exist once provisioning is done. Anything missing means
# the package set has not been installed, or failed to install.
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
        --force) FORCE=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown argument: $1"; err "Try --help."; exit 2 ;;
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

login_shell() { getent passwd "$USER" | cut -d: -f7; }

# True while the login shell is still whatever the distro image shipped.
shell_wrong() { [[ "$(login_shell)" != "$ZSH_BIN" ]]; }

# WSL names the handler WSLInterop, or WSLInterop-late on builds that defer
# the registration; either one means .exe files run.
interop_live() {
    [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ||
       -e /proc/sys/fs/binfmt_misc/WSLInterop-late ]]
}

# Wrong when interop is dead now, or alive but with nothing on disk to bring
# it back after the next boot.
interop_wrong() {
    ! interop_live || [[ "$(cat "$BINFMT_CONF" 2>/dev/null)" != "$BINFMT_LINE" ]]
}

# --- install -----------------------------------------------------------
# Failures here warn rather than abort: the shell and link steps are
# independent of the package set and must still run. main() re-checks the
# state afterwards and exits non-zero if anything is genuinely missing.
install_packages() {
    if [[ ! -r "$WSL_FILE" ]]; then
        err "$WSL_FILE is missing; nothing to install."
        return 1
    fi

    local repo aur rc=0
    mapfile -t repo < <(repo_pkgs)
    mapfile -t aur < <(aur_pkgs)

    if (( ${#repo[@]} )); then
        log "Installing ${#repo[@]} repo packages from packages/wsl"
        if as_root pacman -Syu --noconfirm --needed --quiet &&
           as_root pacman -S --noconfirm --needed "${repo[@]}"; then
            ok "pacman batch install succeeded."
        else
            warn "pacman install failed; continuing."
            rc=1
        fi
    fi

    if (( ${#aur[@]} )); then
        if bootstrap_yay; then
            log "Installing ${#aur[@]} AUR packages with yay"
            if yay -S --noconfirm --needed "${aur[@]}"; then
                ok "yay batch install succeeded."
            else
                warn "yay install failed; continuing."
                rc=1
            fi
        else
            warn "yay unavailable; skipped ${#aur[@]} AUR packages."
            rc=1
        fi
    fi

    install_lang_packages || rc=1
    return $rc
}

bootstrap_yay() {
    need_cmd yay && return 0
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
    local items item rc=0

    mapfile -t items < <(read_pkg_file "$CARGO_FILE")
    if (( ${#items[@]} )) && need_cmd cargo; then
        for item in "${items[@]}"; do
            cargo install --locked "$item" || { warn "cargo: $item failed."; rc=1; }
        done
        ok "cargo crates processed."
    fi

    if [[ -r "$NPM_FILE" ]] && need_cmd npm; then
        local deps
        deps="$(node -e "const p=require('$NPM_FILE'); console.log(Object.keys(p.dependencies||{}).join(' '))")"
        if [[ -n "$deps" ]]; then
            # shellcheck disable=SC2086
            if as_root npm install -g $deps; then
                ok "npm packages installed."
            else
                warn "npm install failed."
                rc=1
            fi
        fi
    fi

    mapfile -t items < <(read_pkg_file "$PIP_FILE")
    if (( ${#items[@]} )) && need_cmd pipx; then
        for item in "${items[@]}"; do
            pipx install "$item" || pipx upgrade "$item" || { warn "pipx: $item failed."; rc=1; }
        done
        ok "pip packages processed."
    fi

    return $rc
}

# --- login shell -------------------------------------------------------
# A first-class step, not a tail-end of the package install: on a host where
# the packages are already present this is the only thing left to do. chsh
# authenticates through PAM on its own, separately from the sudo used above,
# so it prompts for a password and can be declined — that must not be fatal.
configure_shell() {
    if [[ ! -x "$ZSH_BIN" ]]; then
        warn "$ZSH_BIN not installed; leaving login shell as $(login_shell)."
        return 1
    fi
    if ! shell_wrong; then
        return 0
    fi
    if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
        warn "$ZSH_BIN is not listed in /etc/shells; chsh will refuse it."
        return 1
    fi

    log "Setting login shell to zsh (takes effect next time the distro starts)"
    if chsh -s "$ZSH_BIN"; then
        ok "Login shell set to $ZSH_BIN."
    else
        warn "chsh failed or was declined; run 'chsh -s $ZSH_BIN' by hand."
        return 1
    fi
}

# --- windows interop ---------------------------------------------------
# Writes the handler systemd needs and, if it is not already loaded, asks
# systemd-binfmt to load it so this shell can run .exe files without a
# distro restart. Reachable only through sudo, so like configure_shell it
# can be declined and must not be fatal.
configure_interop() {
    if [[ "$(cat "$BINFMT_CONF" 2>/dev/null)" != "$BINFMT_LINE" ]]; then
        log "Registering the WSLInterop binfmt handler in $BINFMT_CONF"
        if ! as_root install -Dm644 /dev/stdin "$BINFMT_CONF" <<<"$BINFMT_LINE"; then
            warn "Could not write $BINFMT_CONF; .exe files will stop working on reboot."
            return 1
        fi
    fi

    if interop_live; then
        ok "Windows interop registered."
        return 0
    fi

    if [[ ! -d /run/systemd/system ]]; then
        warn "Interop is dead and systemd is not running; restart the distro."
        return 1
    fi

    if as_root systemctl restart systemd-binfmt && interop_live; then
        ok "Windows interop restored."
    else
        warn "systemd-binfmt did not register the handler; restart the distro."
        return 1
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

# --- provision ---------------------------------------------------------
# Each step decides for itself whether it has work to do. None of them can
# abort the others, so a single failure never leaves the host half-set-up
# in a way that a re-run would not fix.
provision() {
    local missing unlinked_now
    missing="$(missing_cmds)"
    unlinked_now="$(unlinked)"

    if (( FORCE )) || [[ -n "$missing" ]]; then
        [[ -n "$missing" ]] && log "Missing: $(tr '\n' ' ' <<<"$missing")"
        install_packages || true
    fi

    if (( FORCE )) || shell_wrong; then
        configure_shell || true
    fi

    if (( FORCE )) || interop_wrong; then
        configure_interop || true
    fi

    if (( FORCE )) || [[ -n "$unlinked_now" ]]; then
        [[ -n "$unlinked_now" ]] && log "Not linked: $(tr '\n' ' ' <<<"$unlinked_now")"
        link_configs
    fi
}

# Reports the state and returns non-zero if the host is not fully provisioned.
# The login shell is advisory: chsh can legitimately be declined, and nothing
# else in the repo depends on it, so it warns but does not fail the run.
report_state() {
    local missing unlinked_now rc=0

    missing="$(missing_cmds)"
    if [[ -n "$missing" ]]; then
        warn "Packages not installed: $(tr '\n' ' ' <<<"$missing")"
        rc=1
    else
        ok "Session packages present."
    fi

    if shell_wrong; then
        warn "Login shell is $(login_shell), not $ZSH_BIN."
    else
        ok "Login shell is zsh."
    fi

    if ! interop_live; then
        warn "Windows interop is dead; .exe files will fail with 'exec format error'."
        rc=1
    elif [[ "$(cat "$BINFMT_CONF" 2>/dev/null)" != "$BINFMT_LINE" ]]; then
        warn "Windows interop works now but $BINFMT_CONF is missing; it will break on reboot."
        rc=1
    else
        ok "Windows interop registered."
    fi

    unlinked_now="$(unlinked)"
    if [[ -n "$unlinked_now" ]]; then
        warn "Not linked: $(tr '\n' ' ' <<<"$unlinked_now")"
        rc=1
    else
        ok "Configs linked (${#LINKS[@]} entries)."
    fi

    return $rc
}

# --- main --------------------------------------------------------------
main() {
    if ! is_wsl; then
        err "Not running under WSL. On bare metal, use install.sh + setup.sh."
        exit 1
    fi

    if (( CHECK_ONLY )); then
        report_state || true
        exit 0
    fi

    provision

    echo
    if ! report_state; then
        err "Provisioning incomplete; re-run ./wsl.sh once the errors above are resolved."
        exit 1
    fi
    ok "Provisioned. Start the desktop with: sway-session"
}

main "$@"
