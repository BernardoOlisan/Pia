---
name: continue
description: Resume a PIA work after reviewing its decision map, after a restart, or in a new session. Picks up from state.json and the logs.
argument-hint: "[work id or number]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(mkdir -p *), Bash(date *), Bash(git rev-parse *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" *)
---

# /pia:continue (resume as the PIA lead)

**Work:** $ARGUMENTS

1. **Find the work.** Match the argument against `.pia/work/*` (a number like `3` or `003` is enough). With no argument: if exactly one work is not `done`, use it; otherwise list the active ones (id, title, phase) and ask which.
2. **Load it.** Read `.pia/PIA.md` completely, then the work's `state.json`, `intent.md`, the `## Now` of `log.md`, and the `## Now` of each file in `logs/`. Set `lead_session` = `${CLAUDE_SESSION_ID}` and update `updated`. Log that the lead resumed.
3. **Continue from the phase.** You are the lead: follow `/pia:new` steps 3 to 6 (spawn prompt, team table, mode check, parallel check) and PIA.md from here.

| Phase | What to do |
|---|---|
| `intent` | Finish clarifying with the human. Start caffeinate if it isn't running. |
| `research`, `decisions`, `implement` | Work was interrupted. **Start caffeinate** (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>`; it does nothing if already running). Spawn fresh teammates for the current phase; tell them to resume from the files, `## Now` in `log.md`, and the log of the agent they replace. |
| `plan` | If `## Now` says it is waiting for another work to finish implementing, check again (PIA.md → *Works in parallel*): still blocked → tell the human and stop; free → **start caffeinate** and move to implement. Otherwise it was interrupted: start caffeinate and spawn fresh planner and plan-reviewer. |
| `awaiting-review` | The human has reviewed the map. Mark every card still `Status: agent` as `approved` (in `decisions.md` and `DECISIONS.md`). Set phase `plan`. **Start caffeinate.** Continue with the plan. |
| `test` | Ask the human for their test feedback (or use what they just wrote) and route it to an implementer. No caffeinate. |
| `done` | Tell the human it's done; ask if they want to reopen it for more fixes (phase `test`). |

Caffeinate rule, always: running while agents work unattended; stopped when the work waits for the human (`awaiting-review`, `test`, blocked) or is `done`.
