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

**Watch every run for a stall.** The run commands below pass `--thinking`, so a
healthy `opencode run` streams the model's reasoning (`Thinking: …`) and then its
tool calls (`→ Read …`, `$ …`) to stdout within a few seconds — reasoning shows up
*before* the first tool call, so the planning phase is no longer silent and "thinking"
is now distinguishable from "stalled." **Zero output after ~30–60s means the model has
stalled** — almost always because the brief was too open-ended for a cheap model to
plan, so it never emits a first token (not even a thinking block). A stall can sit silent for
20+ minutes; do **not** wait it out. Cap every run with `timeout` so silence fails
fast (the command examples below already do this), and treat exit code 124 as
"re-scope with a sharper, narrower brief," not "retry the same prompt." If you must
kill a run by hand, kill it by **PID** (`pgrep -f deepseek` or read the PID you
backgrounded, then `kill <pid>`) — never `pkill -f "opencode run"`, which also
matches *your own* orchestrating shell command and kills it out from under you.

---

### Phase 0 — Preconditions (once)

1. Confirm a git repo: `git rev-parse --show-toplevel`. If not, stop and tell the
   user to `git init` first — the loop uses `git diff` to review and `git commit`
   to gate.
2. Check the tree is clean, **ignoring the scratch dir** a prior run may have left:
   `git status --porcelain -- . ':!.delegate'`. If anything prints, the tree is dirty
   — **stop and ask** whether to proceed (delegated edits would commingle with their
   work) or stash first. A clean tree makes every source diff attributable to the
   executor. (Plain `git status --porcelain` would flag a leftover `.delegate/` as
   dirty and trip this check on every repeat run — hence the pathspec.)
3. Resolve the executor model and scratch dir, and keep the scratch dir out of git
   locally so it never pollutes a status/diff/read-only check (`.git/info/exclude`
   ignores it without touching the user's tracked `.gitignore`):

   ```bash
   ROOT="$(git rev-parse --show-toplevel)"
   # precedence: DELEGATE_MODEL env > OpenCode resolved default > free fallback
   CFG_MODEL="$(opencode debug config 2>/dev/null | grep -oP '"model"\s*:\s*"\K[^"]+' | head -1)"
   MODEL="${DELEGATE_MODEL:-${CFG_MODEL:-opencode/deepseek-v4-flash-free}}"
   mkdir -p "$ROOT/.delegate"
   grep -qxF '.delegate/' "$ROOT/.git/info/exclude" 2>/dev/null || echo '.delegate/' >> "$ROOT/.git/info/exclude"
   ```

### Phase 1 — EXPLORE (executor)

Relay the user's request to the executor and have it investigate the codebase and
write a **concise, anchored** report — read-only, no edits.

**Scope the brief — a cheap model stalls on an open-ended whole-repo prompt.** "Investigate
the codebase and report everything" routinely produces *zero* output on a real repo:
the model can't plan an unbounded task and never emits a first token (the silent stall
described above). Don't make the executor discover the surface — **name the exact files
to read**, which is cheap to work out yourself first (`git ls-files`, `wc -l` for the
big ones, a `pubspec`/`package.json` peek for stack + tests). Pair that with a short,
specific list of what to look for. If the surface is large, **split it into several
focused passes** — e.g. services, then UI, then project-level — each reading a handful
of named files and writing its **own** `.delegate/report_<area>.md` (separate files so
parallel passes can't clobber each other's appends). Several small, scoped runs beat
one broad run that hangs.

Compose the brief (fill in the bracketed parts) and run from the repo root, **capped
with `timeout`** so a stall fails fast instead of burning 20 minutes:

```bash
timeout 600 opencode run --pure --thinking --dir "$ROOT" -m "$MODEL" --dangerously-skip-permissions "$(cat <<'PROMPT'
You are a read-only code explorer. The user wants: <PASTE the request + any detail/constraints>.
Read ONLY these files (do NOT scan the whole repo): <EXPLICIT file list>.
WRITE your findings to .delegate/report.md and do NOT modify any other file. Keep it
concise and high-signal — a working brief, not a brain dump:
- Relevant files (paths) and why each matters
- Current behavior of the code involved
- Conventions/patterns to match (naming, style, error handling, imports)
- Integration points: where new code hooks in (exact functions/signatures, file:line)
- Tests: how they're run, where they live, the existing test pattern
- Gotchas / constraints
Anchor every claim with file:line, exact signatures, and short quoted snippets so it is
verifiable. If something is unknown, say so — do not guess. Write the file, then STOP.
PROMPT
)" || echo "explore run exited $? (124 = timed out → re-scope with a narrower file list / split into passes)"
```

Then **verify read-only**: `git status --porcelain -- . ':!.delegate'` must be empty
(the `:!.delegate` pathspec drops the scratch dir, which is not necessarily gitignored).
Anything that prints means the executor touched source during exploration; revert it
(`git checkout -- <file>`) and note it. Read `.delegate/report.md` (and any
`report_<area>.md` from extra passes).

**Some tasks end here.** If the request was a question or audit ("what could we
improve?", "how does X work?", "is Y safe?"), the synthesized report *is* the
deliverable — present the findings (spot-checking a few anchors first, as in Phase 2)
and let the user pick what, if anything, to implement. Only continue to Phase 2 once
there is a concrete change to make.

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
and tool-running — you wait, but watch for the stall signature (no streamed output)
and let `timeout` bound it:

```bash
timeout 900 opencode run --pure --thinking --dir "$ROOT" -m "$MODEL" ${DELEGATE_VARIANT:+--variant "$DELEGATE_VARIANT"} \
  --dangerously-skip-permissions "$(cat "$ROOT/.delegate/spec.md")" \
  || echo "implement run exited $? (124 = timed out → tighten or split the spec, then retry)"
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
