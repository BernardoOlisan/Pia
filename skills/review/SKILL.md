---
name: review
description: Switch a PIA work to review mode — it will stop when the decision map is finished and wait for you.
argument-hint: "[work id or number] [--default]"
disable-model-invocation: true
allowed-tools: Read, Edit, Glob, Bash(ls *), Bash(date *)
---

# /pia:review

**Arguments:** $ARGUMENTS

- With `--default`: set `"mode": "review"` in `.pia/config.json` (new works start in review). If a work is also named, switch it too.
- Otherwise find the work: the id or number given; else the active work this session leads (`lead_session` = `${CLAUDE_SESSION_ID}`); else the only work that isn't `done`; else list active works and ask.

Set `"mode": "review"` and `updated` in its `state.json`, and log the switch.

Reply in one line. If the work is already past the decision map (phase `plan`, `implement`, `test` or `done`), say that review mode only matters at the decision map, so this work won't stop now.
