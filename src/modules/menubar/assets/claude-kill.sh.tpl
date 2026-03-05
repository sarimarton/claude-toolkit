#!/usr/bin/env bash
# Kill a tmux Claude session, then reopen the SwiftBar menu
{{tmux}} kill-session -t "$1" 2>/dev/null
# Refresh plugin data, then reopen menu via CGEvent mouse click
open -g "swiftbar://refreshplugin?name=claude.10s"
sleep 0.5
osascript -l JavaScript -e "
ObjC.import('CoreGraphics');
var se = Application('System Events');
var items = se.processes.byName('SwiftBar').menuBars[0].menuBarItems;
var item = null;
for (var i = 0; i < items.length; i++) {
    if ((items[i].name() || '').indexOf('✻') !== -1) { item = items[i]; break; }
}
if (!item) { item = items[items.length - 1]; }
var pos = item.position();
var sz = item.size();
var cx = pos[0] + sz[0]/2, cy = pos[1] + sz[1]/2;
var pt = $.CGPointMake(cx, cy);
var dn = $.CGEventCreateMouseEvent(null, $.kCGEventLeftMouseDown, pt, 0);
var up = $.CGEventCreateMouseEvent(null, $.kCGEventLeftMouseUp, pt, 0);
$.CGEventPost($.kCGHIDEventTap, dn);
delay(0.05);
$.CGEventPost($.kCGHIDEventTap, up);
" &>/dev/null &
