---
name: auto
description: Switch a PIA work to auto mode — it won't stop after the decision map and keeps going through plan and implementation (e.g. while you sleep).
argument-hint: "[work id or number] [--default]"
disable-model-invocation: true
allowed-tools: Read, Edit, Glob, Bash(ls *), Bash(date *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *)
---

# /pia:auto

**Arguments:** $ARGUMENTS

- With `--default`: set `"mode": "auto"` in `.pia/config.json` (new works start in auto). If a work is also named, switch it too.
- Otherwise find the work: the id or number given; else the active work this session leads (`lead_session` = `${CLAUDE_SESSION_ID}`); else the only work that isn't `done`; else list active works and ask.

Set `"mode": "auto"` and `updated` in its `state.json`, and log the switch.

If its phase is `awaiting-review`, the human is also saying "go": continue exactly as `/pia:continue` does for `awaiting-review` (approve untouched cards, phase `plan`, **start caffeinate**, lead the plan and implementation per `.pia/PIA.md`).

Otherwise reply in one line: the work, and that it won't stop at the decision map.
