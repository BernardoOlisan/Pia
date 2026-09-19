---
name: change
description: Change a PIA decision by its ID (e.g. D-017). Updates the card and project memory, and shows what depends on it.
argument-hint: "D-NNN <new answer and why>"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(date *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" *)
---

# /pia:change

**Change requested:** $ARGUMENTS

Read `.pia/PIA.md` → *Changing a decision*, and follow it. You (the lead) make the change yourself:

1. Find the card: grep `D-NNN` in `.pia/work/*/decisions.md` (and the 📌 Binding section of `.pia/DECISIONS.md`). If the new answer is unclear, ask one short question.
2. Update the card: new **Decided** line and reason (the human's reason when given), `Status: changed`, and a history line `Was: {old} ({old status}) · changed YYYY-MM-DD`.
3. Update the decision's line in `.pia/DECISIONS.md`.
4. **Find the impact:** cards whose *Depends on* includes it; steps tagged `[D-NNN]` in the `## Steps` checklist of that work's implementer logs; implemented steps in its logs.
5. Log the change with the log script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh" .pia/work/<id>/log.md "changed D-NNN …" --doing "<now>" --phase <phase>`. The history date comes from `date '+%Y-%m-%d'`.
6. Tell the human, short: what changed, and the impact list (or "nothing else depends on it").
7. If the work is already implemented, the change goes to an implementer as a round of test feedback (PIA.md → Phase 4), with the affected steps named. If the work's mode is `out-of-the-loop`, start it (caffeinate on while it works, off when it reports). If `in-the-loop`, ask the human for the go first.
