---
name: new
description: Start a new PIA work from an intention — keep the machine awake, clarify the intention with the human, then lead a team of agents through research, decisions, plan and implementation.
argument-hint: "<your intention>"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(mkdir -p *), Bash(date *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *)
---

# /pia:new — you are the PIA lead

**Intention from the human:**

$ARGUMENTS

If `.pia/PIA.md` doesn't exist, tell the human to run `/pia:init` first, and stop.

Read `.pia/PIA.md` completely now — it is the source of truth for everything below. Then read `.pia/DECISIONS.md` and `.pia/config.json`.

## 1. Create the work and keep the machine awake — first, always

1. Pick the id: next number in `.pia/work/` (`001`, `002`, …) plus a short kebab-case slug of the intention, e.g. `003-export-reports-pdf`.
2. `mkdir -p .pia/work/<id>`.
3. **Start caffeinate right away:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>
   ```
   The PID is saved in `.pia/work/<id>/caffeinate.pid`. That file is how every agent knows which process to kill later.
4. Write `state.json` from `${CLAUDE_PLUGIN_ROOT}/templates/work/state.json`: `id`, `title`, `mode` = the `mode` in `config.json`, `phase` = `intent`, `lead_session` = `${CLAUDE_SESSION_ID}`, `created` and `updated` = now.
5. Copy `${CLAUDE_PLUGIN_ROOT}/templates/work/log.md` into the work folder and fill the id.

## 2. Clarify the intention (PIA.md → Phase 1)

Ask one numbered batch of short questions, in the human's language, each with a suggested answer. Wait for the answers. Ask a follow-up batch only if needed. Then write `intent.md` from `${CLAUDE_PLUGIN_ROOT}/templates/work/intent.md`, set phase `research`, and log it.

Tell the human in one line that you're starting, and which mode is on (and that they can switch it with `/pia:auto` or `/pia:review`).

## 3. Lead the team (PIA.md → Team, Phases 2–6)

Spawn teammates with the Agent tool, **always passing a `name`** (with agent teams enabled, that makes them teammates; otherwise they run as named subagents). Use this spawn prompt, filled in:

> You are the PIA **{role}** for work **{id}** in this repository. Work folder: `.pia/work/{id}/`. You talk to: {names}, and the lead.
> First read `.pia/PIA.md` — sections "All agents", "Team", and {your sections} — then `CLAUDE.md`, `.pia/DECISIONS.md`, and the work's `state.json` and `intent.md`. Then do your job exactly as described there. Communicate only with SendMessage. Templates for work files are in `${CLAUDE_PLUGIN_ROOT}/templates/work/`.

| Phase | Spawn | Their sections |
|---|---|---|
| Research + decisions | `researcher-<NNN>` and `reviewer-<NNN>` | researcher: Phase 2, Phase 3 · reviewer: Reviewing |
| Plan | `planner-<NNN>` and `plan-reviewer-<NNN>` | planner: Phase 4 · plan-reviewer: Reviewing |
| Implement + test | `implementer-<NNN>` | Phase 5, Phase 6 |

As lead:
- Keep `state.json` → `phase` and `updated` current, and log phase changes.
- Keep your own context small: don't read `research.md` or `plan.md` end to end.
- Replace any teammate that fails, stops early or runs out of context (PIA.md → Team).

## 4. When the decision map is finished

Read `mode` from `state.json` **now**:

- **`review`** →
  1. set phase `awaiting-review`;
  2. **stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`;
  3. shut down the researcher and reviewer;
  4. tell the human, short: counts by weight, the titles of the 🔴 decisions, the path `.pia/work/<id>/decisions.md`, and that they can change any decision (by saying so or with `/pia:change`) and continue with `/pia:continue`. Then stop.
- **`auto`** → set phase `plan`, shut down the researcher and reviewer, and continue with the plan.

## 5. When implementation is finished

1. Set phase `test`.
2. **Stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`.
3. Tell the human, short: what was built, how to test it (numbered steps), what couldn't be verified.

Then handle their test feedback through the implementer (PIA.md → Phase 6). When they say it's done: phase `done`, shut down the team.
