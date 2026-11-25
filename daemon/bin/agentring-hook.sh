#!/bin/sh
# AgentRing hook shim.
#
# Reads the agent's hook payload from stdin and forwards it to the local
# daemon, then exits. It never writes to stdout (a hook's stdout can be parsed
# as a decision) and always exits 0 so a stopped daemon can never break an
# agent run.
#
#   agentring-hook.sh --source codex
#
# Override the daemon port with AGENTRING_PORT.

SRC=default
if [ "$1" = "--source" ] && [ -n "$2" ]; then
  SRC="$2"
fi

PORT="${AGENTRING_PORT:-7801}"

BODY=$(cat)
# Resolve the log next to this script: codex may run hooks with a restricted
# environment where $HOME is unset.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG="$DIR/hook.log"
# Always keep a short trace: when a hook silently stops firing, this is the only
# way to tell "never invoked" from "invoked but rejected".
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
  mv "$LOG" "$LOG.1"
fi
printf '%s %s %s\n' "$(date +%H:%M:%S)" "$SRC" "$BODY" >> "$LOG" 2>/dev/null

CODE=$(printf '%s' "$BODY" | curl -sS -m 1 --noproxy '*' -o /dev/null -w '%{http_code}' \
  -X POST \
  -H 'content-type: application/json' \
  --data-binary @- \
  "http://127.0.0.1:${PORT}/ingest?source=${SRC}" 2>/dev/null)

printf '  -> %s\n' "${CODE:-failed}" >> "$LOG" 2>/dev/null
exit 0
