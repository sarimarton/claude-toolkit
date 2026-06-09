<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.sarim.llm-cleanup-server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>__NODE_BIN__</string>
        <string>{{install_dir}}/dictation/llm-cleanup-server/index.js</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key>
        <string>51733</string>
        <key>CLAUDE_BIN</key>
        <string>__CLAUDE_BIN__</string>
        <key>CLEANUP_MODEL</key>
        <string>claude-sonnet-4-6</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:__HOME__/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/llm-cleanup-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/llm-cleanup-server.log</string>
</dict>
</plist>
