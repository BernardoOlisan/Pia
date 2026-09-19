---
name: out-of-the-loop
description: Switch a PIA work to out-of-the-loop mode, so it doesn't stop at the decision map and keeps going through plan and implementation (e.g. while you sleep).
argument-hint: "[work id or number] [--default]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(date *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *)
---

# /pia:out-of-the-loop

**Arguments:** $ARGUMENTS

- With `--default`: set `"mode": "out-of-the-loop"` in `.pia/config.json` (new works start this way). If a work is also named, switch it too.
- Otherwise find the work: the id or number given; else the active work this session leads (`lead_session` = `${CLAUDE_SESSION_ID}`); else the only work that isn't `done`; else list active works and ask.

Set `"mode": "out-of-the-loop"` and `updated` in its `state.json`, and log the switch with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/<id>/log.md "mode → out-of-the-loop" --doing "<what the lead is doing>" --phase <phase>`.

Then, by phase:

- **`talk`** — the human is leaving mid-conversation. Stop asking at once (PIA.md → Phase 1 → *When the human isn't there*): take the questions they left unanswered **and the ones you were still going to ask**, turn each into a decision of your own with its reason and the line `Asked you during the talk; you were away.`, and write into `talk.md` the closing summary you would have demonstrated, saying they did not confirm it. **Start caffeinate** if it isn't running, set phase `decisions`, and carry on with the team. Reply in one line before you go quiet: how many questions became decisions, and that you'll have it done when they're back.
- **`awaiting-review`** — the human is also saying "go": continue exactly as `/pia:continue` does for `awaiting-review` (approve untouched cards, **start caffeinate**, phase `implement`, lead the implementation per `.pia/PIA.md`).
- **anything else** — reply in one line: the work, and that it won't stop at the decision map.
