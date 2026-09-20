---
name: new
description: Start a new PIA work from an intention. Keeps the machine awake, then talks it through with you while a scout investigates in parallel, turns it into a decision map, and builds it.
argument-hint: "<your intention> [--voice] [--out-of-the-loop]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Monitor, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/voice-say.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/voice-bin.sh" *), Bash(ls *), Bash(mkdir -p *), Bash(date *), Bash(git rev-parse *), Bash(swift build *), Bash("${CLAUDE_PLUGIN_ROOT}/voice/.build/release/pia-voice" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" *)
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

If the human gave no intention, say one line — "Va, cuéntame" in their language — wait for their first message, and name the work from that.

1. Pick the id: next number in `.pia/work/` (`001`, `002`, …) plus a short kebab-case slug of the intention, e.g. `003-export-reports-pdf`.
2. `mkdir -p .pia/work/<id>/logs`.
3. **Start caffeinate right away:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>
   ```
   The PID is saved in `.pia/work/<id>/caffeinate.pid`. That file is how every agent knows which process to kill later.
4. Write `state.json` from `${CLAUDE_PLUGIN_ROOT}/templates/work/state.json`: `id`, `title`, `mode` = `out-of-the-loop` if the arguments contain `--out-of-the-loop` (`--in-the-loop` likewise), else the `mode` in `config.json`; `phase` = `talk`, `lead_session` = `${CLAUDE_SESSION_ID}`, `created` and `updated` = now.
5. Copy `${CLAUDE_PLUGIN_ROOT}/templates/work/log.md` and `talk.md` into the work folder, fill the id and whatever the human already said, and log "work created" with the script.

## 2. Spawn the scout immediately (before your first question)

The investigation runs **during** the talk, not after it. Spawn `scout-<NNN>` now (step 4 has the spawn prompt), with whatever the human has said so far, even if it is one line. Tell it to start from the area that intention touches and to report back short.

The human never talks to the scout. You do, in one line at a time.

## 3. The talk (PIA.md → Phase 1, and *Writing for the human*)

One conversation that is the intention and the research at once. Follow Phase 1 exactly.

**Check `mode` in `state.json` before every question you would put to the human**, not once at the end. If it is `out-of-the-loop`, ask them nothing: turn every question you would have asked — including any you already asked and they never answered — into a decision of your own, marked `Asked you during the talk; you were away.`, close the talk yourself, and go to step 4 (PIA.md → Phase 1 → *When the human isn't there*). If they switch mid-talk, that takes effect on the spot.

In short, while they are in the loop:

- **One or two questions at a time**, in the human's language, like a colleague. No numbered rounds.
- **Ask only what the scout can't find out.** Send the scout what to look at as the talk moves; ask it direct questions and take two-or-three-line answers. **Never read `research.md`** — that is how your context stays small.
- **Ask informed:** say what was found when it changes the question, so the human gets a fork instead of a blank page.
- Record what the human settles under *Decided by you* in `talk.md`; those become `Status: human` cards.
- **End by demonstrating you understood:** summarise the work back to them — intention, scope, what matters most — and ask them to confirm. If they correct it or add something, carry on; the talk is never closed.

Write `talk.md` as you go, from `${CLAUDE_PLUGIN_ROOT}/templates/work/talk.md`. Then set phase `decisions`, log it, and tell the human in one line which mode is on (they can switch with `/pia:in-the-loop` or `/pia:out-of-the-loop`).

### With `--voice`: the talk happens out loud

If the arguments contain `--voice`, the human talks and you answer through the notch (PIA.md → Phase 1 → *By voice*). You are still the brain and the only writer of `talk.md`. With `--out-of-the-loop` there is nobody to talk to, so say that in one line and skip the voice.

1. **Binary.** If `${CLAUDE_PLUGIN_ROOT}/voice/.build/release/pia-voice` doesn't exist, tell the human it's being built once (a few minutes), and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/voice-bin.sh" build`. If it fails, tell the human and carry on in the terminal.
2. **Start it first**, before anything else you would do for the work, with the Monitor tool (persistent, so every line reaches you as an event):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/voice/.build/release/pia-voice" intent .pia/work/<id>
   ```
   It greets the human by itself and tells them you're catching up, so they are not left in silence while you read the code.
3. **Talk with the say script**, never by writing to the inbox file:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/voice-say.sh" .pia/work/<id> "what you want to say"
   ```
   Your normal writing voice; the voice turns it into speech. **One idea per message**, and don't repeat in the terminal what you just said out loud — put the exact names, versions, prices and links there instead.
4. **React to its lines**, logging each one (`FROM VOICE: …`):
   - `PIA-VOICE SAID {"text": …}`: what the human said. Treat it exactly as if they had typed it — record decisions under *Decided by you*, ask the scout, answer with the say script. **If it means they are done talking, stop the Monitor task yourself** and carry on in the terminal.
   - `PIA-VOICE ENDED {"reason": …}`: the voice stopped, not the human. Unless the reason clearly says they are leaving, stay `in-the-loop` and carry on in the terminal, writing normally again. If it does say they are leaving, follow PIA.md → Phase 1 → *When the human isn't there*.
   - `PIA-VOICE ERROR {"message": …}`: the voice is broken. **Stop saying things** — nothing will be heard. Tell the human in one line, in plain words, and carry on in the terminal.
5. If the human types in the terminal while the voice runs, that is an answer too.

## 4. Lead the team (PIA.md → Team, Phases 2 to 4)

Spawn teammates with the Agent tool, **always passing a `name`** (with agent teams enabled, that makes them teammates; otherwise they run as named subagents). Use this spawn prompt, filled in:

> You are the PIA **{role}** for work **{id}** in this repository. Work folder: `.pia/work/{id}/`. Your log: `.pia/work/{id}/logs/{your name}.md` (create it from `${CLAUDE_PLUGIN_ROOT}/templates/work/agent-log.md`). You talk to: {names}, and the lead.
> First read `.pia/PIA.md` (sections "All agents", "Team", and {your sections}), then `AGENTS.md`, `.pia/DECISIONS.md` as PIA.md says, and the work's `state.json` and `talk.md`. Then do your job exactly as described there. Communicate only with SendMessage.
> Log only with the log script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/{id}/logs/{your name}.md "<what happened>" --doing "<what you're doing now>"`.
> Templates for work files: `${CLAUDE_PLUGIN_ROOT}/templates/work/`. Decision ID script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" <project root> {id} <count>`.
> {For the scout during the talk: the lead will send you what to look at and direct questions. Answer in two or three lines, never with a document.}
> {For a replacement or a test-round implementer: resume from the files, the `## Now` of `log.md`, and `logs/{previous agent}.md`. The items to fix: …}

| When | Spawn | Their sections |
|---|---|---|
| The moment the work is created | `scout-<NNN>` | Phase 1 (its part), Phase 2 |
| When the talk ends | `scout-reviewer-<NNN>` | Reviewing |
| Implement | `implementer-<NNN>` | Phase 3 |
| Each round of test feedback | a fresh `implementer-<NNN>-2`, `-3`… | Phase 3, Phase 4 |

As lead:
- Keep `state.json` (`phase`, `updated`) current, and log with the script: phase changes, spawns, replacements, every report from a teammate (`STEP DONE`, `APPROVED`, `DECISIONS DONE`, …) and every message to or from the human.
- Keep your own context small: don't read `research.md` end to end.
- Replace any teammate that fails, stops early or runs out of context (PIA.md → Team). If Claude Code says the human stopped it, ask the human in one line first.

## 5. When the decision map is finished

Read `mode` from `state.json` **now**:

- **`in-the-loop`** →
  1. set phase `awaiting-review`;
  2. **stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`;
  3. shut down the scout and the scout reviewer;
  4. tell the human, short: first the titles of any cards that say *you were away*, then counts by weight (and how many they decided in the talk), the titles of the 🔴 decisions, the path `.pia/work/<id>/decisions.md`, and that they can change any decision (by saying so or with `/pia:change`) and continue with `/pia:continue`. Then stop.
- **`out-of-the-loop`** → shut down the scout and the scout reviewer, and go to step 6.

## 6. Before implementing

Check the other works' `state.json` (PIA.md → *Works in parallel*). If another work is in `implement`: keep phase `decisions`, write the blocker in `## Now`, **stop caffeinate**, tell the human in one line, and stop. Otherwise set phase `implement` and spawn the implementer, which works out its own steps (PIA.md → Phase 3).

## 7. When implementation is finished

1. Set phase `test`.
2. **Stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`.
3. Shut down the implementer.
4. Tell the human, short (PIA.md → *Writing for the human*): what was built, how to test it (numbered steps), what couldn't be verified, and any decision you need them to confirm (log each as `ASKED D-NNN: …`).

Then handle their test feedback per PIA.md → Phase 4: append it to `## The conversation` in `talk.md`, record changed decisions first, then a fresh implementer for each round, with caffeinate on while it works. Before `done`, ask once more about every `ASKED` decision still unanswered. When they say it's done: mark every card still `Status: agent` as `approved`, set phase `done`, and shut down the team.
