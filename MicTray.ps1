# MicTray.ps1
# Requires: AudioDeviceCmdlets
Import-Module AudioDeviceCmdlets
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Paths to icons (same folder as script)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$iconPathOn = Join-Path $scriptDir "mic-on.ico"
$iconPathOff = Join-Path $scriptDir "mic-off.ico"
# NotifyIcon setup
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
function Update-Icon {
 $muted = Get-AudioDevice -RecordingMute
 if ($muted) {
 $notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPathOff)
 $notify.Text = "Mic: Muted"
 } else {
 $notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPathOn)
 $notify.Text = "Mic: Unmuted"
 }
}
# Toggle on left-click
$notify.add_Click({
 if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
 Set-AudioDevice -RecordingMuteToggle
 Start-Sleep -Milliseconds 200
 Update-Icon
 }
})
# Initialize
Update-Icon
[System.Windows.Forms.Application]::Run()
