#!/usr/bin/env bash
# =============================================================================
# setup.sh — link this repo's configs into place on bare-metal Arch.
#
#   ./setup.sh            Link everything. Whatever is in the way is backed up
#                         to <dest>.bak.<timestamp> first.
#   ./setup.sh --dry-run  Print what would happen and touch nothing.
#
# Re-running is a no-op: links that already point into the repo are left alone.
# Windows is setup.bat's job; WSL is wsl.sh's, which links a smaller subset and
# also installs packages.
#
# Deliberately not linked here: powershell/, bucket/, psmux/ (Windows-only),
# assets/ and packages/ (data, not config).
# =============================================================================

set -euo pipefail

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"

DRY=0
case "${1:-}" in
    --dry-run|-n) DRY=1 ;;
    -h|--help) sed -n '2,/^# ===/p' "$0" | sed 's/^#\ \?//'; exit 0 ;;
    "") ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

log() { printf '[setup] %s\n' "$*"; }

# link <src> <dest> — point dest at src, backing up anything already there.
# sudo is used only for destinations outside $HOME.
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
    if (( DRY )); then
        log "would link $dest -> $src"
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

log "Repo: $DOTS"
(( DRY )) && log "Dry run; nothing will change."

# --- ~/.config ---------------------------------------------------------------
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

# --- $HOME -------------------------------------------------------------------
link "$DOTS/.zshenv"          "$HOME/.zshenv"
link "$DOTS/.bashrc"          "$HOME/.bashrc"

# --- ~/.local/bin ------------------------------------------------------------
# One link per executable, because the tools come from two directories:
# scripts/ and the virutils submodule. Older runs made ~/.local/bin a symlink
# to scripts/; that has to go, or every link below lands inside the repo.
if [[ -L "$BIN" ]]; then
    log "replacing the $BIN symlink with a real directory"
    (( DRY )) || rm -f "$BIN"
fi
(( DRY )) || mkdir -p "$BIN"
for src in "$DOTS"/scripts/* "$DOTS"/virutils/vir*; do
    link "$src" "$BIN/${src##*/}"
done

# --- /etc (sudo) -------------------------------------------------------------
# Symlinked rather than copied so repo edits take effect immediately; the
# tradeoff is that moving the repo breaks them.
link "$DOTS/sddm.conf.d"              "/etc/sddm.conf.d"
link "$DOTS/systemd/resolved.conf.d"  "/etc/systemd/resolved.conf.d"

log "Done."
