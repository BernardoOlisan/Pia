---
name: change
description: Change a PIA decision by its ID (e.g. D-017). Updates the card and project memory, and shows what depends on it.
argument-hint: "D-NNN <new answer and why>"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(date *)
---

# /pia:change

**Change requested:** $ARGUMENTS

Read `.pia/PIA.md` → *Changing a decision*, and follow it:

1. Find the card: grep `D-NNN` in `.pia/work/*/decisions.md` (and the 📌 Binding section of `.pia/DECISIONS.md`). If the new answer is unclear, ask one short question.
2. Update the card: new **Decided** line and reason (the human's reason when given), `Status: changed`, and a history line `Was: {old} ({old status}) · changed YYYY-MM-DD`.
3. Update the decision's line in `.pia/DECISIONS.md`.
4. **Find the impact:** cards whose *Depends on* includes it; steps in that work's `plan.md` tagged `[D-NNN]`; implemented steps in its `log.md`.
5. Log the change in the work's `log.md`.
6. Tell the human, short: what changed, and the impact list (or "nothing else depends on it").
7. If the work is already planned or implemented, add a `## Change D-NNN` phase to `plan.md` covering the affected steps. If the work's mode is `auto`, lead it through implementation (as in `/pia:new` step 3, starting caffeinate while agents run and stopping it when done). If `review`, ask the human for the go first.
