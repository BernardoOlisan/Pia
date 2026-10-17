---
name: status
description: Show where every PIA work in this project stands: phase, mode, decisions by weight, keep-awake, and what's happening now.
argument-hint: "[work id or number]"
allowed-tools: Read, Glob, Grep, Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/decisions.py" *), Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" *), Bash(ls *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *)
---

# /pia:status

**Work (optional):** $ARGUMENTS

For each work `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" list` prints (repo and disposable; or just the one given), read the summary line of `decisions.md` (if any) and the `## Now` section of `log.md`, and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" status <its folder>`. Mark disposable works with *(disposable)* after the id.

Reply with one short table, newest first, in the human's language:

| Work | Phase | Round | Mode | Decisions | Awake | Now |
|---|---|---|---|---|---|---|

Then, only if something needs the human, one line each: works in `awaiting-review` (read their `decisions.md`), works in `test` (waiting for test feedback), works waiting for another work to finish implementing, and caffeinate running on a work that is waiting or done (offer to stop it).
