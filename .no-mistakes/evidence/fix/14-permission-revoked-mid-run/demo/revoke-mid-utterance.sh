#!/bin/zsh
# Issue #14 live demo: revoke Accessibility mid-Utterance, then check idle behaviour.
set -u
OUT=/tmp/demo14; mkdir -p $OUT
PID=$(pgrep -x MachVoice)
echo "pid=$PID"
menu() { osascript -e 'tell application "System Events" to tell process "MachVoice" to click menu bar item 1 of menu bar 2' >/dev/null 2>&1; sleep 1; screencapture -x $OUT/$1.png; osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1; sleep 0.5; }
menu 1-granted-menu
echo "clipboard sentinel before demo" | pbcopy
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null; sleep 1.5
VOL=$(osascript -e 'output volume of (get volume settings)')
osascript -e 'set volume output volume 60'
date "+%H:%M:%S.000 demo: Dictation Key down"
/tmp/rcmd down; sleep 0.8
say "the quick brown fox jumps over the lazy dog"
date "+%H:%M:%S.000 demo: revoking Accessibility with the Dictation Key still held"
tccutil reset Accessibility com.augustomklee.MachVoice >/dev/null
sleep 4
date "+%H:%M:%S.000 demo: Dictation Key released (after teardown)"
/tmp/rcmd up
osascript -e "set volume output volume $VOL"
sleep 2
echo "clipboard after: $(pbpaste)"
echo "textedit contents: $(osascript -e 'tell application "TextEdit" to get text of front document')"
tail -c 400 ~/Library/Application\ Support/MachVoice/history.json; echo
menu 2-revoked-menu
date "+%H:%M:%S.000 demo: Dictation Key tapped again after loss"
/tmp/rcmd tap 1; sleep 2
echo "still running: $(pgrep -x MachVoice)"
