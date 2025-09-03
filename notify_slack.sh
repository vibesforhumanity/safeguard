#!/bin/bash

# Simple notification script for Slack updates
# Usage: ./notify_slack.sh "Your message here"

MESSAGE="$1"
USER_ID="U09CRDBHW1K"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"Your message\""
    exit 1
fi

# Try to send notification, ignore errors if bot is down
curl -X POST http://localhost:3000/notify \
  -H "Content-Type: application/json" \
  -d "{\"userId\": \"$USER_ID\", \"message\": \"$MESSAGE\"}" \
  --connect-timeout 5 \
  --max-time 10 \
  --silent \
  --fail > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Slack notification sent"
else 
    echo "ℹ️  Slack bot not available - continuing with work"
fi