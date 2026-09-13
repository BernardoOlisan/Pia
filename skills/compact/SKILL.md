---
name: compact
description: Set how many tokens a PIA project's sessions fill before auto-compacting (e.g. 500k). Saved per project.
argument-hint: "<tokens, e.g. 500k>"
disable-model-invocation: true
allowed-tools: Bash(git rev-parse *), Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pia-settings.py" *)
---

# /pia:compact

**New window:** $ARGUMENTS

If no value was given, read `.pia/config.json` and tell the human the current `compact` value, then stop.

Otherwise find the repo root (`git rev-parse --show-toplevel`, else the current directory) and run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pia-settings.py" "<repo root>" "$ARGUMENTS"
```

It saves the value in `.pia/config.json` and writes it as an integer to `autoCompactWindow` in `.claude/settings.json`.

Reply in one line: the new value, and that it applies from the next time Claude Code starts in this project.
