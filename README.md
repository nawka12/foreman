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

Foreman is two Claude Code slash commands. Make them available in every project
by linking them into your user commands directory:

```bash
git clone https://github.com/nawka12/foreman.git
cd foreman
mkdir -p ~/.claude/commands
ln -s "$PWD/.claude/commands/delegate.md"       ~/.claude/commands/delegate.md
ln -s "$PWD/.claude/commands/opencode-model.md" ~/.claude/commands/opencode-model.md
```

**Requirements**

- [OpenCode](https://opencode.ai) installed and authenticated
  (`opencode auth login`) for whichever provider serves your executor model.
- A git repo to run `/delegate` in — it uses `git diff` to review and
  `git commit` to gate.

Then, from any project: `/delegate <task>` to delegate work, and
`/opencode-model [provider/model]` to list or set the executor model.

## Model tiers

The executor model is resolved by precedence: `DELEGATE_MODEL` (env) →
OpenCode's global default (`~/.config/opencode/opencode.jsonc`) → free fallback.
An escalation ladder is also built into the command:

| Tier        | Model                              | When                          |
|-------------|------------------------------------|-------------------------------|
| Free        | `opencode/deepseek-v4-flash-free`  | fallback default              |
| Cheap paid  | `opencode-go/deepseek-v4-flash`    | auto-escalation after retries |

Use **`/opencode-model`** to manage the default: no argument lists available
models, a `provider/model` argument sets the global default (which `/delegate`
then uses). `opencode models` also just lists them.

## Caveats

- **Savings depend on the executor being good enough that review usually passes.**
  Too-weak a model means Claude burns tokens reviewing bad diffs and re-specifying,
  which eats the savings. The spec's precision is the main lever.
- The executor runs with `--dangerously-skip-permissions` — free rein in the repo
  dir. Containment = run only inside the project, and every diff is reviewed before
  commit (and revertable via git).
- Requires `opencode` authenticated for the chosen provider (`opencode auth list`).
