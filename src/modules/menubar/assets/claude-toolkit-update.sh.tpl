#!/bin/sh
# claude-toolkit-update.sh — wrapper for menubar "Update available" action
# Avoids SwiftBar terminal env-export quoting issues by being a plain sh script.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"
exec node "{{repo_dir}}/dist/cli.js" update
