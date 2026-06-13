---
description: Resume the prior Claude session shown in this pane's scrollback, by its $topic marker
allowed-tools: Bash({{scripts_dir}}/ultraresume-inject.sh:*)
---

Resume the PRIOR Claude session visible in this tmux pane's scrollback — the one
*before* the current conversation — identified by its `$topic` marker and resumed
in place via `/resume <uuid>` self-injected into this pane's prompt.

The work is fully done by the script below; it reads the scrollback, excludes the
current session, resolves the prior session's UUID, and sends `/resume <uuid>` +
Enter into this pane. You do not need to do anything else.

!`{{scripts_dir}}/ultraresume-inject.sh "$TMUX_PANE"`

If the script printed `ultraresume → /resume <uuid> …`, the resume keys were sent
and Claude is switching sessions now — say nothing further. If it printed an
`ultraresume: …` error (no prior marker in scrollback, no matching session, not in
tmux), relay that one line to the user so they know why nothing happened.
