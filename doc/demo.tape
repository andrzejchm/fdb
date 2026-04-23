Output doc/demo.gif

Set Shell "zsh"
Set FontSize 13
Set Width 1200
Set Height 600
Set FontFamily "Menlo"
Set LineHeight 1.2
Set Padding 24
Set Framerate 24
Set TypingSpeed 45ms
Set WindowBar Rings
Set BorderRadius 12
Set Theme "Catppuccin Mocha"
Set MarginFill "#0D1117"
Set Margin 40

Hide
Type "alias fdb='/Users/andrzejchm/Developer/andrzejchm/fdb/doc/fdb-mock.sh'"
Enter
Ctrl+L
Show

Type "fdb devices"
Enter
Sleep 4s
Ctrl+L

Type "fdb launch --device b433094a --project ."
Enter
Sleep 5s
Ctrl+L

Type "fdb screenshot"
Enter
Sleep 4s
Ctrl+L

Type "fdb describe"
Enter
Sleep 5s
Ctrl+L

Type "fdb tap --key fab_add"
Enter
Sleep 4s
Ctrl+L

Type "fdb logs --tag MyApp --last 5"
Enter
Sleep 5s
Ctrl+L

Type "fdb kill"
Enter
Sleep 2s
