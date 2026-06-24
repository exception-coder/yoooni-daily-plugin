' run-hidden.vbs - launch a PowerShell script with a truly hidden window (no flashing console).
'
' Why: `powershell -WindowStyle Hidden` creates the console window first and only hides it
'      afterwards, so a black box still flashes for a moment. WshShell.Run(cmd, 0, False)
'      passes SW_HIDE at process creation, so the window is never shown at all; child
'      console programs (git / npm / claude / node) inherit that hidden console and do not
'      pop their own windows either.
'
' Usage:
'   wscript.exe run-hidden.vbs                       -> runs run-update.ps1 next to this file
'   wscript.exe run-hidden.vbs "<abs path .ps1>" ... -> runs the given .ps1 (extra args forwarded)
' The no-arg form keeps the scheduled-task action a single quoted path (avoids nested-quote pain).
Option Explicit
Dim sh, fso, target, cmd, i
Set sh = CreateObject("WScript.Shell")
If WScript.Arguments.Count >= 1 Then
  target = WScript.Arguments(0)
Else
  Set fso = CreateObject("Scripting.FileSystemObject")
  target = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "run-update.ps1")
End If
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File """ & target & """"
For i = 1 To WScript.Arguments.Count - 1
  cmd = cmd & " """ & WScript.Arguments(i) & """"
Next
sh.Run cmd, 0, False
