# Re-record with:  bash demo/setup.sh && vhs demo/demo.tape
Output demo/demo.gif
Set Shell "bash"
Set FontSize 14
Set Width 1280
Set Height 680
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 35ms
Set CursorBlink false

Hide
Type "source /tmp/claude-account-demo/env.sh && clear" Enter
Sleep 500ms
Show

Type "claude-account list" Sleep 400ms Enter
Sleep 1.8s
Type "claude-account sessions" Sleep 400ms Enter
Sleep 2.5s
Type "claude-account brief" Sleep 400ms Enter
Sleep 9s
Type "clear" Enter
Type "claude-account handoff work --brief" Sleep 400ms Enter
Sleep 8s
