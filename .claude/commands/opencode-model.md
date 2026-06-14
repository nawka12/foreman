---
description: List OpenCode models, or set the global default model OpenCode (and /delegate) use. Runs a deterministic script — no config editing by hand.
argument-hint: "[provider/model]  (omit to list)"
---

This command is a thin wrapper around a script that does all the work
deterministically — **do not** list models, edit any config file, or "verify" the
model yourself. Just run the companion script and relay its output verbatim.

Run exactly this:

```bash
bash "$HOME/.claude/commands/opencode-model.sh" $ARGUMENTS
```

If that file doesn't exist, the install step that symlinks `opencode-model.sh`
next to the command was skipped — find `opencode-model.sh` in the Foreman repo's
`.claude/commands/` and run that, and tell the user to add the missing symlink.

Then report the script's stdout/stderr to the user as-is. The script:

- **no argument** → lists `provider/model` ids and the current effective model.
- **`provider/model` argument** → validates it against `opencode models`, writes the
  `"model"` key into OpenCode's global config (preserving other keys and comments),
  and **verifies** it became the effective model — reporting an override (e.g. a
  project-level `opencode.json`) instead of falsely claiming success.

Exit codes: `0` ok · `2` unknown model · `3` written but a higher-precedence config
is overriding it. On `2` or `3`, surface the script's diagnostic; don't retry by
editing files yourself.

> **Variants** (reasoning effort `high`/`max`/`minimal`) are a separate axis from the
> model id — set per run via `opencode run --variant <v>` (TUI: `ctrl+t`), or for
> delegated runs via `DELEGATE_VARIANT`. They are not stored in `"model"`.
