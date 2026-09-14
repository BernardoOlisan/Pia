---
name: new
description: Start a new PIA work from an intention. Keeps the machine awake, clarifies the intention with the human, then leads a team of agents through research, decisions, plan and implementation.
argument-hint: "<your intention> | --voice"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Monitor, Bash(ls *), Bash(mkdir -p *), Bash(date *), Bash(git rev-parse *), Bash(swift build *), Bash("${CLAUDE_PLUGIN_ROOT}/voice/.build/release/pia-voice" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" *)
---

# /pia:new (you are the PIA lead)

**Intention from the human:**

$ARGUMENTS

If `.pia/PIA.md` doesn't exist, tell the human to run `/pia:init` first, and stop.

Read `.pia/PIA.md` completely now; it is the source of truth for everything below. Then read `.pia/config.json`, and from `.pia/DECISIONS.md` the 📌 Binding section plus the lines for the areas this intention touches.

**Logging, always:** every entry in your `log.md` goes through the log script, which stamps the real time and refreshes `## Now`:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/<id>/log.md "<what happened>" --doing "<now>" --phase <phase> [--team "…"] [--next "…"] [--blockers "…"]
```
Never write entries or times by hand. Other times (`state.json`) come from `date '+%Y-%m-%d %H:%M'`.

## 1. Create the work and keep the machine awake (first, always)

1. Pick the id: next number in `.pia/work/` (`001`, `002`, …) plus a short kebab-case slug of the intention, e.g. `003-export-reports-pdf`.
2. `mkdir -p .pia/work/<id>/logs`.
3. **Start caffeinate right away:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>
   ```
   The PID is saved in `.pia/work/<id>/caffeinate.pid`. That file is how every agent knows which process to kill later.
4. Write `state.json` from `${CLAUDE_PLUGIN_ROOT}/templates/work/state.json`: `id`, `title`, `mode` = the `mode` in `config.json`, `phase` = `intent`, `lead_session` = `${CLAUDE_SESSION_ID}`, `created` and `updated` = now.
5. Copy `${CLAUDE_PLUGIN_ROOT}/templates/work/log.md` into the work folder, fill the id, and log "work created" with the script. This is your log; only you write it.

## 2. Clarify the intention (PIA.md → Phase 1 and *Writing for the human*)

This is the most important conversation with the human. Ask what they want and why, in the human's language, like a friendly colleague: the outcome in business terms, who it's for, what done looks like, scope, constraints and preferences. Small numbered rounds, short questions, each with a suggested answer in plain words.

- Technical questions only when the answer changes what research has to look at, or it's a choice the human clearly wants to make.
- Don't diagnose or propose solutions, and don't put file names or code in the questions: that's research.
- Answers that are really decisions go under *Decided by the human*.

Then write `intent.md` from `${CLAUDE_PLUGIN_ROOT}/templates/work/intent.md`, set phase `research`, and log it.

### With `--voice`: the whole intent is a conversation

If the arguments contain `--voice`, the human says the intention and answers your questions by talking (PIA.md → Phase 1 → *By voice*). Nothing else about the intent changes: you still think the questions, and you are the only one who writes `intent.md`.

1. **Binary.** If `${CLAUDE_PLUGIN_ROOT}/voice/.build/release/pia-voice` doesn't exist, tell the human it's being built once (a few minutes), and run `swift build -c release --package-path "${CLAUDE_PLUGIN_ROOT}/voice"`. If it fails, tell the human and continue the intent in the terminal.
2. **Start it** right after creating the work, with the Monitor tool (persistent, so every line reaches you as an event):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/voice/.build/release/pia-voice" intent .pia/work/<id>
   ```
   Create `intent.md` from the template first, so pia-voice can watch it. Tell the human in one line: "Talk when you're ready; the notch is listening."
3. **React to its lines**, logging each one (`FROM VOICE: …`):
   - `PIA-VOICE READY {…}`: nothing to do.
   - `PIA-VOICE INTENT {json}`: fill the top of `intent.md` with it (it may come again with changes). Read the code you need, then write `### Round N` under `## Clarifications`, numbered questions, each with `*Suggested: …*`, in the human's language. Same rules as typed questions.
   - `PIA-VOICE ANSWERS R<n> {json}`: write each answer after its question as ` → answer`, and add the ones with `decided_by_human: true` under *Decided by the human*. Then either write the next round, or, when the intent is clear, finish `intent.md` and add the line `<!-- pia-voice: ready to confirm -->` at its top.
   - `PIA-VOICE CONFIRMED`: remove that line, set phase `research`, log it, and continue with the team. pia-voice exits by itself.
   - `PIA-VOICE ENDED {json}`: the human stopped the voice. Record what it carries, and continue the intent in the terminal from the current round.
   - `PIA-VOICE ERROR {json}`: tell the human in one line and continue the intent in the terminal.
4. If the human types in the terminal while the voice runs, accept it as an answer too. If they ask to stop the voice, stop the Monitor task: pia-voice prints `PIA-VOICE ENDED` and exits.

Tell the human in one line that you're starting, and which mode is on (they can switch with `/pia:in-the-loop` or `/pia:out-of-the-loop`).

## 3. Lead the team (PIA.md → Team, Phases 2 to 6)

Spawn teammates with the Agent tool, **always passing a `name`** (with agent teams enabled, that makes them teammates; otherwise they run as named subagents). Use this spawn prompt, filled in:

> You are the PIA **{role}** for work **{id}** in this repository. Work folder: `.pia/work/{id}/`. Your log: `.pia/work/{id}/logs/{your name}.md` (create it from `${CLAUDE_PLUGIN_ROOT}/templates/work/agent-log.md`). You talk to: {names}, and the lead.
> First read `.pia/PIA.md` (sections "All agents", "Team", and {your sections}), then `CLAUDE.md`, `.pia/DECISIONS.md` as PIA.md says, and the work's `state.json` and `intent.md`. Then do your job exactly as described there. Communicate only with SendMessage.
> Log only with the log script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/{id}/logs/{your name}.md "<what happened>" --doing "<what you're doing now>"`.
> Templates for work files: `${CLAUDE_PLUGIN_ROOT}/templates/work/`. Decision ID script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" <project root> {id} <count>`.
> {For a replacement or a test-round implementer: resume from the files, the `## Now` of `log.md`, and `logs/{previous agent}.md`. The items to fix: …}

| Phase | Spawn | Their sections |
|---|---|---|
| Research + decisions | `researcher-<NNN>` and `reviewer-<NNN>` | researcher: Phase 2, Phase 3 · reviewer: Reviewing |
| Plan | `planner-<NNN>` and `plan-reviewer-<NNN>` | planner: Phase 4 · plan-reviewer: Reviewing |
| Implement | `implementer-<NNN>` | Phase 5 |
| Each round of test feedback | a fresh `implementer-<NNN>-2`, `-3`… | Phase 5, Phase 6 |

As lead:
- Keep `state.json` (`phase`, `updated`) current, and log with the script: phase changes, spawns, replacements, every report from a teammate (`PHASE DONE`, `APPROVED`, `DECISIONS DONE`, …) and every message to or from the human.
- Keep your own context small: don't read `research.md` or `plan.md` end to end.
- Replace any teammate that fails, stops early or runs out of context (PIA.md → Team). If Claude Code says the human stopped it, ask the human in one line first.

## 4. When the decision map is finished

Read `mode` from `state.json` **now**:

- **`in-the-loop`** →
  1. set phase `awaiting-review`;
  2. **stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`;
  3. shut down the researcher and reviewer;
  4. tell the human, short: counts by weight (and how many they decided in the intent), the titles of the 🔴 decisions, the path `.pia/work/<id>/decisions.md`, and that they can change any decision (by saying so or with `/pia:change`) and continue with `/pia:continue`. Then stop.
- **`out-of-the-loop`** → set phase `plan`, shut down the researcher and reviewer, and continue with the plan.

## 5. Before implementing

Check the other works' `state.json` (PIA.md → *Works in parallel*). If another work is in `implement`: keep phase `plan`, write the blocker in `## Now`, **stop caffeinate**, tell the human in one line, and stop. Otherwise set phase `implement` and spawn the implementer.

## 6. When implementation is finished

1. Set phase `test`.
2. **Stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`.
3. Shut down the implementer.
4. Tell the human, short (PIA.md → *Writing for the human*): what was built, how to test it (numbered steps), what couldn't be verified, and any decision you need them to confirm (log each as `ASKED D-NNN: …`).

Then handle their test feedback per PIA.md → Phase 6: record changed decisions first, then a fresh implementer for each round, with caffeinate on while it works. Before `done`, ask once more about every `ASKED` decision still unanswered. When they say it's done: phase `done`, shut down the team.
