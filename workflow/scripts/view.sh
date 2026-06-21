#!/bin/bash

# Text View Script Source: starts/polls the detached Claude job and prints the
# Text View JSON (spinner + rerun while running, answer when done). Reads Q (the
# prompt) and N (nonce) from the variables set by passthrough.sh.
#
# All view-only logic lives here; common.sh holds only code shared with
# passthrough.sh (json_escape).

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/common.sh"

# ---- Configuration (exported by Alfred from userconfigurationconfig) ----

# Claude CLI binary path.
CLAUDE_CLI="${CLAUDE_CLI_PATH:-$HOME/.local/bin/claude}"

# Model passed to `claude --model`.
CLAUDE_MODEL="${MODEL:-sonnet}"

# Spinner re-poll interval (seconds) for the Text View "rerun" key.
RERUN_INTERVAL="0.5"

# Abort a background job that produced no output after this many seconds.
JOB_TIMEOUT_SECONDS=180

# ---- View JSON ----

# Emit a Text View JSON response.
# Args: $1 - response Markdown (raw)
#       $2 - rerun interval in seconds (optional; omit to stop polling)
emit_view() {
    local resp
    resp=$(printf '%s' "$1" | json_escape)
    if [[ -n "$2" ]]; then
        printf '{"rerun":%s,"response":"%s","behaviour":{"response":"replace","scroll":"start"}}' \
            "$2" "$resp"
    else
        printf '{"response":"%s","behaviour":{"response":"replace","scroll":"start"}}' \
            "$resp"
    fi
}

# ---- Rendering ----

# Render the prompt inside a fenced code block (Alfred's only Markdown element
# that draws a filled, rounded box).
# Uses a fence one backtick longer than the longest backtick run in the prompt
# so prompts containing ``` don't break out of the box.
# Args: $1 - prompt
prompt_header() {
    local prompt="$1" fence='```'
    # Widen the fence past any backtick run in the prompt.
    local run
    run=$(printf '%s' "$prompt" | grep -oE '`+' | awk '{ if (length > m) m = length } END { print m+0 }')
    while (( ${#fence} <= run )); do fence+='`'; done
    printf '%s\n%s\n%s\n\n' "$fence" "$prompt" "$fence"
}

# Build the animated "thinking" spinner Markdown.
# Args: $1 - prompt
#       $2 - path to the start-timestamp file
spinner_text() {
    local prompt="$1" startf="$2"
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local start now elapsed idx
    start=$(cat "$startf" 2>/dev/null || echo 0)
    now=$(date +%s)
    elapsed=$(( now - start ))
    (( elapsed < 0 )) && elapsed=0
    idx=$(( elapsed % ${#frames[@]} ))

    prompt_header "$prompt"
    printf '%s  Asking Claude… _(%ss)_' "${frames[$idx]}" "$elapsed"
}

# ---- Config validation ----

# Validate configuration. On failure prints a Markdown error and returns 1.
validate_config() {
    if [[ ! -f "$CLAUDE_CLI" ]]; then
        printf '## ⚠️ Configuration error\n\nClaude CLI not found at:\n\n`%s`\n\nSet **Claude CLI Path** in the workflow configuration.\n' "$CLAUDE_CLI"
        return 1
    fi
    if [[ ! -x "$CLAUDE_CLI" ]]; then
        printf '## ⚠️ Configuration error\n\nClaude CLI exists but is not executable:\n\n`%s`\n' "$CLAUDE_CLI"
        return 1
    fi
    return 0
}

# ---- Background job ----

# Launch Claude detached, writing the rendered answer (prompt header + output,
# or a fenced error block) to $out.
# Args: $1 - prompt   $2 - output file   $3 - pid file
launch_job() {
    local prompt="$1" out="$2" pidf="$3"
    local tmp="${out}.tmp"

    (
        # Detach from Alfred so the job survives the Text View script returning.
        trap '' HUP INT
        local result=""
        {
            prompt_header "$prompt"
            if result=$("$CLAUDE_CLI" -p "$prompt" --model "$CLAUDE_MODEL" 2>&1); then
                printf '%s\n' "$result"
            else
                printf '## ⚠️ Claude CLI error\n\n```\n%s\n```\n' "$result"
            fi
        } > "$tmp" 2>/dev/null
        mv -f "$tmp" "$out"
        rm -f "$pidf"
    ) >/dev/null 2>&1 &

    echo $! > "$pidf"
    disown 2>/dev/null || true
}

# ---- Text View state machine ----

# Drive one Text View render: start/poll the background Claude job and emit the
# appropriate JSON (spinner+rerun while running, final answer when done).
# Args: $1 - prompt   $2 - per-invocation nonce
run_view() {
    local prompt="$1" nonce="$2"

    if [[ -z "$prompt" ]]; then
        emit_view '## Claude CLI

Type a prompt after the keyword, e.g. `ca explain recursion in one line`.'
        return 0
    fi

    local cfgerr
    if ! cfgerr=$(validate_config); then
        emit_view "$cfgerr"
        return 0
    fi

    local cache="${alfred_workflow_cache:-${TMPDIR:-/tmp}/alfred-claude-cli}"
    mkdir -p "$cache"
    # Drop stale job files (older than ~1 day) to avoid clutter.
    find "$cache" -type f -mtime +1 -delete 2>/dev/null

    local key="${nonce:-default}"
    local out="$cache/$key.out"
    local pidf="$cache/$key.pid"
    local startf="$cache/$key.start"

    # Finished: render the answer and stop polling.
    if [[ -f "$out" ]]; then
        emit_view "$(cat "$out")"
        return 0
    fi

    # Still running: animate the spinner (with a timeout guard).
    if [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf" 2>/dev/null)" 2>/dev/null; then
        local start now elapsed
        start=$(cat "$startf" 2>/dev/null || echo 0)
        now=$(date +%s)
        elapsed=$(( now - start ))
        if (( elapsed > JOB_TIMEOUT_SECONDS )); then
            kill "$(cat "$pidf" 2>/dev/null)" 2>/dev/null
            rm -f "$pidf"
            emit_view "$(prompt_header "$prompt")## ⚠️ Timed out

Claude did not respond within ${JOB_TIMEOUT_SECONDS}s."
            return 0
        fi
        emit_view "$(spinner_text "$prompt" "$startf")" "$RERUN_INTERVAL"
        return 0
    fi

    # Job was started but the pid is gone with no output -> it died.
    if [[ -f "$startf" ]]; then
        emit_view "$(prompt_header "$prompt")## ⚠️ Claude CLI error

The background job ended unexpectedly."
        return 0
    fi

    # First call: start the background job and show the spinner.
    date +%s > "$startf"
    launch_job "$prompt" "$out" "$pidf"
    emit_view "$(spinner_text "$prompt" "$startf")" "$RERUN_INTERVAL"
}

# ---- Entry point ----

run_view "$Q" "$N"
