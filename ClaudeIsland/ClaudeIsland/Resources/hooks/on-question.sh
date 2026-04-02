#!/bin/bash
# Claude Island — PreToolUse hook for AskUserQuestion
# Receives JSON via stdin when Claude asks the user a question.
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
QUESTION=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
if isinstance(ti,dict):
    print(ti.get('question','Claude is asking a question'))
else:
    print(str(ti)[:200])
" 2>/dev/null)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)

# Escape quotes
QUESTION_ESCAPED=$(echo "$QUESTION" | sed 's/"/\\"/g' | tr '\n' ' ')

MSG=$(cat <<EOF
{"type":"question","sessionId":"${SESSION_ID}","question":"${QUESTION_ESCAPED}","cwd":"${CWD}","pid":$$}
EOF
)

echo "$MSG" | nc -U /tmp/claude-island.sock 2>/dev/null

exit 0
