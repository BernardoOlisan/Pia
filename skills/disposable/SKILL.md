---
name: disposable
description: Start a disposable PIA work — PIA's continuity (log, Now, talk, decisions when they matter, resume from any session) without the team and without leaving anything in the repo. Also "drop" to throw one away and "adopt" to turn one into a normal work.
argument-hint: "<what you want> | drop [work] | adopt [work]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" *), Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/decisions.py" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" *), Bash(mkdir -p *), Bash(date *), Bash(ls *), Bash(git rev-parse *)
---

# /pia:disposable (you are the lead of a disposable work)

**Arguments:** $ARGUMENTS

A disposable work is PIA for small or short-lived projects: everything a session can't do for itself — a log with `## Now`, the conversation, decisions when there are real forks, keep-awake, notifications, and picking it up from any later session with `/pia:continue` — and nothing else. **No team by default, no `/pia:init`, and nothing in the repository:** it lives in `~/.pia/disposable/<project key>/<NNN-slug>/`, so the project can be migrated, handed over or deleted with no trace of PIA in it.

You work directly, like any session — but every step goes through the log, so the next session (or the human) can see exactly where it stands.

Read these sections of `${CLAUDE_PLUGIN_ROOT}/templates/project/PIA.md` now and follow them: *All agents* (rules 3, 6–10), *Writing for the human*, *Keep-awake*, *Phase 4* (rounds, quick fix, only the human closes), *Changing a decision*.

## `drop [work]`

Find the work (the number, else the one this session leads, else ask among `works.py list` entries with `"kind": "disposable"`). Tell the human in one line what will be deleted (folder, number of log entries, decisions) and **ask them to confirm**. On yes: `awake.sh stop <folder>`, then delete the folder with your file tools (it is outside the repo; nothing else references it). Reply in one line.

## `adopt [work]`

The disposable work grew into something the project should remember. It needs `.pia/` in the repo: if `.pia/PIA.md` doesn't exist, tell the human to run `/pia:init` first, and stop. Then:

1. Pick the new id with `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" next-id <slug>` (repo, not disposable).
2. Reserve project-wide decision IDs for every card (`next-decision-id.sh <project root> <new id> <count>`), renumber the cards and every reference to them inside the work's files, and replace each reserved line in `.pia/DECISIONS.md` with the card's real line.
3. Move the folder there, set `"kind": "repo"` and the new `id` in `state.json`, run `decisions.py summary`, and log `adopted from disposable <old id>`.
4. Tell the human in one line. From now on it is a normal work (`.pia/PIA.md` applies in full).

## Starting one

If no intention was given, say "Va, cuéntame" in their language and wait.

1. **Create it.** `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" next-id <short-slug> --disposable` gives the folder; `mkdir -p <folder>/logs`.
2. `state.json` from `${CLAUDE_PLUGIN_ROOT}/templates/work/state.json`, with `"kind": "disposable"`, `id` = the folder name, `title`, `mode` = `in-the-loop` (or `out-of-the-loop` if the arguments say so), `phase` = `work`, `round` = `0`, `lead_session` = `${CLAUDE_SESSION_ID}`, `created`/`updated` from `date '+%Y-%m-%d %H:%M'`.
3. `log.md` and `talk.md` from the templates. In `talk.md` keep only *Intention*, *Decided by you* and *The conversation*; fill what the human said.
4. Log `disposable work created` with the log script (`--phase work --round 0`). **Every** later step goes through it.
5. Tell the human in one line: the work's number, that nothing goes into the repo, and that `/pia:continue` picks it up from any session.

## While you work

- **Talk only as much as the work needs.** Ask what you can't find out; don't run a talk phase for a one-hour task.
- **Log as you go:** each meaningful step, what you found, what you changed, what failed, what you are waiting on. `## Now` must always say where things stand.
- **Decisions only for real forks** — a choice the human would want to know about later, or a constraint they set. Create `decisions.md` from the template the first time one appears. IDs are local to this work (`D-001`, `D-002`…; `next-decision-id.sh` is not used until adoption). Same card format, `Status: human` for what they settled, `decisions.py summary` after each change.
- **`talk.md` keeps up:** what the human asked and settled, in their terms.
- **Help when it pays:** for a long, separable job (a build, a long investigation) you may spawn a named helper (`helper-<NNN>-<round>-<attempt>`) with PIA.md's spawn rules. Otherwise do it yourself.
- **Keep-awake** on while you or a helper work unattended, off when you wait for the human.
- **Rounds:** when you hand something to the human to try, set phase `test`. Each batch of their feedback is a round (PIA.md → Phase 4). Only the human closes the work; then phase `done`. A done disposable work stays on disk until they `drop` it.
- **Before a long pause or when the context is getting full**, make sure `## Now` says exactly what is next: that line is the handoff.
