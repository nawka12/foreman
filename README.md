# Foreman

Steer an **open-source model** to do the heavy code work while keeping **Claude**
as the boss — writing the spec and reviewing — to save tokens.

In agentic coding, token cost is dominated by *reading*: pulling files into
context to understand the code, then the read-edit-iterate loop. Foreman pushes
**both** onto a free/cheap OSS model running inside [OpenCode](https://opencode.ai)
— it explores the codebase and implements — and keeps Claude on the two
high-judgment parts: turning a report into a tight **spec**, and **reviewing** the
diff. Claude reads a one-page report instead of the whole codebase.

```
┌─ OpenCode (explorer) ────────────────────────────────────┐
│ EXPLORE  read the codebase, write an anchored report      │  free / cheap tokens
│          → .delegate/report.md   (read-only)              │
└──────────────────────────┬───────────────────────────────┘
                           │ report
                           ▼
┌─ Claude (boss) ──────────────────────────────────────────┐
│ SPEC    write a tight spec from the report                │  worth Claude tokens
│         → .delegate/spec.md                               │
└──────────────────────────┬───────────────────────────────┘
                           │ spec
                           ▼
┌─ OpenCode (executor) ────────────────────────────────────┐
│ IMPLEMENT  opencode run --dangerously-skip-permissions    │  free / cheap tokens
│            the read-edit-iterate loop happens here        │  (the heavy part)
└──────────────────────────┬───────────────────────────────┘
                           │ git diff
                           ▼
┌─ Claude (boss) ──────────────────────────────────────────┐
│ REVIEW  read diff, run acceptance cmd                     │  worth Claude tokens
│         pass → hand to you for OK   |   fail → re-delegate │
└───────────────────────────────────────────────────────────┘
```

Every executor run is **fresh and single-shot** — no persistent session (cheap
models drift on long contexts; the files on disk are the handoff).

## Usage

From inside a git repo:

```
/delegate <describe the task to implement>
```

The OSS model explores and reports; Claude writes the spec from that report and
reviews the resulting diff against acceptance criteria, looping a correction back
to the executor when it fails. On pass, Claude **hands you the reviewed result for
a final OK** before committing — you stay out of the inner loop but keep the last
word.

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
  which eats the savings. The levers: a sharp **brief** Claude relays for the
  explore step, and a precise **spec** built on a report Claude spot-checks (rather
  than trusts blindly) before specifying.
- The executor runs with `--dangerously-skip-permissions` — free rein in the repo
  dir. Containment = run only inside the project; the explore step is verified
  read-only (`.delegate/` is gitignored, so a clean `git status` proves it touched
  no source); and every diff is reviewed, handed to you for a final OK, then
  committed (and revertable via git).
- Requires `opencode` authenticated for the chosen provider (`opencode auth list`).
