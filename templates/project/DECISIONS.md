# Decisions

Project memory. Every decision ever made in this project, each with a permanent ID.

How agents read it: the 📌 Binding section in full, always. From *All decisions*, only the lines for the areas their work touches (search by `[area]`). Past decisions are the default unless there is a stated reason to deviate.

## 📌 Binding

Rules every work in this project follows, in full text.

<!--
### D-NNN · Title  [area]  (was Rule N)
Full text of the rule.
*Where it's enforced:* …
-->

## All decisions

One line per decision: `D-NNN  weight  [area] what was decided · work · status`

- Weights: 📌 binding · 🔴 high · 🟡 medium · 🟢 low · ⏳ reserved (ID taken, card not written yet)
- Areas: short lowercase words that group related decisions (e.g. `reports`, `auth`, `sync`, `ui`). Reuse existing areas before inventing new ones.
- Status: `agent` (decided by an agent) · `human` (decided by the human, e.g. during the intent) · `approved` · `changed`

<!-- D-017  🔴  [reports] PDF is generated on the server · work/003-export-pdf · agent -->
