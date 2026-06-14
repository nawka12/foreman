#!/usr/bin/env bash
# Foreman installer — links the slash commands into your Claude commands dir so
# `/delegate` and `/opencode-model` work in every project.
#
#   ./install.sh              install (or repair) the symlinks
#   ./install.sh --uninstall  remove the symlinks
#
# The links point back into this repo, so updating is just `git pull` — no
# reinstall needed. Re-run this any time to repair links or pick up new files.
# Override the target dir with CLAUDE_COMMANDS_DIR=/some/path ./install.sh
set -eu

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SRC="$REPO/.claude/commands"
DEST="${CLAUDE_COMMANDS_DIR:-$HOME/.claude/commands}"
FILES="delegate.md opencode-model.md opencode-model.sh"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---- uninstall -------------------------------------------------------------
if [ "${1:-}" = "-u" ] || [ "${1:-}" = "--uninstall" ]; then
  for f in $FILES; do
    dst="$DEST/$f"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$SRC/$f" ]; then
      rm -f "$dst"; info "removed $dst"
    fi
  done
  info "Foreman uninstalled."
  exit 0
fi

if [ -n "${1:-}" ]; then die "unknown argument: $1 (use --uninstall, or no args to install)"; fi

# ---- requirements (warn only) ----------------------------------------------
command -v opencode >/dev/null 2>&1 || warn "'opencode' not on PATH — install it: https://opencode.ai"
command -v perl     >/dev/null 2>&1 || warn "'perl' not on PATH — /opencode-model needs it to edit the config"
command -v git      >/dev/null 2>&1 || warn "'git' not on PATH — /delegate needs a git repo to run in"

# ---- install ---------------------------------------------------------------
mkdir -p "$DEST"
for f in $FILES; do
  src="$SRC/$f"
  dst="$DEST/$f"
  [ -f "$src" ] || die "missing $src — run this from a complete Foreman checkout"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    die "refusing to overwrite a real file: $dst — move it aside and re-run"
  fi
  ln -sfn "$src" "$dst"
  info "linked $f -> $dst"
done
chmod +x "$SRC/opencode-model.sh"

info ""
info "Done. From any project: /delegate <task>  and  /opencode-model [provider/model]"
info "Update later with:  git -C \"$REPO\" pull   (links keep working — no reinstall)"
