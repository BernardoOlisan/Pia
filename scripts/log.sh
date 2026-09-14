#!/usr/bin/env bash
# Write one PIA log entry with the real time, and refresh the log's "## Now" in the same step.
#
#   log.sh <log file> "<what happened>" --doing "<what you're doing now>" [--next ..] [--blockers ..] [--phase ..] [--team ..]
#
# Agents never write log entries by hand: the time would be guessed and "## Now" would go stale.
exec python3 "$(dirname "$0")/log.py" "$@"
