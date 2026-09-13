---
name: out-of-the-loop
description: Switch a PIA work to out-of-the-loop mode, so it doesn't stop at the decision map and keeps going through plan and implementation (e.g. while you sleep).
argument-hint: "[work id or number] [--default]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(date *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *)
---

# /pia:out-of-the-loop

**Arguments:** $ARGUMENTS

- With `--default`: set `"mode": "out-of-the-loop"` in `.pia/config.json` (new works start this way). If a work is also named, switch it too.
- Otherwise find the work: the id or number given; else the active work this session leads (`lead_session` = `${CLAUDE_SESSION_ID}`); else the only work that isn't `done`; else list active works and ask.

Set `"mode": "out-of-the-loop"` and `updated` in its `state.json`, and log the switch in `log.md`.

If its phase is `awaiting-review`, the human is also saying "go": continue exactly as `/pia:continue` does for `awaiting-review` (approve untouched cards, phase `plan`, **start caffeinate**, lead the plan and implementation per `.pia/PIA.md`).

Otherwise reply in one line: the work, and that it won't stop at the decision map.
