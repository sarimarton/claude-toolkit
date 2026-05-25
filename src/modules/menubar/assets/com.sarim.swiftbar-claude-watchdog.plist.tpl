<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.sarim.swiftbar-claude-watchdog</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{{scripts_dir}}/swiftbar-watchdog.sh</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/swiftbar-watchdog.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/swiftbar-watchdog.log</string>
</dict>
</plist>
