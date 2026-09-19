---
name: in-the-loop
description: Switch a PIA work to in-the-loop mode, so it stops when the decision map is finished and waits for you.
argument-hint: "[work id or number] [--default]"
disable-model-invocation: true
allowed-tools: Read, Edit, Glob, Bash(ls *), Bash(date *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *)
---

# /pia:in-the-loop

**Arguments:** $ARGUMENTS

- With `--default`: set `"mode": "in-the-loop"` in `.pia/config.json` (new works start this way). If a work is also named, switch it too.
- Otherwise find the work: the id or number given; else the active work this session leads (`lead_session` = `${CLAUDE_SESSION_ID}`); else the only work that isn't `done`; else list active works and ask.

Set `"mode": "in-the-loop"` and `updated` in its `state.json`, and log the switch with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/<id>/log.md "mode → in-the-loop" --doing "<what the lead is doing>" --phase <phase>`.

Reply in one line. If the work is already past the decision map (phase `implement`, `test` or `done`), say that this mode only matters at the decision map, so this work won't stop now.
