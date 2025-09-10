# Audio Tray Tools - Full Setup Guide

I did not create this all by myself. Most of the credit should go to the creators of [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets).

Big thanks to PSum for setting up the githubrepo and creating the instructional guide. Some of the images are in german, but du schaffst es schon!

This guide explains how to set up two PowerShell tray utilities:


1. **Microphone Tray Tool** – shows mic status (muted/unmuted) in the system tray and lets you toggle mute with a left click.


<img width="600" height="113" alt="MicMute" src="https://github.com/user-attachments/assets/aa554fb9-989c-4df0-a0da-bf5dd00667d1" />

<img width="608" height="99" alt="MicunMute" src="https://github.com/user-attachments/assets/44812151-d30b-49ce-8811-c1bab00e290d" />


2. **Audio Output Tray Tool** – shows the current playback device in the tray and lets you switch between outputs with a left click. Both scripts use **AudioDeviceCmdlets** and rely on `.ico` icon files provided alongside the scripts

   
<img width="594" height="107" alt="Speaker" src="https://github.com/user-attachments/assets/271a4f96-952b-41d9-ae67-d3ca3aa3a8b8" />

<img width="526" height="109" alt="Speaker2" src="https://github.com/user-attachments/assets/b1903fb5-2432-4b86-9258-f380e480ba2d" />

## Microphone Tray Tool

### Save the script

Save the following script into a folder of your choice (e.g. `C:\Users\YourName\Tools\AudioTray`)

You can do this by creating a text file (.txt) and copy and pasting this code into that file. Then name the file as you wish, but change the extension to .ps1 instead of .txt

```ps1
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
```

### Requirements

For the script to work you must download 2 icons of your choice (showing whether the microphone is muted or not). You can use [this website](https://icon-icons.com/) to download the files in the `.ico`-fileformat.

I've also included those two icon files in the download. They are named mic-on.ico and mic-off.ico. These .ico files are basically images that windows can use instead of the standard windows shortcut image.


<img width="210" height="140" alt="Miconandmicoff" src="https://github.com/user-attachments/assets/f06ae09a-85fb-44fb-9fe3-c0914a89c3cc" />


Place those files in the same directory as the script. 

The names of these files must also match the names in the script. Look for these lines in the script:


$iconPathOn = Join-Path $scriptDir "mic-on.ico"
$iconPathOff = Join-Path $scriptDir "mic-off.ico"


#### Next:

You also must install the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) suite for the script to work. To do so paste the following script as administrator in a powershell window:
```bash
Install-Module -Name AudioDeviceCmdlets
```

### Execution

Run the script by right-clicking it and pressing `run with powershell`. Now the icon showing the microphone status should appear in you tool tray. Toggle your mics state by clicking the icon.

## Audio Output Tray Tool

### Save the script

Save the following script into a folder of your choice (e.g. `C:\Users\YourName\Tools\AudioTray`)

You can do this by creating a text file (.txt) and copy and pasting this code into that file. Then name the file as you wish, but change the extension to .ps1 instead of .txt

```ps1
# AudioOutputTray.ps1
# Requires: AudioDeviceCmdlets
Import-Module AudioDeviceCmdlets
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Paths to icons (same folder as script)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$iconPath1 = Join-Path $scriptDir "icon1.ico"
$iconPath2 = Join-Path $scriptDir "icon2.ico"
# NotifyIcon setup
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
function Update-Icon {
$device = Get-AudioDevice -Playback
$notify.Text = "Output: " + $device.Name
if ($device.Index -eq 1) {
$notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath1)
} else {
$notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath2)
}
}
# Toggle on left-click
$notify.add_Click({
if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
$current = Get-AudioDevice -Playback
$next = Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' -and $_.ID -ne $current.ID } | Select-Object -First 1
if ($next) { Set-AudioDevice -ID $next.ID }
Start-Sleep -Milliseconds 200
Update-Icon
}
})
# Initialize
Update-Icon
[System.Windows.Forms.Application]::Run()
```

### Requirements

For the script to work you must download 2 icons of your choice (showing which source is in use). You can use [this website](https://icon-icons.com/) to download the files in the `.ico`-fileformat.

I've also included those two icon files in the download. They are called icon1.ico and icon2.ico. (real creative I know...) These .ico files are basically images that windows can use instead of the standard windows shortcut image.

Place those files in the same directory as the script.

The names of these files must also match the names in the script. Look for these lines in the script:

<img width="200" height="121" alt="Icons1and2" src="https://github.com/user-attachments/assets/cb22647f-bb78-4dfe-b6b8-d8d0cbf3f540" />

$iconPath1 = Join-Path $scriptDir "icon1.ico"
$iconPath2 = Join-Path $scriptDir "icon2.ico"

Again:

If you didn't already, you also must install the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) suite for the script to work. To do so paste the following script as administrator in a powershell window:
```bash
Install-Module -Name AudioDeviceCmdlets
```
#### Auto Running these Scripts on startup:

 Creating Shortcuts & Autostart
 1. Right-click on your Desktop → New → Shortcut.

<img width="701" height="545" alt="Makeshortcut" src="https://github.com/user-attachments/assets/a6358493-630d-4ccc-a187-3737b0feb733" />


 2. Enter this as the location (adjust path to your script location):
 3. powershell.exe -NoLogo -WindowStyle Hidden -ExecutionPolicy Bypass -File
 "C:\Path\To\MicTray.ps1"

<img width="795" height="515" alt="makeshortcutwithpath" src="https://github.com/user-attachments/assets/aeba0a5e-3971-4abe-9be3-9de8fbfce897" />


 5. Click Next, give it a name (e.g., 'Mic Tray'), and Finish.
 6. Repeat the same for `AudioOutputTray.ps1`.
 7. To autostart, press `Win + R`, type `shell:startup`, and drag the shortcut into the Startup folder

<img width="403" height="206" alt="Shellstartupcmd" src="https://github.com/user-attachments/assets/2344a4d3-5a90-49ff-bfb0-cd8e61a25e33" />


<img width="998" height="233" alt="Autostartfolder" src="https://github.com/user-attachments/assets/95b7ec49-eb8e-4c75-8e91-6896a6afba87" />

 ##### Hide Powershell Window on Startup
 1. Right click on the shortcuts you created in previous steps.
 2. Change the execute in window mode to minimized

<img width="404" height="523" alt="Windowminimized" src="https://github.com/user-attachments/assets/e9ed7f64-37c3-4115-a305-ebc8418120ea" />

Good luck. Hope it works. Just so you know, powershell will be running in the background. No promises that this will work well or that I will update this if it breaks. 
