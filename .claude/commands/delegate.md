---
description: You are the boss — an OSS model in OpenCode explores the codebase and implements; you only write the spec and review. Saves Claude tokens.
argument-hint: <task to implement>
---

You are **the boss** in an explore → spec → implement → review loop. An
open-source model running in OpenCode is the **executor**, and it does the
token-heavy work: reading the codebase and editing files. You spend Claude tokens
only on the two high-judgment parts — writing the **spec** and **reviewing**. Each
model does what it's good at: the cheap model reads and edits; you reason.

**Do not explore the codebase yourself, and do not write the implementation.** The
executor reads the code and reports back; you write the spec from its report; the
executor implements; you review and loop corrections. If you catch yourself reading
lots of source or editing code, the loop has failed — write a sharper brief or
correction for the executor instead. (Only exception: a trivial one-file change —
just read that file and skip Phase 1.)

Task to implement: **$ARGUMENTS**

Executor runs are **fresh, single-shot** — no persistent session. Cheap models
drift on long multi-turn contexts, and the handoff is files on disk
(`.delegate/report.md`, `.delegate/spec.md`, the git working tree), so every run
gets a clean, focused context with exactly the artifact it needs.

They also run with **`--pure`** (no external opencode plugins). The executor is a
sandboxed code task that doesn't need your personal plugins, and skipping them
keeps runs fast, deterministic, and isolated from plugin-load problems (a stale
plugin in `~/.config/opencode` can otherwise hang bootstrap before the model even
starts). Drop `--pure` only if your executor genuinely needs a custom plugin.

---

### Phase 0 — Preconditions (once)

1. Confirm a git repo: `git rev-parse --show-toplevel`. If not, stop and tell the
   user to `git init` first — the loop uses `git diff` to review and `git commit`
   to gate.
2. Check `git status --porcelain`. If the tree is dirty, **stop and ask** whether
   to proceed (delegated edits would commingle with their work) or stash first. A
   clean tree makes every source diff attributable to the executor.
3. Resolve the executor model and scratch dir:

   ```bash
   ROOT="$(git rev-parse --show-toplevel)"
   # precedence: DELEGATE_MODEL env > OpenCode resolved default > free fallback
   CFG_MODEL="$(opencode debug config 2>/dev/null | grep -oP '"model"\s*:\s*"\K[^"]+' | head -1)"
   MODEL="${DELEGATE_MODEL:-${CFG_MODEL:-opencode/deepseek-v4-flash-free}}"
   mkdir -p "$ROOT/.delegate"
   ```

### Phase 1 — EXPLORE (executor)

Relay the user's request to the executor and have it investigate the codebase and
write a **concise, anchored** report — read-only, no edits. Compose the brief
(fill in the bracketed parts), then run from the repo root:

```bash
opencode run --pure --dir "$ROOT" -m "$MODEL" --dangerously-skip-permissions "$(cat <<'PROMPT'
You are a read-only code explorer. The user wants: <PASTE the request + any detail/constraints>.
Investigate the codebase and WRITE your findings to .delegate/report.md. Do NOT modify
any other file. Keep it concise and high-signal — a working brief, not a brain dump:
- Relevant files (paths) and why each matters
- Current behavior of the code involved
- Conventions/patterns to match (naming, style, error handling, imports)
- Integration points: where new code hooks in (exact functions/signatures, file:line)
- Tests: how they're run, where they live, the existing test pattern
- Gotchas / constraints
Anchor every claim with file:line, exact signatures, and short quoted snippets so it is
verifiable. If something is unknown, say so — do not guess.
PROMPT
)"
```

Then **verify read-only**: `git status --porcelain` must be empty. `.delegate/` is
gitignored, so `report.md` won't appear — anything that *does* appear means the
executor touched source during exploration; revert it (`git checkout -- <file>`)
and note it. Read `.delegate/report.md`.

### Phase 2 — SPEC (you)

From the report, write `.delegate/spec.md`. **Spot-check** a couple of the report's
anchors (read those exact `file:line`s) before trusting it — cheap insurance against
a hallucinated report. If the report has a real gap, do a **targeted** follow-up
explore (re-run Phase 1 with a narrow question) rather than reading the whole
codebase yourself.

```
# Goal
<one sentence>

# Files to create / modify
- path/to/a — <what changes>

# Exact changes
<signatures, behavior, edge cases. Precise enough that a mid-tier model can't
misread it. Don't paste full code unless trivial.>

# Constraints
- Match existing style. Do NOT touch <X>. No new deps unless listed.

# Acceptance criteria
- Command that MUST exit 0: `<test / build / lint command>`
- Observable: <conditions to eyeball in the diff>
```

The spec quality determines whether review passes first try. Be exact about files
and acceptance criteria.

### Phase 3 — IMPLEMENT (executor)

Fresh run; the spec is the handoff. Let OpenCode do all the file reading, editing,
and tool-running — you wait.

```bash
opencode run --pure --dir "$ROOT" -m "$MODEL" ${DELEGATE_VARIANT:+--variant "$DELEGATE_VARIANT"} \
  --dangerously-skip-permissions "$(cat "$ROOT/.delegate/spec.md")"
```

### Phase 4 — REVIEW (you)

1. `git --no-pager diff` — read what the executor actually changed.
2. Run the acceptance command(s) from the spec; capture pass/fail.
3. Judge the diff against the spec: right files only (no scope creep), criteria met,
   no obvious bugs or hallucinated APIs.

### Phase 5 — DECIDE

- **FAIL**: append a `# Correction (attempt N)` section to `.delegate/spec.md`
  stating exactly what's wrong and what to fix, then re-run **Phase 3** (fresh — the
  executor reads the current tree + spec + correction). Escalation ladder:
  - Attempts 1–2: retry on the **free** model.
  - Attempt 3: set `DELEGATE_MODEL=opencode-go/deepseek-v4-flash` (stronger, cheap
    paid) and retry.
  - Attempt 4: **stop.** Show the diff and the failing criteria, and ask the user
    how to proceed. Do not silently take over.
- **PASS**: **hand it to the user — do NOT auto-commit.** Summarize what changed
  (2–3 lines), the acceptance results, and point them at the diff. Wait for their
  OK. On approval:
  `git add -A && git commit -m "<concise msg>  [delegated: $MODEL]"`.

Throughout: your role is the brief, the spec, and judgement — not exploring or
typing code. Reading a little to verify is fine; reading a lot is the signal to
write a sharper brief for the executor instead.
