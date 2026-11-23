#!/bin/sh
# Render og.html to public/og.png at the Open Graph size. Needs the agent-browser CLI.
set -e
cd "$(dirname "$0")"
agent-browser open "file://$PWD/og.html" >/dev/null
agent-browser set viewport 1200 630 >/dev/null
agent-browser wait 400 >/dev/null
agent-browser screenshot "$PWD/../public/og.png" >/dev/null
agent-browser close >/dev/null
echo "Wrote public/og.png"
