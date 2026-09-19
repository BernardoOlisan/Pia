---
name: continue
description: Resume a PIA work after reviewing its decision map, after a restart, or in a new session. Picks up from state.json and the logs.
argument-hint: "[work id or number]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(mkdir -p *), Bash(date *), Bash(git rev-parse *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" *)
---

# /pia:continue (resume as the PIA lead)

**Work:** $ARGUMENTS

1. **Find the work.** Match the argument against `.pia/work/*` (a number like `3` or `003` is enough). With no argument: if exactly one work is not `done`, use it; otherwise list the active ones (id, title, phase) and ask which.
2. **Load it.** Read `.pia/PIA.md` completely, then the work's `state.json`, `talk.md`, the `## Now` of `log.md`, and the `## Now` of each file in `logs/`. Set `lead_session` = `${CLAUDE_SESSION_ID}` and update `updated` (time from `date '+%Y-%m-%d %H:%M'`). Log that the lead resumed, with the log script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/<id>/log.md "lead resumed" --doing "<now>" --phase <phase>`. Every later entry goes through the script too.
3. **Continue from the phase.** You are the lead: follow `/pia:new` steps 2 to 7 (spawn prompt, team table, mode check, parallel check) and PIA.md from here.

| Phase | What to do |
|---|---|
| `talk` | Check `mode` first. `in-the-loop` → carry on the conversation from where it stopped. `out-of-the-loop` → don't ask anything: close the talk yourself (PIA.md → Phase 1 → *When the human isn't there*) and go to `decisions`. Either way, start caffeinate if it isn't running, and spawn a fresh `scout-<NNN>` if the old one is gone — it resumes from `research.md` and its own log. |
| `decisions` | If `## Now` says it is waiting for another work to finish implementing, check again (PIA.md → *Works in parallel*): still blocked → tell the human and stop; free → **start caffeinate** and move to implement. Otherwise it was interrupted: **start caffeinate** and spawn a fresh scout and scout reviewer, telling them to resume from the files, `## Now` in `log.md`, and the log of the agent they replace. |
| `implement` | Work was interrupted. **Start caffeinate** (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>`; it does nothing if already running). Spawn a fresh implementer; it resumes from the `## Steps` checklist in the previous implementer's log. |
| `awaiting-review` | The human has reviewed the map. Mark every card still `Status: agent` as `approved` (in `decisions.md` and `DECISIONS.md`). **Start caffeinate**, check *Works in parallel*, set phase `implement` and spawn the implementer. |
| `test` | Ask the human for their test feedback (or use what they just wrote). Append it to `## The conversation` in `talk.md`, record changed decisions first, then spawn a fresh implementer for the round (PIA.md → Phase 4), with caffeinate on while it works. |
| `done` | Tell the human it's done; ask if they want to reopen it for more fixes (phase `test`). |

Caffeinate rule, always: running while agents work unattended; stopped when the work waits for the human (`awaiting-review`, `test`, blocked) or is `done`.
