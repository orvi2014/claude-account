# Re-record with:  bash demo/setup.sh && vhs demo/demo.tape
Output demo/demo.gif
Set Shell "bash"
Set FontSize 14
Set Width 1280
Set Height 720
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
Type "claude-account whoami" Sleep 400ms Enter
Sleep 2s
Type "claude-account switch work" Sleep 400ms Enter
Sleep 3s
Type "clear" Enter
Type "claude-account pin work" Sleep 400ms Enter
Sleep 2.5s
Type "claude" Sleep 400ms Enter
Sleep 2s
Type "cd ~ && claude" Sleep 400ms Enter
Sleep 2.5s
Type "cd billing" Enter
Type "clear" Enter
Type "claude-account handoff codex" Sleep 400ms Enter
Sleep 5s
