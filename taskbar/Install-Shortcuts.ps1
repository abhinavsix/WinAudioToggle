<#
.SYNOPSIS
    Creates the taskbar shortcuts for the audio tools.

.DESCRIPTION
    Writes .lnk files into your own Start Menu folder (no admin rights, no
    registry changes, nothing under Program Files). From there you can
    right-click each one and choose "Pin to taskbar".

    Each shortcut also gets a global hotkey. Windows implements shortcut
    hotkeys itself, so you get Ctrl+Alt+M mic mute with no background process
    of any kind listening for keystrokes.

    Two of the shortcuts run no script at all - they open the audio pages
    Windows already ships. Those work on absolutely any machine, however
    locked down. Use -NativeOnly if scripts are off the table entirely.

.PARAMETER NativeOnly
    Only create the shortcuts that open built-in Windows audio panels.

.PARAMETER Desktop
    Also drop the shortcuts on the Desktop.

.PARAMETER MicHotkey
    Hotkey for the mic toggle. Defaults to CTRL+ALT+M. Pass '' for none.

.PARAMETER OutputHotkey
    Hotkey for the output switcher. Defaults to CTRL+ALT+O. Pass '' for none.

.PARAMETER Uninstall
    Remove everything this script created.

.EXAMPLE
    .\Install-Shortcuts.ps1

.EXAMPLE
    .\Install-Shortcuts.ps1 -NativeOnly
#>
[CmdletBinding()]
param(
    [switch]$NativeOnly,
    [switch]$Desktop,
    [string]$MicHotkey = 'CTRL+ALT+M',
    [string]$OutputHotkey = 'CTRL+ALT+O',
    [switch]$Uninstall
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$folderName  = 'Audio Tray Tools'
$startMenu   = Join-Path ([Environment]::GetFolderPath('Programs')) $folderName
$desktopPath = [Environment]::GetFolderPath('Desktop')
$repoRoot    = Split-Path -Parent $PSScriptRoot

if ($Uninstall) {
    if (Test-Path -LiteralPath $startMenu) {
        Remove-Item -LiteralPath $startMenu -Recurse -Force
        Write-Host "Removed $startMenu"
    }
    Get-ChildItem -LiteralPath $desktopPath -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -in @('Mute Microphone', 'Switch Audio Output',
                                         'Sound Devices (Playback)', 'Sound Devices (Recording)') } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force; Write-Host "Removed $($_.Name)" }

    Write-Host 'Done. Unpin anything left on the taskbar by hand.'
    exit 0
}

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powershell)) {
    throw "Could not find powershell.exe at $powershell."
}

New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell

function New-AppShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$Icon = '',
        [string]$Hotkey = '',
        [string]$Description = ''
    )

    $targets = @($startMenu)
    if ($Desktop) { $targets += $desktopPath }

    foreach ($dir in $targets) {
        $path = Join-Path $dir "$Name.lnk"
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $Target
        $link.Arguments = $Arguments
        $link.Description = $Description
        if ($WorkingDirectory) { $link.WorkingDirectory = $WorkingDirectory }
        if ($Icon) { $link.IconLocation = "$Icon,0" }
        if ($Hotkey) { $link.Hotkey = $Hotkey }
        # 7 = minimised, which keeps the console flash to a single frame.
        $link.WindowStyle = 7
        $link.Save()
        Write-Host "  $path"
    }
}

function Get-IconPath {
    # Returns '' when the icon is missing, so the shortcut just keeps the
    # default PowerShell icon rather than failing.
    param([string]$FileName)
    $path = Join-Path $repoRoot $FileName
    if (Test-Path -LiteralPath $path) { return $path }
    return ''
}

Write-Host ''
Write-Host 'Creating shortcuts:' -ForegroundColor Cyan

# Always available: the audio UI Windows already ships. No script runs, so
# these survive any execution policy, AppLocker rule or antivirus setting.
New-AppShortcut -Name 'Sound Devices (Playback)' `
    -Target (Join-Path $env:SystemRoot 'System32\control.exe') `
    -Arguments 'mmsys.cpl,,0' `
    -Icon (Get-IconPath 'icon1.ico') `
    -Description 'Open the Windows playback device list'

New-AppShortcut -Name 'Sound Devices (Recording)' `
    -Target (Join-Path $env:SystemRoot 'System32\control.exe') `
    -Arguments 'mmsys.cpl,,1' `
    -Icon (Get-IconPath 'mic-on.ico') `
    -Description 'Open the Windows recording device list'

if (-not $NativeOnly) {
    $micScript = Join-Path $PSScriptRoot 'Toggle-Mic.ps1'
    $outScript = Join-Path $PSScriptRoot 'Switch-Output.ps1'

    foreach ($script in @($micScript, $outScript)) {
        if (-not (Test-Path -LiteralPath $script)) { throw "Missing script: $script" }
    }

    # -NoProfile matters for more than speed: it sidesteps profile scripts that
    # corporate images often use to constrain the session.
    $common = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File'

    New-AppShortcut -Name 'Mute Microphone' `
        -Target $powershell `
        -Arguments "$common `"$micScript`"" `
        -WorkingDirectory $PSScriptRoot `
        -Icon (Get-IconPath 'mic-off.ico') `
        -Hotkey $MicHotkey `
        -Description 'Toggle the microphone mute state'

    New-AppShortcut -Name 'Switch Audio Output' `
        -Target $powershell `
        -Arguments "$common `"$outScript`"" `
        -WorkingDirectory $PSScriptRoot `
        -Icon (Get-IconPath 'icon2.ico') `
        -Hotkey $OutputHotkey `
        -Description 'Cycle the default audio output device'
}

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  1. Open Start and find the '$folderName' folder."
Write-Host '  2. Right-click a shortcut and choose Pin to taskbar.'
if (-not $NativeOnly) {
    if ($MicHotkey)    { Write-Host "  3. $MicHotkey toggles the microphone from anywhere." }
    if ($OutputHotkey) { Write-Host "     $OutputHotkey cycles the audio output." }
}
Write-Host ''
