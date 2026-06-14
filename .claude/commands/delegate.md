---
description: Plan & review here in Claude; delegate the heavy code edits to an open-source model running in OpenCode (token-saving loop).
argument-hint: <task to implement>
---

You are the **planner + reviewer** in a plan → delegate → review loop. An
open-source model running inside OpenCode is the **executor**. The whole point
is to spend Claude tokens only on planning and reviewing, and push the
token-heavy read-edit-iterate loop onto a cheap/free model.

**Do not write the implementation yourself.** Your edits in the happy path are
zero. If you ever have to step in, say so explicitly — it means the loop failed.

Task to implement: **$ARGUMENTS**

---

### Phase 0 — Preconditions (once)

1. Confirm you're in a git repo: `git rev-parse --show-toplevel`. If not, stop
   and tell the user to `git init` first — the loop uses `git diff` as the
   handoff and `git commit` as the gate.
2. Check `git status --porcelain`. If the tree is dirty, **stop and ask** the
   user whether to proceed (delegated edits would commingle with their work) or
   to stash first. A clean tree makes every diff attributable to the executor.

### Phase 1 — PLAN (you)

Explore only as much as you need to write a precise spec — keep your context
small, that's where the savings come from. Write the spec to `.delegate/spec.md`:

```
# Goal
<one sentence>

# Files to create / modify
- path/to/a.py — <what changes>
- path/to/b.ts — <what changes>

# Exact changes
<signatures, behavior, edge cases. Don't paste full code unless trivial —
describe precisely enough that a mid-tier model can't misread it.>

# Constraints
- Match existing style. Do NOT touch <X>. No new deps unless listed.

# Acceptance criteria
- Command that MUST exit 0: `<test / build / lint command>`
- Observable: <conditions to eyeball in the diff>
```

The spec quality determines whether review passes first try. Vague spec → bad
diff → wasted reloops. Be exact about files and acceptance criteria.

### Phase 2 — DELEGATE (executor)

Run from the repo root. The executor model is resolved by precedence:
`DELEGATE_MODEL` env → OpenCode's resolved default → free fallback. Change the
default with `/opencode-model <provider/model>`. Read the default from
`opencode debug config` (the *resolved* model — correct even when a project-level
`opencode.json` overrides the global one), not by grepping a guessed config file.

```bash
ROOT="$(git rev-parse --show-toplevel)"
# precedence: DELEGATE_MODEL env > OpenCode resolved default > free fallback
CFG_MODEL="$(opencode debug config 2>/dev/null | grep -oP '"model"\s*:\s*"\K[^"]+' | head -1)"
MODEL="${DELEGATE_MODEL:-${CFG_MODEL:-opencode/deepseek-v4-flash-free}}"
# DELEGATE_VARIANT (optional): reasoning effort, e.g. high|max|minimal.
opencode run --dir "$ROOT" -m "$MODEL" ${DELEGATE_VARIANT:+--variant "$DELEGATE_VARIANT"} \
  --dangerously-skip-permissions "$(cat "$ROOT/.delegate/spec.md")"
```

Let OpenCode do all the file reading, editing, and tool-running. You wait.

### Phase 3 — REVIEW (you)

1. `git --no-pager diff` — read what the executor actually changed.
2. Run the acceptance command(s) from the spec; capture pass/fail.
3. Judge the diff against the spec: right files only (no scope creep), criteria
   met, no obvious bugs or hallucinated APIs.

### Phase 4 — DECIDE

- **PASS** (criteria green + diff sound):
  `git add -A && git commit -m "<concise msg>  [delegated: $MODEL]"`.
  Report what changed in 2-3 lines. Done.
- **FAIL**: append a `# Correction (attempt N)` section to `.delegate/spec.md`
  stating exactly what's wrong and what to fix, then re-delegate (Phase 2).
  Escalation ladder:
  - Attempts 1–2: retry on the **free** model with the correction.
  - Attempt 3: set `DELEGATE_MODEL=opencode-go/deepseek-v4-flash` (stronger,
    cheap paid) and retry.
  - Attempt 4: **stop.** Show the diff and the failing criteria, and ask the
    user how to proceed. Do not silently take over.

Throughout: your role is spec + judgement, not typing code. If you catch
yourself about to edit a source file, that's the signal to write a sharper
correction for the executor instead.
