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

---

# Which version should I use?

**Most people want [`dist/AudioTray.exe`](dist).** Download, double-click, tick *Start with Windows*. Done.

The rest exist for machines where that is not allowed.

| | **AudioTray.exe** | **Audio Tray** (`tray/`) | **Taskbar tools** (`taskbar/`) | Shortcuts only |
|---|---|---|---|---|
| Setup | Double-click | Run a script | Run an installer script | Run an installer script |
| Live tray icons | Yes | Yes | No, brief pop-up | No |
| Background process | Yes, resident | Yes, resident | No, ~1.5s per click | None |
| Click to toggle | Yes | Yes | Yes | No, opens a panel |
| Pick a device from a menu | Yes | Yes | Via `-Name` | Yes, in the panel |
| Connect a paired Bluetooth device | Yes | Yes | No | Via Windows Settings |
| Global hotkey | No | No | Yes | No |
| Needs PowerShell to be permitted | No | Yes | Yes | No |
| Third-party code | None | None | None | None |
| Works under AppLocker / WDAC | Usually not | Usually not | Sometimes | Always |

The .exe and the `tray/` script are the same tool built two ways — pick the .exe for convenience, the script if you would rather run something you can read. The original tray scripts at the bottom of this README are superseded by both; they are kept for reference.

**On a work PC, start here:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\taskbar\Test-Compatibility.ps1
```

That is read-only — it installs nothing and changes no device. It tells you which of the columns above you can use, and why.

## Why the original tools trip antivirus and corporate policy

Two separate things caused trouble, and they are worth separating because the fixes are different:

- **`Install-Module AudioDeviceCmdlets` downloads an unsigned compiled DLL from the PowerShell Gallery.** That is the single biggest trigger — SmartScreen, Defender and AppLocker all treat a freshly downloaded unsigned binary as suspect, and most work accounts cannot install modules at all.
- **`[System.Windows.Forms.Application]::Run()` keeps `powershell.exe` alive forever.** Endpoint security products flag long-running PowerShell processes as a matter of course, and "no background scripts" policies are aimed at exactly this shape of thing.

Every tool here fixes the first problem: they call the Core Audio API that is already part of Windows, so there is nothing to download and nothing third-party involved.

Only the taskbar tools fix the second, by exiting after each action. **Audio Tray is a resident process by design** — that is what a live tray icon requires — so on a machine whose policy forbids background scripts, use the taskbar tools instead. There is no way to have both.

---

# AudioTray.exe (easiest option)

**[`dist/AudioTray.exe`](dist)** — one file, no PowerShell, no execution policy, no console window. Download it, put it anywhere, double-click.

To start it with Windows, right-click the output icon and tick **Start with Windows**. That is all the setup there is.

It needs .NET Framework 4.8, which is part of Windows 10 (1903 and later) and Windows 11 — so on any current Windows there is nothing to install.

### First run: expect a SmartScreen warning

The executable is not code-signed — signing certificates cost a few hundred a year — so the first launch shows **"Windows protected your PC"**. Click **More info → Run anyway**. If it was downloaded rather than built locally, you can clear the flag permanently: right-click the file → **Properties** → tick **Unblock** → OK.

That warning is the honest cost of a plain binary. If you would rather not take a downloaded .exe on trust, don't — build it yourself:

- **On Windows:** `dotnet build src/AudioTray/AudioTray.csproj -c Release`
- **In CI:** the [build workflow](.github/workflows/build-audiotray.yml) compiles it on a clean GitHub runner and uploads the result as a downloadable artifact. Same source, build you can watch.
- **On Linux:** `bash src/build.sh` (uses Microsoft's Roslyn compiler and .NET Framework reference assemblies from NuGet, with Mono only as a host)

The full source is in [`src/AudioTray`](src/AudioTray) — the same Core Audio and Bluetooth code as the PowerShell version, roughly 1,300 lines.

### If switching outputs is refused

Some Windows builds will not expose `IPolicyConfig`, the undocumented interface every audio switcher uses to change the default device. There is no public API for this, so when Windows declines there is no second official route. Left-clicking the output icon then reports "Could not change the default audio device".

**Right-click the output icon → Diagnostics...** to see exactly which interfaces your build answers to. The report is also written to `AudioTray-diagnostics.txt` next to the executable.

Everything else still works when this fails — mic mute, device monitoring, the tray icons, and Bluetooth. Two workarounds:

- **If you switch between a Bluetooth headset and speakers**, use the **Bluetooth** submenu instead. Connecting and disconnecting goes through a completely different Windows API that does not involve PolicyConfig at all, and Windows moves the default output on its own when a headset connects or drops. For that particular swap it does the same job.
- **Otherwise** use **Windows sound settings...** in the same menu, or **Win+Ctrl+V** for the volume mixer's output picker.

### Options

| | |
|---|---|
| `AudioTray.exe` | Normal launch. |
| `AudioTray.exe --poll 500` | Poll the audio state every 500 ms instead of 1000. Accepts 250–10000. |
| `outputs.txt` beside the .exe | Narrows which outputs get cycled. Same format as below. |
| `mic-on.ico` etc. beside the .exe | Overrides the built-in icons without rebuilding. |

Everything else works exactly as described in the next section — same icons, same clicks, same menus, same Bluetooth submenu.

---

# Audio Tray (PowerShell version)

The same tool as a script, in [`tray/`](tray). Use this if you would rather run something you can read and edit than a compiled binary. Two icons appear in the notification area and stay in step with whatever Windows is doing — including changes you make in the volume mixer, from a headset button, or by unplugging a dock.

**Microphone icon**

- **Left click** — toggle mute. The icon switches between `mic-on.ico` and `mic-off.ico`.
- **Right click** — mute/unmute, pick which input device is the default, quit.

**Output icon**

- **Left click** — cycle to the next output device.
- **Right click** — pick an output directly, connect a paired Bluetooth device, open the Windows sound panel, toggle **Start with Windows**, quit.

## Running it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tray\AudioTray.ps1
```

The console window hides itself once it starts, and only when the script owns that window — launching it from an existing prompt leaves your prompt alone. Pass `-KeepConsole` to keep it visible while testing.

To start it at login, use **Start with Windows** in the output icon's right-click menu. That writes a shortcut into your own Startup folder: nothing machine-wide, no admin, no registry Run key. Untick it to remove.

Launching it twice is harmless — the second copy notices the first and exits rather than adding a duplicate pair of icons.

## Connecting a Bluetooth device

The output icon's **Bluetooth** submenu lists devices already paired with this PC, marking the ones currently connected. Click one to connect it; click a connected one to disconnect.

Two limits worth knowing up front:

- **Pairing is not included** — only connecting things already paired. Pairing needs a trust prompt and belongs in Windows Settings, where you have presumably already done it.
- **This uses the classic Bluetooth audio profiles** (A2DP and hands-free), which is what ordinary headsets and speakers use. A device that only speaks Bluetooth LE Audio will be listed but may not connect this way.

Connecting can take several seconds while the radio negotiates. That work happens on a background thread so the tray stays responsive, and a notification tells you how it went. If the device is off or out of range you get "did not respond" rather than a silent failure.

## Choosing which outputs it cycles

Left-clicking the output icon walks through your devices in order. A docked laptop often exposes five when you only use two, so the same `outputs.txt` the taskbar tools use applies here — see [Cycling only the outputs you care about](#cycling-only-the-outputs-you-care-about). Put it in the repository root to share one file between both tools.

The icon alternates between `icon1.ico` and `icon2.ico` along that cycle order, so the two devices you actually swap between look different at a glance.

## Notes

- **It polls once a second** rather than subscribing to device-change events. That is a deliberate trade: a few API calls per second is negligible, and it avoids COM callbacks arriving on a foreign thread, which is a rich source of crashes in a script-hosted app. Your own clicks repaint the icon immediately, so only external changes can lag, and only briefly.
- **Transient errors do not kill it.** Windows occasionally refuses these calls while devices are being re-enumerated; the tray absorbs that and only complains if the state stays unreadable.

---

# Taskbar Tools

Everything in this section lives in the [`taskbar/`](taskbar) folder.

| File | What it does |
|---|---|
| `Test-Compatibility.ps1` | Read-only check of what will work on this machine. Run this first. |
| `Install-Shortcuts.ps1` | Creates the shortcuts you pin to the taskbar. |
| `Toggle-Mic.ps1` | Mutes/unmutes the microphone and exits. |
| `Switch-Output.ps1` | Cycles the default output device and exits. |
| `../lib/AudioControl.ps1` | Shared library, used by the tray tools too. Not run directly. |
| `Add-CodeSignature.ps1` | Only needed if policy forces `AllSigned`. |
| `outputs.example.txt` | Optional — narrows which outputs get cycled. |

## Setup

1. Download or clone this repository somewhere permanent — your Documents folder is fine. The shortcuts point at wherever you put it, so moving it later means re-running step 3.

2. If you downloaded a ZIP, unblock it. Windows tags downloaded files and will refuse to run them otherwise:

   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```

3. Create the shortcuts:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\taskbar\Install-Shortcuts.ps1
   ```

4. Open the Start menu, find the **Audio Tray Tools** folder, right-click each shortcut and choose **Pin to taskbar**.

No admin rights are needed. The shortcuts go in your own Start menu folder; nothing is written to Program Files, the registry, or anywhere machine-wide. To undo the whole thing, run `Install-Shortcuts.ps1 -Uninstall`.

## Using them

Click the taskbar buttons, or use the hotkeys the installer sets up:

- **Ctrl+Alt+M** — toggle microphone mute
- **Ctrl+Alt+O** — cycle audio output

These hotkeys are implemented by Windows itself, as a property of the shortcut file. Nothing is sitting in the background watching your keyboard — which is both why they are policy-friendly and why they only work when the shortcut lives in your Start menu or Desktop.

Change them with `-MicHotkey` / `-OutputHotkey`, or pass `''` to skip them:

```powershell
.\Install-Shortcuts.ps1 -MicHotkey 'CTRL+ALT+SHIFT+M' -OutputHotkey ''
```

A small pop-up confirms each action for about a second, then disappears. It never takes keyboard focus, so muting yourself mid-sentence will not swallow your typing. Deliberately not a balloon notification — those pile up in the Windows notification centre, which gets old fast for something you click all day.

### Mute covers conferencing apps properly

Windows tracks two separate default microphones: the normal one, and a "communications" one that Teams, Zoom, Slack and Discord use. They are often different devices, which is the usual reason a mute button appears to do nothing in a meeting. `Toggle-Mic.ps1` sets both. If you have several mics and want all of them, use `-AllDevices`.

### Cycling only the outputs you care about

A docked laptop can expose five outputs when you only ever use two. Copy `outputs.example.txt` to `outputs.txt` and list the ones you want, one name fragment per line, in cycle order:

```
Headset
Speakers
```

Matching is partial and case-insensitive, and entries that are not plugged in right now are skipped — so the same file works docked and undocked. Run `.\Switch-Output.ps1 -List` to see the exact names Windows reports.

You can also jump straight to a device: `.\Switch-Output.ps1 -Name 'Headset'`.

## If something does not work

Run `Test-Compatibility.ps1` first — it names the specific blocker. The common ones:

**"Language mode: ConstrainedLanguage"** — your machine blocks the .NET calls that any scripted audio tool needs, including AudioDeviceCmdlets. Nothing scripted will work. Use the shortcut-only approach below.

**Execution policy forced to `AllSigned` by Group Policy** — `-ExecutionPolicy Bypass` cannot override a policy-set value. Either sign the scripts for yourself:

```powershell
powershell -NoProfile -File .\taskbar\Add-CodeSignature.ps1
```

which creates a certificate in your own user store, trusts it for your account only, and signs the files — or use the shortcut-only approach. Note that some environments do not honour the per-user root store for script signing, in which case this will not help either.

**A shortcut flashes and nothing happens** — run the script directly in a console window to see the error:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\taskbar\Toggle-Mic.ps1
```

**"Device switching: PolicyConfig refused"** — Windows has never shipped a public API for changing the default output device; every audio switcher, this one included, uses an internal shell interface. If your build refuses it, mic mute still works and you can use the Sound Devices shortcut for outputs.

**First click feels slow** — the first run in each process compiles the interop layer, which takes a second or so. This is the trade for not shipping a binary you would have to trust.

### One thing to avoid

If you go looking for other ways around execution policy, you will find advice to use `powershell -EncodedCommand <base64>`. Do not. Base64-encoded PowerShell is one of the most reliable malware signatures there is, and it is close to guaranteed to get you an antivirus alert and an awkward conversation with IT. Everything here is plain readable text on purpose.

## If nothing scripted works

Some machines are locked down hard enough that no script will run, full stop. You can still get one-click audio control, because Windows has the panels built in:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\taskbar\Install-Shortcuts.ps1 -NativeOnly
```

This creates two shortcuts that run no script at all — they just open the playback and recording device lists (`control.exe mmsys.cpl`). Pin them to the taskbar and you get the device switcher two clicks away. Since no code executes, there is nothing for antivirus or policy to object to.

If even that is off the table, the shortcuts are trivial to create by hand: right-click the Desktop → **New** → **Shortcut**, and enter `control.exe mmsys.cpl,,0` for playback or `control.exe mmsys.cpl,,1` for recording.

Also worth knowing, since they need no setup whatsoever:

- **Win+Ctrl+V** opens the volume mixer on Windows 11, which includes an output device picker.
- **Win+A** opens Quick Settings; the arrow next to the volume slider switches output.

---

# Original Tray Tools (superseded)

Kept for reference. These are the scripts this repository started with; [Audio Tray](#audio-tray) does the same job without needing AudioDeviceCmdlets, and adds device menus and Bluetooth connect.

The two scripts below still work if you have AudioDeviceCmdlets installed and prefer them.

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
