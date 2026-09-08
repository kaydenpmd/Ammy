# Registers the Ammy relay as a logon Scheduled Task.
#
# It MUST run in the interactive session, not as a Windows service. Discord's
# IPC pipe (\\.\pipe\discord-ipc-0) belongs to the logged-in session, and
# session 0 cannot reach it. That is why the principal below is -LogonType
# Interactive and the run level is Limited: "run whether user is logged on or
# not" would register a session 0 task that starts fine, listens on 8787, and
# never connects — a failure that looks like a Discord problem, not a task one.

$ErrorActionPreference = 'Stop'

$TaskName = 'Ammy Relay'

# Wherever this script lives is where relay.py lives. Nothing is hardcoded, so
# the repo can sit anywhere and the task still points at the right copy.
$Dir    = $PSScriptRoot
$Script = Join-Path $Dir 'relay.py'

if (-not (Test-Path $Script)) { throw "relay.py not found next to this script ($Dir)" }
if (-not (Test-Path (Join-Path $Dir '.env'))) {
    throw "No .env in $Dir. A Scheduled Task inherits no variables from a PowerShell window, so the relay would start with no client ID or secret. Create .env first."
}

# pythonw.exe, not python.exe: no console window at logon. relay.py detects the
# missing stdout and redirects its output to relay.log beside itself.
$Pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $Pythonw) {
    $Py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
    if (-not $Py) { throw 'Neither pythonw.exe nor python.exe is on PATH.' }
    $Pythonw = Join-Path (Split-Path $Py) 'pythonw.exe'
}
if (-not (Test-Path $Pythonw)) { throw "pythonw.exe not found (looked at $Pythonw)" }

Write-Host "python : $Pythonw"
Write-Host "script : $Script"

$Action = New-ScheduledTaskAction -Execute $Pythonw -Argument 'relay.py' -WorkingDirectory $Dir

# The 30s delay is comfort, not necessity — the RPC worker already retries every
# 10s if Discord isn't up yet. It just keeps the log tidy at boot.
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
$Trigger.Delay = 'PT30S'

$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                        -LogonType Interactive `
                                        -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                         -DontStopIfGoingOnBatteries `
                                         -StartWhenAvailable `
                                         -RestartCount 3 `
                                         -RestartInterval (New-TimeSpan -Minutes 1) `
                                         -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $TaskName `
                       -Description 'Apple Music -> Discord Rich Presence relay.' `
                       -Action $Action -Trigger $Trigger `
                       -Principal $Principal -Settings $Settings -Force | Out-Null

Write-Host ''
Write-Host "Registered '$TaskName'." -ForegroundColor Green
Write-Host 'Start it now with:  Start-ScheduledTask -TaskName "Ammy Relay"'
Write-Host 'Stop it with:       Stop-ScheduledTask  -TaskName "Ammy Relay"'
Write-Host 'Remove it with:     Unregister-ScheduledTask -TaskName "Ammy Relay" -Confirm:$false'
Write-Host ''
Write-Host 'Output goes to relay.log beside relay.py, not a console window.'
Write-Host 'LastTaskResult 267009 means running; relay.log is the real evidence.'
