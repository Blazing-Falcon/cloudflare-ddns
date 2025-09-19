Set objShell = CreateObject("Wscript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Path\YourScript.ps1""", 0, True
