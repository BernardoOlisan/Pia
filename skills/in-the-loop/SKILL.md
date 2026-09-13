---
name: in-the-loop
description: Switch a PIA work to in-the-loop mode, so it stops when the decision map is finished and waits for you.
argument-hint: "[work id or number] [--default]"
disable-model-invocation: true
allowed-tools: Read, Edit, Glob, Bash(ls *), Bash(date *)
---

# /pia:in-the-loop

**Arguments:** $ARGUMENTS

- With `--default`: set `"mode": "in-the-loop"` in `.pia/config.json` (new works start this way). If a work is also named, switch it too.
- Otherwise find the work: the id or number given; else the active work this session leads (`lead_session` = `${CLAUDE_SESSION_ID}`); else the only work that isn't `done`; else list active works and ask.

Set `"mode": "in-the-loop"` and `updated` in its `state.json`, and log the switch in `log.md`.

Reply in one line. If the work is already past the decision map (phase `plan`, `implement`, `test` or `done`), say that this mode only matters at the decision map, so this work won't stop now.
