#!/usr/bin/env bash
# TAP classify — determines terminal state from assistant message text.
# Reads text from stdin, echoes "done" or "asking".

text=$(cat 2>/dev/null)
[[ -z "$text" ]] && echo "done" && exit 0

# Ends with a question mark (ignoring trailing whitespace)
if printf '%s' "$text" | grep -qE '\?[[:space:]]*$'; then
  echo "asking"
  exit 0
fi

# Last 5 lines contain a numbered list (presenting options)
if printf '%s' "$text" | tail -5 | grep -qE '^[[:space:]]*[0-9]+\.[[:space:]]'; then
  echo "asking"
  exit 0
fi

echo "done"
