#!/usr/bin/env python3
"""Write PIA's Claude Code settings into <project>/.claude/settings.json.

    pia-settings.py <project-dir>            use the compact window from .pia/config.json
    pia-settings.py <project-dir> <tokens>   set a new window (e.g. 500k, 400000, 1m) and save it to config.json

Merges, never clobbers: only `autoCompactWindow` and `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` are touched.
Claude Code silently ignores a non-integer `autoCompactWindow`, so the value is always written as an integer.
"""
import json
import re
import sys
from pathlib import Path

MIN_TOKENS = 100_000
MAX_TOKENS = 1_000_000
DEFAULT_TOKENS = 600_000


def parse_tokens(text):
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*([km]?)\s*", str(text).lower())
    if not match:
        raise ValueError(f"can't read '{text}' as tokens (examples: 500k, 400000, 1m)")
    number, unit = float(match.group(1)), match.group(2)
    tokens = int(number * {"": 1, "k": 1_000, "m": 1_000_000}[unit])
    if not MIN_TOKENS <= tokens <= MAX_TOKENS:
        raise ValueError(f"{tokens} tokens is outside the allowed range (100k to 1M)")
    return tokens


def read_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as error:
        sys.exit(f"pia-settings: {path} is not valid JSON ({error}); fix it first, nothing was changed")


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    project = Path(sys.argv[1]).resolve()
    config_path = project / ".pia" / "config.json"
    settings_path = project / ".claude" / "settings.json"

    config = read_json(config_path, {"mode": "in-the-loop", "compact": DEFAULT_TOKENS})
    try:
        tokens = parse_tokens(sys.argv[2] if len(sys.argv) == 3 else config.get("compact", DEFAULT_TOKENS))
    except ValueError as error:
        sys.exit(f"pia-settings: {error}")

    settings = read_json(settings_path, {})

    if config_path.parent.exists():
        config["compact"] = tokens
        write_json(config_path, config)

    settings["autoCompactWindow"] = tokens
    settings.setdefault("env", {})["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
    write_json(settings_path, settings)

    print(f"pia-settings: autoCompactWindow = {tokens} tokens, agent teams enabled → {settings_path}")
    print("pia-settings: takes effect the next time Claude Code starts in this project")


if __name__ == "__main__":
    main()
