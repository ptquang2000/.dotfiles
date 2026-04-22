#!/usr/bin/env bash
# =============================================================================
# setup.sh — Link dotfiles into the appropriate locations on Linux.
#
# Mirrors what setup.bat does for Windows. Creates symlinks from this repo
# into ~/.config, $HOME, and (with sudo) /etc/... as appropriate.
#
# Usage:
#   ./setup.sh            Apply the configuration (creates symlinks, backs up
#                         any pre-existing non-symlink targets).
#   ./setup.sh --dry-run  Print the actions that would be taken without
#                         touching the filesystem.
#
# Idempotent: re-running after a successful setup performs no changes and
# creates no new backups — symlinks that already point at the correct target
# are left untouched.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SUCCESSES=()
FAILURES=()
SKIPPED=()

# ---- logging helpers --------------------------------------------------------

log()  { printf '[setup] %s\n' "$*"; }
warn() { printf '[setup][warn] %s\n' "$*" >&2; }
err()  { printf '[setup][err]  %s\n' "$*" >&2; }

run() {
    if (( DRY_RUN )); then
        printf '  DRY: %s\n' "$*"
    else
        eval "$@"
    fi
}

# ---- core link routine ------------------------------------------------------

# link_into <src> <dest> [label]
#   Creates a symlink at <dest> pointing to <src>. Backs up any existing
#   non-symlink target to <dest>.bak.<timestamp>. Skips when the symlink is
#   already correct. Uses sudo when <dest> is outside $HOME.
link_into() {
    local src="$1"
    local dest="$2"
    local label="${3:-$(basename "$src")}"

    if [[ ! -e "$src" ]]; then
        warn "Source missing, skipping: $src"
        SKIPPED+=("$label (source missing)")
        return 0
    fi

    local sudo_cmd=""
    case "$dest" in
        "$HOME"/*|"$HOME") sudo_cmd="" ;;
        *) sudo_cmd="sudo" ;;
    esac

    local parent
    parent="$(dirname "$dest")"
    if [[ ! -d "$parent" ]]; then
        run "$sudo_cmd mkdir -p '$parent'"
    fi

    # Already the correct symlink? Nothing to do.
    if [[ -L "$dest" ]]; then
        local current
        current="$(readlink "$dest" || true)"
        if [[ "$current" == "$src" ]]; then
            log "OK (already linked): $dest -> $src"
            SUCCESSES+=("$label")
            return 0
        fi
    fi

    # Back up anything already at <dest> that isn't the correct symlink.
    if [[ -e "$dest" || -L "$dest" ]]; then
        local backup="${dest}.bak.${TIMESTAMP}"
        log "Backing up existing $dest -> $backup"
        run "$sudo_cmd mv '$dest' '$backup'"
    fi

    log "Linking $dest -> $src"
    # -s symbolic, -f force, -n treat dest symlink-to-dir as file (no descent).
    if run "$sudo_cmd ln -sfn '$src' '$dest'"; then
        SUCCESSES+=("$label")
    else
        err "Failed to link $label"
        FAILURES+=("$label")
    fi
}

# ---- mappings ---------------------------------------------------------------
#
# Folders intentionally skipped on Linux:
#   powershell/      Windows PowerShell profile (handled by setup.bat)
#   bucket/          Scoop bucket metadata (Windows-only)
#   psmux/           PowerShell tmux clone (Windows-only)
#   zen/             Browser profile data — user-specific, don't auto-link
#   assets/          Static assets consumed by other steps, not a config dir
#   packages/        Package lists consumed by install.sh, not a config dir
#   .git/ .gitignore .gitmodules install.bat setup.bat install.sh setup.sh README.md

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

log "Repo root: $SCRIPT_DIR"
log "Config home: $CONFIG_HOME"
(( DRY_RUN )) && log "Dry-run mode: no changes will be made."

# --- ~/.config/* symlinks ----------------------------------------------------
link_into "$SCRIPT_DIR/hypr"              "$CONFIG_HOME/hypr"              "hypr"
link_into "$SCRIPT_DIR/waybar"            "$CONFIG_HOME/waybar"            "waybar"
link_into "$SCRIPT_DIR/mako"              "$CONFIG_HOME/mako"              "mako"
link_into "$SCRIPT_DIR/fcitx5"            "$CONFIG_HOME/fcitx5"            "fcitx5"
link_into "$SCRIPT_DIR/ghostty"           "$CONFIG_HOME/ghostty"           "ghostty"
link_into "$SCRIPT_DIR/mpv"               "$CONFIG_HOME/mpv"               "mpv"
link_into "$SCRIPT_DIR/zathura"           "$CONFIG_HOME/zathura"           "zathura"
link_into "$SCRIPT_DIR/nvim-init"         "$CONFIG_HOME/nvim"              "nvim"
link_into "$SCRIPT_DIR/zsh"               "$CONFIG_HOME/zsh"               "zsh"
link_into "$SCRIPT_DIR/tmux"              "$CONFIG_HOME/tmux"              "tmux"
link_into "$SCRIPT_DIR/tmux-sessionizer"  "$CONFIG_HOME/tmux-sessionizer"  "tmux-sessionizer"

# --- $HOME dotfiles ----------------------------------------------------------
link_into "$SCRIPT_DIR/.zshenv"           "$HOME/.zshenv"                  ".zshenv"
link_into "$SCRIPT_DIR/.bashrc"           "$HOME/.bashrc"                  ".bashrc"
link_into "$SCRIPT_DIR/.local/bin"        "$HOME/.local/bin"               ".local/bin"

# --- system paths (require sudo) --------------------------------------------
# Note: symlinking a directory from $HOME into /etc works but is fragile when
# the repo moves. We still use ln -sfn (matching the README) so edits in the
# repo take effect immediately; users who prefer copies can adjust manually.
if [[ -d "$SCRIPT_DIR/sddm.conf.d" ]]; then
    link_into "$SCRIPT_DIR/sddm.conf.d"     "/etc/sddm.conf.d"             "sddm.conf.d (sudo)"
fi
if [[ -d "$SCRIPT_DIR/resolved.conf.d" ]]; then
    link_into "$SCRIPT_DIR/resolved.conf.d" "/etc/systemd/resolved.conf.d" "resolved.conf.d (sudo)"
fi

# ---- summary ----------------------------------------------------------------

echo
log "==================== Summary ===================="
log "Linked / already-correct: ${#SUCCESSES[@]}"
for s in "${SUCCESSES[@]:-}"; do [[ -n "$s" ]] && printf '  + %s\n' "$s"; done
if (( ${#SKIPPED[@]} )); then
    log "Skipped: ${#SKIPPED[@]}"
    for s in "${SKIPPED[@]}"; do printf '  - %s\n' "$s"; done
fi
if (( ${#FAILURES[@]} )); then
    log "Failures: ${#FAILURES[@]}"
    for s in "${FAILURES[@]}"; do printf '  ! %s\n' "$s"; done
    exit 1
fi
log "Done."
