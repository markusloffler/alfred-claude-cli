#!/bin/bash

# Run Script action: instant pass-through. Forwards the prompt (Q) and a
# per-invocation nonce (N) to the Text View as Alfred variables, then returns
# immediately so the launcher never blocks on Claude.

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/common.sh"

qesc=$(printf '%s' "$1" | json_escape)
nonce="$(date +%s)-$$-${RANDOM}"

printf '{"alfredworkflow":{"arg":"","variables":{"Q":"%s","N":"%s"}}}' \
    "$qesc" "$nonce"
