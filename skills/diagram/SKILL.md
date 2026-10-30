---
name: diagram
description: Draw a diagram of how something works or how a change alters the code: flow, sequence, database schema, or where it lives in the code. Use it only when the human asks for a diagram, never on your own.
argument-hint: "[what to draw]"
allowed-tools: Read, Write, Glob, Grep, Artifact, Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/diagram.py" *), Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" *), Bash(mkdir -p *)
---

# /pia:diagram

**What to draw:** $ARGUMENTS

You write the text; the script gives it PIA's look. Never hand-draw SVG, never write CSS, never pick a colour.

## 1. Pick only what the question needs

| View | File | When |
|---|---|---|
| Flow | `1-flow.mmd`, or `1-before.mmd` + `2-after.mmd` | How it works, or how a change moves it. Always stack before and after as two files; side by side they shrink until nobody can read them |
| Sequence | `3-sequence.mmd` | Three or more actors, and the order matters |
| Schema | `4-schema.mmd` | The data changes. Only the tables and columns the answer turns on |
| Code | `5-code.tsv` | Where it lives, so the human can open it |

One view is often enough.

## 2. Write it from what is true

Read the real code first. A diagram of what you assume is worse than none.

- In the human's language, in their words: what the product does, not how the code names it.
- **At most 12 boxes.** If it doesn't fit, make two diagrams.
- **Every arrow is a verb:** `saves`, `queues`, `polls every 30 s`. Never `POST /x` or a function call.
- Stop at components and files, never functions.
- **What changes gets `class <ids> changed`, what goes away gets `class <ids> removed`,** and its label also says so in words (`new`, `goes away`), because colour must never be the only signal. Don't define classes or colours: the script does.
- A sequence has no classes: wrap what is new in `rect rgb(44, 46, 120)` … `end`.
- A schema marks the changed table with `class` and with the word in its name: `jobs["jobs · new"] { … }`.

Each `.mmd` starts with two comments, then the diagram:

```
%% title: The flow after this change
%% caption: One sentence on what the picture shows.
flowchart LR
  a["Phone records"] -->|"uploads"| b["1 · API queues the job · new"]
  class b changed
```

`5-code.tsv` is tab-separated with no header: step number (matching the box), path from the repo root, line, what it does, decision, state.

## 3. Build and publish

The folder is `<work folder>/diagrams/<short-name>/` (`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/works.py" lead ${CLAUDE_SESSION_ID}` finds a lead's work; a teammate already knows its own). Outside any work, use the scratchpad.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/diagram.py" page <folder> "<title in the human's language>" "<one-line summary>"
```

Publish the `page.html` it prints with the Artifact tool, with `icon: "diagram"`. To change a diagram, edit its source, run the script again and publish the same file, so the link stays the same.

Give the human the link. In a work, the lead adds it to `talk.md`.
