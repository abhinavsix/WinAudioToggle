<#
.SYNOPSIS
    Resident tray icons for the microphone and the audio output device.

.DESCRIPTION
    Puts two icons in the notification area and keeps them in step with what
    Windows is actually doing:

      Microphone icon
        left click   toggle mute
        right click  pick the input device, mute/unmute, quit

      Output icon
        left click   cycle to the next output device
        right click  pick an output directly, connect a paired Bluetooth
                     device, open the Windows sound panel, quit

    Both icons follow changes made anywhere else - the volume mixer, a headset
    button, unplugging a dock - so they never show a stale state.

    Unlike the original tray scripts this needs no AudioDeviceCmdlets and
    nothing from the PowerShell Gallery; it talks to the Core Audio and
    Bluetooth APIs already in Windows. It is still a resident process, so it
    is not the right choice on a PC whose policy forbids one. See the taskbar
    tools for that case.

.PARAMETER KeepConsole
    Leave the console window visible. Useful while testing; the window is
    hidden automatically when the script owns it.

.PARAMETER PollMilliseconds
    How often to re-read the audio state. Default 1000.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\AudioTray.ps1
#>
[CmdletBinding()]
param(
    [switch]$KeepConsole,
    [ValidateRange(250, 10000)][int]$PollMilliseconds = 1000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AudioControl.ps1')

# --- single instance --------------------------------------------------------

$script:MutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\WinAudioToggle.AudioTray', [ref]$script:MutexCreated)

if (-not $script:MutexCreated) {
    Write-Host 'Audio Tray is already running. Look for the icons in the notification area.'
    exit 0
}

Initialize-AudioTypes
if (-not $KeepConsole) { $null = Hide-OwnConsoleWindow }

# --- icons ------------------------------------------------------------------

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:IconCache = @{}

function Get-TrayIcon {
    <#
        Loads an .ico and picks the size Windows wants for the notification
        area, which keeps the icon crisp on high-DPI displays instead of
        letting the shell rescale a large frame.
    #>
    param([Parameter(Mandatory = $true)][string]$FileName)

    if ($script:IconCache.ContainsKey($FileName)) { return $script:IconCache[$FileName] }

    $path = Join-Path $script:RepoRoot $FileName
    $icon = $null
    if (Test-Path -LiteralPath $path) {
        try {
            $source = New-Object System.Drawing.Icon($path)
            try {
                $icon = New-Object System.Drawing.Icon($source, [System.Windows.Forms.SystemInformation]::SmallIconSize)
            }
            finally { $source.Dispose() }
        }
        catch { $icon = $null }
    }

    if (-not $icon) { $icon = [System.Drawing.SystemIcons]::Application }

    $script:IconCache[$FileName] = $icon
    return $icon
}

function Set-TrayText {
    # NotifyIcon.Text throws above 63 characters, and device names run long.
    param(
        [Parameter(Mandatory = $true)]$Icon,
        [Parameter(Mandatory = $true)][string]$Text
    )

    if ($Text.Length -gt 63) { $Text = $Text.Substring(0, 60) + '...' }
    $Icon.Text = $Text
}

# --- tray icons -------------------------------------------------------------

$script:MicIcon = New-Object System.Windows.Forms.NotifyIcon
$script:MicIcon.Icon = Get-TrayIcon 'mic-on.ico'
$script:MicIcon.Text = 'Microphone'
$script:MicIcon.Visible = $true

$script:OutIcon = New-Object System.Windows.Forms.NotifyIcon
$script:OutIcon.Icon = Get-TrayIcon 'icon1.ico'
$script:OutIcon.Text = 'Audio output'
$script:OutIcon.Visible = $true

$script:MicMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:OutMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:MicIcon.ContextMenuStrip = $script:MicMenu
$script:OutIcon.ContextMenuStrip = $script:OutMenu

$script:AppContext = New-Object System.Windows.Forms.ApplicationContext

# Last rendered state, so the icons are only touched when something moved.
$script:Shown = @{ MicId = $null; MicMuted = $null; OutId = $null; Failures = 0 }

# --- state ------------------------------------------------------------------

function Get-OutputIconName {
    <#
        Alternates icon1/icon2 along the cycle order, so the two devices you
        actually swap between are visually distinct in the tray.
    #>
    param([string]$OutputId)

    if (-not $OutputId) { return 'icon1.ico' }

    try {
        $devices = @(Get-AudioDeviceList)
        $rotation = @(Get-OutputRotation -Devices $devices -ConfigDirectory $PSScriptRoot)
        if ($rotation.Count -eq 0) { $rotation = @($devices | Sort-Object Name) }

        for ($i = 0; $i -lt $rotation.Count; $i++) {
            if ($rotation[$i].Id -eq $OutputId) {
                if ($i % 2 -eq 1) { return 'icon2.ico' }
                return 'icon1.ico'
            }
        }
    }
    catch { }

    return 'icon1.ico'
}

function Update-TrayIcons {
    <#
        Reads the current state and repaints only what changed. Runs on the
        poll timer and immediately after any action we take ourselves, so a
        click feels instant rather than waiting for the next tick.
    #>
    $status = Get-AudioStatus

    if ($status.HasInput) {
        if ($script:Shown.MicMuted -ne $status.InputMuted) {
            $script:MicIcon.Icon = if ($status.InputMuted) {
                Get-TrayIcon 'mic-off.ico'
            } else {
                Get-TrayIcon 'mic-on.ico'
            }
        }
        if ($script:Shown.MicId -ne $status.InputId -or $script:Shown.MicMuted -ne $status.InputMuted) {
            $state = if ($status.InputMuted) { 'Muted' } else { 'Live' }
            Set-TrayText $script:MicIcon "Mic ($state): $($status.InputName)"
        }
        $script:Shown.MicId = $status.InputId
        $script:Shown.MicMuted = $status.InputMuted
    }
    elseif ($script:Shown.MicId -ne '<none>') {
        $script:MicIcon.Icon = Get-TrayIcon 'mic-off.ico'
        Set-TrayText $script:MicIcon 'No microphone connected'
        $script:Shown.MicId = '<none>'
        $script:Shown.MicMuted = $null
    }

    if ($status.HasOutput) {
        if ($script:Shown.OutId -ne $status.OutputId) {
            $script:OutIcon.Icon = Get-TrayIcon (Get-OutputIconName -OutputId $status.OutputId)
            Set-TrayText $script:OutIcon "Output: $($status.OutputName)"
            $script:Shown.OutId = $status.OutputId
        }
    }
    elseif ($script:Shown.OutId -ne '<none>') {
        Set-TrayText $script:OutIcon 'No audio output connected'
        $script:Shown.OutId = '<none>'
    }
}

function Show-TrayBalloon {
    param(
        [Parameter(Mandatory = $true)]$Icon,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$Timeout = 4000
    )
    try { $Icon.ShowBalloonTip($Timeout, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info) }
    catch { }
}

# --- actions ----------------------------------------------------------------

function Invoke-ToggleMic {
    try {
        $status = Get-AudioStatus
        if (-not $status.HasInput) {
            Show-TrayBalloon $script:MicIcon 'Audio Tray' 'No microphone is connected.'
            return
        }
        $null = Set-MicrophoneMute -Mute (-not $status.InputMuted)
        Update-TrayIcons
    }
    catch {
        Show-TrayBalloon $script:MicIcon 'Audio Tray' $_.Exception.Message
    }
}

function Invoke-CycleOutput {
    try {
        $devices = @(Get-AudioDeviceList)
        if ($devices.Count -lt 2) {
            Show-TrayBalloon $script:OutIcon 'Audio Tray' 'Only one output device is active.'
            return
        }

        $rotation = @(Get-OutputRotation -Devices $devices -ConfigDirectory $PSScriptRoot)
        if ($rotation.Count -eq 0) { $rotation = @($devices | Sort-Object Name) }

        $currentIndex = -1
        for ($i = 0; $i -lt $rotation.Count; $i++) {
            if ($rotation[$i].IsDefault) { $currentIndex = $i; break }
        }

        $target = if ($currentIndex -lt 0) {
            $rotation[0]
        } else {
            $rotation[($currentIndex + 1) % $rotation.Count]
        }

        Set-DefaultAudioDevice -Id $target.Id
        Update-TrayIcons
    }
    catch {
        Show-TrayBalloon $script:OutIcon 'Audio Tray' $_.Exception.Message
    }
}

function Invoke-SetDevice {
    param([Parameter(Mandatory = $true)][string]$Id)
    try {
        Set-DefaultAudioDevice -Id $Id
        Update-TrayIcons
    }
    catch {
        Show-TrayBalloon $script:OutIcon 'Audio Tray' $_.Exception.Message
    }
}

function Invoke-BluetoothToggle {
    param([Parameter(Mandatory = $true)]$Device)

    try {
        $started = Start-BluetoothConnect -Address $Device.Address `
                                          -Connect (-not $Device.Connected) `
                                          -DisplayName $Device.Name
        if (-not $started) {
            Show-TrayBalloon $script:OutIcon 'Bluetooth' 'Still working on the previous request.'
            return
        }

        $verb = if ($Device.Connected) { 'Disconnecting' } else { 'Connecting to' }
        Show-TrayBalloon $script:OutIcon 'Bluetooth' "$verb $($Device.Name)..." 2000
    }
    catch {
        Show-TrayBalloon $script:OutIcon 'Bluetooth' $_.Exception.Message
    }
}

# --- autostart --------------------------------------------------------------

function Get-StartupShortcutPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'Audio Tray.lnk'
}

function Test-AutoStart {
    Test-Path -LiteralPath (Get-StartupShortcutPath)
}

function Set-AutoStart {
    param([Parameter(Mandatory = $true)][bool]$Enabled)

    $path = Get-StartupShortcutPath
    try {
        if (-not $Enabled) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            return
        }

        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $self = Join-Path $PSScriptRoot 'AudioTray.ps1'

        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $powershell
        $link.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`""
        $link.WorkingDirectory = $PSScriptRoot
        $link.Description = 'Audio Tray - microphone and output device tray icons'
        $link.WindowStyle = 7
        $iconPath = Join-Path $script:RepoRoot 'mic-on.ico'
        if (Test-Path -LiteralPath $iconPath) { $link.IconLocation = "$iconPath,0" }
        $link.Save()
    }
    catch {
        Show-TrayBalloon $script:OutIcon 'Audio Tray' "Could not update autostart: $($_.Exception.Message)"
    }
}

# --- shutdown ---------------------------------------------------------------

function Stop-Tray {
    try { $script:Timer.Stop() } catch { }
    foreach ($icon in @($script:MicIcon, $script:OutIcon)) {
        try { $icon.Visible = $false; $icon.Dispose() } catch { }
    }
    $script:AppContext.ExitThread()
}

# --- menus ------------------------------------------------------------------

function Add-MenuHeader {
    param($Menu, [string]$Text)
    $item = $Menu.Items.Add($Text)
    $item.Enabled = $false
    return $item
}

$script:MicMenu.Add_Opening({
    $script:MicMenu.Items.Clear()

    try {
        $status = Get-AudioStatus
        Add-MenuHeader $script:MicMenu 'Microphone' | Out-Null

        $toggle = New-Object System.Windows.Forms.ToolStripMenuItem('Muted')
        $toggle.Checked = $status.InputMuted
        $toggle.Enabled = $status.HasInput
        $toggle.Add_Click({ Invoke-ToggleMic })
        $script:MicMenu.Items.Add($toggle) | Out-Null

        $script:MicMenu.Items.Add('-') | Out-Null
        Add-MenuHeader $script:MicMenu 'Input device' | Out-Null

        foreach ($device in (@(Get-AudioDeviceList -Capture) | Sort-Object Name)) {
            $item = New-Object System.Windows.Forms.ToolStripMenuItem($device.Name)
            $item.Checked = $device.IsDefault
            $item.Tag = $device.Id
            $item.Add_Click({ param($sender, $eventArgs) Invoke-SetDevice -Id $sender.Tag })
            $script:MicMenu.Items.Add($item) | Out-Null
        }
    }
    catch {
        Add-MenuHeader $script:MicMenu $_.Exception.Message | Out-Null
    }

    $script:MicMenu.Items.Add('-') | Out-Null
    $quit = New-Object System.Windows.Forms.ToolStripMenuItem('Quit Audio Tray')
    $quit.Add_Click({ Stop-Tray })
    $script:MicMenu.Items.Add($quit) | Out-Null
})

$script:OutMenu.Add_Opening({
    $script:OutMenu.Items.Clear()

    try {
        Add-MenuHeader $script:OutMenu 'Output device' | Out-Null

        foreach ($device in (@(Get-AudioDeviceList) | Sort-Object Name)) {
            $item = New-Object System.Windows.Forms.ToolStripMenuItem($device.Name)
            $item.Checked = $device.IsDefault
            $item.Tag = $device.Id
            $item.Add_Click({ param($sender, $eventArgs) Invoke-SetDevice -Id $sender.Tag })
            $script:OutMenu.Items.Add($item) | Out-Null
        }
    }
    catch {
        Add-MenuHeader $script:OutMenu $_.Exception.Message | Out-Null
    }

    # --- Bluetooth ---
    $script:OutMenu.Items.Add('-') | Out-Null
    $bluetooth = New-Object System.Windows.Forms.ToolStripMenuItem('Bluetooth')
    $script:OutMenu.Items.Add($bluetooth) | Out-Null

    try {
        if (-not (Test-BluetoothRadio)) {
            $none = $bluetooth.DropDownItems.Add('No Bluetooth radio found')
            $none.Enabled = $false
        }
        else {
            $paired = @(Get-PairedBluetoothDevice)
            if ($paired.Count -eq 0) {
                $none = $bluetooth.DropDownItems.Add('No paired devices')
                $none.Enabled = $false
            }
            else {
                foreach ($device in $paired) {
                    $label = if ($device.Connected) { "$($device.Name)  (connected)" } else { $device.Name }
                    $item = New-Object System.Windows.Forms.ToolStripMenuItem($label)
                    $item.Checked = $device.Connected
                    $item.Tag = $device
                    $item.Add_Click({ param($sender, $eventArgs) Invoke-BluetoothToggle -Device $sender.Tag })
                    $bluetooth.DropDownItems.Add($item) | Out-Null
                }
            }

            $bluetooth.DropDownItems.Add('-') | Out-Null
            $note = $bluetooth.DropDownItems.Add('Pair new devices in Windows Settings')
            $note.Enabled = $false
        }
    }
    catch {
        $failed = $bluetooth.DropDownItems.Add($_.Exception.Message)
        $failed.Enabled = $false
    }

    # --- the rest ---
    $script:OutMenu.Items.Add('-') | Out-Null

    $sound = New-Object System.Windows.Forms.ToolStripMenuItem('Windows sound settings...')
    $sound.Add_Click({
        try { Start-Process -FilePath 'control.exe' -ArgumentList 'mmsys.cpl,,0' } catch { }
    })
    $script:OutMenu.Items.Add($sound) | Out-Null

    $autostart = New-Object System.Windows.Forms.ToolStripMenuItem('Start with Windows')
    $autostart.Checked = Test-AutoStart
    $autostart.Add_Click({ param($sender, $eventArgs) Set-AutoStart -Enabled (-not $sender.Checked) })
    $script:OutMenu.Items.Add($autostart) | Out-Null

    $script:OutMenu.Items.Add('-') | Out-Null
    $quit = New-Object System.Windows.Forms.ToolStripMenuItem('Quit Audio Tray')
    $quit.Add_Click({ Stop-Tray })
    $script:OutMenu.Items.Add($quit) | Out-Null
})

# --- clicks -----------------------------------------------------------------

# MouseClick rather than Click: it is the one that reliably carries which
# button was pressed. Right-click is left alone so the context menu opens.
$script:MicIcon.Add_MouseClick({
    param($sender, $mouse)
    if ($mouse.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Invoke-ToggleMic }
})
$script:OutIcon.Add_MouseClick({
    param($sender, $mouse)
    if ($mouse.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Invoke-CycleOutput }
})

# --- poll timer -------------------------------------------------------------

$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = $PollMilliseconds
$script:Timer.Add_Tick({
    try {
        Update-TrayIcons
        $script:Shown.Failures = 0

        $message = Receive-BluetoothResult
        if ($message) {
            Show-TrayBalloon $script:OutIcon 'Bluetooth' $message
            # A connect changes which endpoints exist; re-read on the next tick.
            $script:Shown.OutId = $null
        }
    }
    catch {
        # Never let a transient COM failure take the whole tray down. Windows
        # briefly refuses these calls while devices are being re-enumerated.
        $script:Shown.Failures++
        if ($script:Shown.Failures -eq 5) {
            Show-TrayBalloon $script:MicIcon 'Audio Tray' "Audio state is unreadable: $($_.Exception.Message)"
        }
    }
})

# --- run --------------------------------------------------------------------

try {
    Update-TrayIcons
}
catch {
    Show-TrayBalloon $script:MicIcon 'Audio Tray' $_.Exception.Message
}

$script:Timer.Start()

try {
    [System.Windows.Forms.Application]::Run($script:AppContext)
}
finally {
    # Without an explicit dispose the icons linger in the tray until hovered.
    foreach ($icon in @($script:MicIcon, $script:OutIcon)) {
        try { $icon.Visible = $false; $icon.Dispose() } catch { }
    }
    try { $script:Timer.Dispose() } catch { }
    try { $script:Mutex.ReleaseMutex() } catch { }
    try { $script:Mutex.Dispose() } catch { }
}
