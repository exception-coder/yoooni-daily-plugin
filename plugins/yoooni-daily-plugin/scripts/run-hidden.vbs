' run-hidden.vbs - launch a PowerShell script with a truly hidden window (no flashing console).
'
' Why: 子进程(claude/git/node)在「真正下载/应用更新」时会各自新开经典控制台 -> 黑框闪。
'      单靠 powershell -WindowStyle Hidden(先开窗再藏) 或 WshShell.Run(...,0)(只藏外层)
'      都压不住「孙子进程新开的控制台」。
'      解法：用 conhost.exe --headless(ConPTY 伪控制台)起 powershell —— 整条进程树都挂在
'      无窗口的伪控制台上，子进程不再新开经典控制台窗口(这正是 Windows Terminal / VS Code
'      跑 shell 不弹黑框的机制)。需 Windows 10 2004+ / Windows 11(均自带)。
'      WshShell.Run(...,0) 再兜一层隐藏。
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
cmd = "conhost.exe --headless -- powershell -NoProfile -ExecutionPolicy Bypass -File """ & target & """"
For i = 1 To WScript.Arguments.Count - 1
  cmd = cmd & " """ & WScript.Arguments(i) & """"
Next
sh.Run cmd, 0, False
