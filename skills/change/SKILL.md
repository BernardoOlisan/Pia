---
name: change
description: Change a PIA decision by its ID (e.g. D-017). Updates the card and project memory, and shows what depends on it.
argument-hint: "D-NNN <new answer and why>"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(date *), Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/decisions.py" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *)
---

# /pia:change

**Change requested:** $ARGUMENTS

Read `.pia/PIA.md` → *Changing a decision*, and follow it. You (the lead) make the change yourself:

1. Find the card: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/decisions.py" card <project root> D-NNN` (it searches every work, disposable ones too, and the 📌 Binding section lives in `.pia/DECISIONS.md`). If the new answer is unclear, ask one short question.
2. Follow PIA.md → *Changing a decision*: keep the past with `decisions.py history`, rewrite the card to the current truth (`Status: changed`, no `Was:` lines), update its one line in `DECISIONS.md`, run `decisions.py summary` on the map.
3. **Find the impact:** cards whose *Depends on* includes it; steps tagged `[D-NNN]` in the `## Steps` checklist of that work's implementer logs; implemented steps in its logs.
4. Log the change with the log script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" <work folder>/log.md "changed D-NNN …" --doing "<now>" --phase <phase>`.
5. Tell the human, short: what changed, and the impact list (or "nothing else depends on it").
6. If the work is already implemented, the change goes into a round (PIA.md → Phase 4). If the work's mode is `out-of-the-loop`, start it (keep-awake on while it works, off when it reports). If `in-the-loop`, ask the human for the go first.
