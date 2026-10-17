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
| `implement` | Work was interrupted. **Start keep-awake** (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>`; it does nothing if already running). Spawn a replacement implementer (next attempt number, PIA.md → Team); it resumes from the `## Steps` checklist in the previous implementer's log. |
| `awaiting-review` | The human has reviewed the map. Mark every card still `Status: agent` as `approved` (in `decisions.md` and `DECISIONS.md`). **Start caffeinate**, check *Works in parallel*, set phase `implement` and spawn the implementer. |
| `test` | Read `round` in `state.json` (missing = `0`) and the last round in `talk.md`. If the log shows a round still being built (no `FIXES DONE` after its `ROUND <R> opened`), it was interrupted: start keep-awake and spawn the next attempt for that round. Otherwise the work waits for the human: ask for their test feedback (or use what they just wrote) and open the next round (PIA.md → Phase 4). Never set `done` unless the human says the work is done. |
| `done` | Tell the human it's done; ask if they want to reopen it (phase `test`, a new round). |

Keep-awake rule, always: on while agents (or you, in a quick fix) work; off when the work waits for the human (`awaiting-review`, `test` between rounds, blocked) or is `done`.
