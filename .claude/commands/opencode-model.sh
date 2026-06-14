#!/usr/bin/env bash
# opencode-model — list OpenCode models, or set the global default model.
#
# Deterministic helper behind the /opencode-model slash command: validate, write
# the "model" key into OpenCode's global config (preserving everything else,
# comments included), then VERIFY against the resolved config so a write that gets
# overridden by a higher-precedence scope is reported instead of faked as success.
#
#   opencode-model                  # list models + show the current effective one
#   opencode-model provider/model   # set the global default
#
# Exit: 0 ok/listed · 1 env error · 2 unknown model · 3 set but not effective.
set -eu

err() { printf '%s\n' "$*" >&2; }

command -v opencode >/dev/null 2>&1 || { err "opencode not found on PATH."; exit 1; }

# Effective model after all config scopes are resolved (authoritative, not a raw
# file read — so it reflects project-level overrides too).
effective_model() {
  opencode debug config 2>/dev/null | grep -oP '"model"\s*:\s*"\K[^"]+' | head -1
}

# ---- LIST mode -------------------------------------------------------------
if [ "$#" -eq 0 ] || [ -z "${1:-}" ]; then
  echo "Available models (provider/model):"
  opencode models 2>/dev/null || { err "could not run 'opencode models'"; exit 1; }
  cur="$(effective_model || true)"
  echo
  if [ -n "${cur:-}" ]; then
    echo "Current effective model: $cur"
  else
    echo "Current effective model: (none set — OpenCode uses its priority default)"
  fi
  echo "Set the global default with:  /opencode-model <provider/model>"
  exit 0
fi

want="$1"

# ---- SET mode --------------------------------------------------------------
command -v perl >/dev/null 2>&1 || { err "perl is required to edit the config."; exit 1; }

# 1) Validate against the real model list — never write an unknown id.
if ! opencode models 2>/dev/null | grep -qxF -- "$want"; then
  err "Unknown model id: $want"
  matches="$(opencode models 2>/dev/null | grep -iF -- "${want##*/}" || true)"
  if [ -n "$matches" ]; then
    err "Closest matches:"
    printf '%s\n' "$matches" | sed 's/^/  /' >&2
  fi
  err "Run /opencode-model with no argument to list all ids."
  exit 2
fi

# 2) Locate the global config file (honour 'opencode debug paths'; handle .json/.jsonc).
cfgdir="$(opencode debug paths 2>/dev/null | awk '$1=="config"{print $2; exit}')"
[ -n "${cfgdir:-}" ] || cfgdir="$HOME/.config/opencode"
mkdir -p "$cfgdir"
if   [ -f "$cfgdir/opencode.jsonc" ]; then cfg="$cfgdir/opencode.jsonc"
elif [ -f "$cfgdir/opencode.json"  ]; then cfg="$cfgdir/opencode.json"
else cfg="$cfgdir/opencode.json"
fi

# 3) Write the "model" key, preserving every other key and any comments.
#    (/e + $ENV avoids regex trouble from the '/' in model ids.)
if [ ! -f "$cfg" ]; then
  printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "model": "%s"\n}\n' "$want" > "$cfg"
elif grep -qP '"model"\s*:\s*"' "$cfg"; then
  LC_ALL=C MODEL="$want" perl -0pi -e 's/("model"\s*:\s*")[^"]*(")/$1 . $ENV{MODEL} . $2/e' "$cfg"
else
  LC_ALL=C MODEL="$want" perl -0pi -e 's/\A(\s*\{)/$1 . "\n  \"model\": \"" . $ENV{MODEL} . "\","/e' "$cfg"
fi

# 4) Verify it actually became the effective model.
got="$(effective_model || true)"
if [ "${got:-}" = "$want" ]; then
  echo "OK — OpenCode (and /delegate) now default to: $want"
  echo "  config file: $cfg"
  echo "  (a DELEGATE_MODEL env var still overrides this for /delegate, if set)"
  exit 0
fi

err "Wrote \"model\": \"$want\" to $cfg, but it is NOT the effective model."
err "  effective model is still: ${got:-<none>}"
err "  A higher-precedence config is winning — most likely a project-level"
err "  opencode.json/.jsonc in your current directory, or the OPENCODE_CONFIG env var."
exit 3
