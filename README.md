# Foreman

Steer an **open-source model** to do the heavy code edits while keeping
**Claude** as the foreman — planning and reviewing — to save tokens.

In agentic coding, token cost is dominated by the execute loop: re-reading files
into context, tool calls, retries, dead ends. This setup keeps Claude on the
small, high-value contexts (planning, reviewing a focused diff) and pushes the
expensive loop onto a free/cheap OSS model running inside
[OpenCode](https://opencode.ai).

```
┌─ Claude (planner/reviewer) ──────────────────────────────┐
│ PLAN    explore + write a tight spec  → .delegate/spec.md │  worth Claude tokens
└──────────────────────────┬───────────────────────────────┘
                           │ spec
                           ▼
┌─ OpenCode + OSS model (executor) ────────────────────────┐
│ EXECUTE  opencode run --dangerously-skip-permissions      │  free / cheap tokens
│          the read-edit-iterate loop happens here          │  (the heavy part)
└──────────────────────────┬───────────────────────────────┘
                           │ git diff
                           ▼
┌─ Claude (planner/reviewer) ──────────────────────────────┐
│ REVIEW  read diff, run acceptance cmd                     │  worth Claude tokens
│         pass → git commit   |   fail → re-delegate fix    │
└───────────────────────────────────────────────────────────┘
```

## Usage

From inside a git repo:

```
/delegate <describe the task to implement>
```

Claude writes a spec, hands it to the OSS model, reviews the resulting diff
against acceptance criteria, and commits when it passes (re-delegating a
correction when it doesn't). Review-gated auto-commit — you stay out of the
inner loop.

## Install

Foreman is two Claude Code slash commands. Clone the repo and run the installer —
it links the commands into your user commands directory so they work in every
project:

```bash
git clone https://github.com/nawka12/foreman.git
cd foreman
./install.sh
```

The links point back into the clone, so **updating is just `git pull`** — no
reinstall. Re-run `./install.sh` any time to repair links or pick up new files,
`./install.sh --uninstall` to remove them. (Set `CLAUDE_COMMANDS_DIR` to target a
non-default commands dir.) Prefer doing it by hand? The installer just symlinks
`.claude/commands/{delegate.md,opencode-model.md,opencode-model.sh}` into
`~/.claude/commands/`.

**Requirements**

- [OpenCode](https://opencode.ai) installed and authenticated
  (`opencode auth login`) for whichever provider serves your executor model.
- A git repo to run `/delegate` in — it uses `git diff` to review and
  `git commit` to gate.

Then, from any project: `/delegate <task>` to delegate work, and
`/opencode-model [provider/model]` to list or set the executor model.

## Model tiers

The executor model is resolved by precedence: `DELEGATE_MODEL` (env) →
OpenCode's resolved default (read from `opencode debug config`, so it stays
correct even when a project-level config overrides the global one) → free
fallback. An escalation ladder is also built into the command:

| Tier        | Model                              | When                          |
|-------------|------------------------------------|-------------------------------|
| Free        | `opencode/deepseek-v4-flash-free`  | fallback default              |
| Cheap paid  | `opencode-go/deepseek-v4-flash`    | auto-escalation after retries |

Use **`/opencode-model`** to manage the default: no argument lists available
models and the current effective one, a `provider/model` argument sets the global
default (which `/delegate` then uses) and **verifies** the change actually took
effect — if a project-level `opencode.json` is overriding it, the command says so
instead of silently no-op'ing. `opencode models` also just lists them.

**Variants** (reasoning effort: `high`/`max`/`minimal`) are a separate axis from
the model id, applied per run via `opencode run --variant <v>` (TUI: `ctrl+t`).
Set one for delegated runs with `DELEGATE_VARIANT=<v>`.

## Caveats

- **Savings depend on the executor being good enough that review usually passes.**
  Too-weak a model means Claude burns tokens reviewing bad diffs and re-specifying,
  which eats the savings. The spec's precision is the main lever.
- The executor runs with `--dangerously-skip-permissions` — free rein in the repo
  dir. Containment = run only inside the project, and every diff is reviewed before
  commit (and revertable via git).
- Requires `opencode` authenticated for the chosen provider (`opencode auth list`).
