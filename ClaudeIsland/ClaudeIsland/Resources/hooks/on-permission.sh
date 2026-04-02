#!/bin/bash
# Claude Island — PermissionRequest hook
# Receives JSON via stdin when Claude Code needs tool permission.
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ti=d.get('tool_input',{})
if isinstance(ti,dict):
    print(ti.get('command', ti.get('file_path', json.dumps(ti)[:200])))
else:
    print(str(ti)[:200])
" 2>/dev/null)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)

# Escape quotes in tool input for JSON
TOOL_INPUT_ESCAPED=$(echo "$TOOL_INPUT" | sed 's/"/\\"/g' | tr '\n' ' ')

MSG=$(cat <<EOF
{"type":"permission","sessionId":"${SESSION_ID}","toolName":"${TOOL_NAME}","toolInput":"${TOOL_INPUT_ESCAPED}","cwd":"${CWD}","pid":$$}
EOF
)

echo "$MSG" | nc -U /tmp/claude-island.sock 2>/dev/null

exit 0
