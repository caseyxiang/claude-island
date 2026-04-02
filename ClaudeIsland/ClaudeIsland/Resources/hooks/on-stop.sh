#!/bin/bash
# Claude Island — Stop hook
# Only notifies for non-interactive (oneshot / -p) sessions.
# Interactive sessions fire Stop on every response — too noisy.
INPUT=$(cat)

# Extract fields
SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('session_id', d.get('sessionId', '')))
" 2>/dev/null)

CWD=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('cwd', ''))
" 2>/dev/null)

TRANSCRIPT=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('transcript_path', d.get('transcriptPath', '')))
" 2>/dev/null)

# Check session kind from ~/.claude/sessions/{pid}.json
# Only notify for non-interactive (oneshot) sessions
SESSIONS_DIR="$HOME/.claude/sessions"
IS_INTERACTIVE="false"
if [ -d "$SESSIONS_DIR" ]; then
    for f in "$SESSIONS_DIR"/*.json; do
        [ -f "$f" ] || continue
        FILE_SID=$(python3 -c "import sys,json; print(json.load(open('$f')).get('sessionId',''))" 2>/dev/null)
        if [ "$FILE_SID" = "$SESSION_ID" ]; then
            KIND=$(python3 -c "import sys,json; print(json.load(open('$f')).get('kind',''))" 2>/dev/null)
            if [ "$KIND" = "interactive" ]; then
                IS_INTERACTIVE="true"
            fi
            break
        fi
    done
fi

# Skip notification for interactive sessions
if [ "$IS_INTERACTIVE" = "true" ]; then
    exit 0
fi

# Send notification for non-interactive (oneshot) sessions
MSG="{\"type\":\"stop\",\"sessionId\":\"${SESSION_ID}\",\"transcriptPath\":\"${TRANSCRIPT}\",\"cwd\":\"${CWD}\"}"
echo "$MSG" | nc -U /tmp/claude-island.sock 2>/dev/null

exit 0
