---
description: List OpenCode models, or set the global default model OpenCode uses (also the /delegate executor default).
argument-hint: "[provider/model]  (omit to list)"
---

Manage the model OpenCode runs. The global default lives in
`~/.config/opencode/opencode.jsonc` under the `"model"` key, and `/delegate`
honors it (its escalation ladder can still override it for failing tasks).

Argument: **$ARGUMENTS**

---

### If NO argument was given → LIST

1. Run `opencode models` and show the available `provider/model` ids.
2. Read `~/.config/opencode/opencode.jsonc` and report the current default:
   the `"model"` value, or "(none set — falls back to opencode/deepseek-v4-flash-free)"
   if the key is absent.
3. Tell the user: re-run `/opencode-model <provider/model>` to set one.

### If an argument WAS given → SET

1. **Validate.** Run `opencode models` and confirm the exact string
   `$ARGUMENTS` appears as an id. If it does not, show the closest matches and
   **STOP** — never write an unrecognized id.
2. **Write.** Read `~/.config/opencode/opencode.jsonc`, set (or replace) the
   top-level `"model"` key to `$ARGUMENTS`, and write it back. Preserve
   `"$schema"`, any other keys, and any comments — change only `"model"`.
3. **Confirm.** Print the new `"model"` value and note that `/delegate` will now
   use it by default (unless `DELEGATE_MODEL` is set in the environment, which
   takes precedence).
