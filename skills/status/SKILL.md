---
name: status
description: Show where every PIA work in this project stands: phase, mode, decisions by weight, keep-awake, and what's happening now.
argument-hint: "[work id or number]"
allowed-tools: Read, Glob, Grep, Bash(ls *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *)
---

# /pia:status

**Work (optional):** $ARGUMENTS

For each work in `.pia/work/*` (or just the one given), read `state.json`, the summary line of `decisions.md`, and the `## Now` section of `log.md`, and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" status .pia/work/<id>`.

Reply with one short table, newest first, in the human's language:

| Work | Phase | Mode | Decisions | Awake | Now |
|---|---|---|---|---|---|

Then, only if something needs the human, one line each: works in `awaiting-review` (read their `decisions.md`), works in `test` (waiting for test feedback), and caffeinate running on a work that is waiting or done (offer to stop it).
