<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude-toolkit.menubar-visibility</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{{scripts_dir}}/menubar-visibility-fix.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/claude-toolkit-menubar-visibility.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-toolkit-menubar-visibility.log</string>
</dict>
</plist>
