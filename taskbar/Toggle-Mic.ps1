<#
.SYNOPSIS
    Mutes or unmutes the microphone, shows a brief confirmation, and exits.

.DESCRIPTION
    Designed to be launched from a taskbar shortcut or a global hotkey. The
    process lives for about a second and a half and then goes away - nothing
    stays resident, and no modules are installed.

    By default the mute state is applied to both the default microphone and
    the default "communications" microphone, since Teams, Zoom and Slack use
    the latter and it is frequently a different device.

.PARAMETER Mute
    Force muted, regardless of the current state.

.PARAMETER Unmute
    Force unmuted, regardless of the current state.

.PARAMETER AllDevices
    Apply to every active microphone rather than just the defaults.

.PARAMETER Quiet
    Skip the on-screen confirmation.

.EXAMPLE
    .\Toggle-Mic.ps1
    Flips the microphone between muted and unmuted.

.EXAMPLE
    .\Toggle-Mic.ps1 -Mute -Quiet
    Force mute with no pop-up. Useful at the top of a meeting-join script.
#>
[CmdletBinding(DefaultParameterSetName = 'Toggle')]
param(
    [Parameter(ParameterSetName = 'Mute')][switch]$Mute,
    [Parameter(ParameterSetName = 'Unmute')][switch]$Unmute,
    [switch]$AllDevices,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'AudioControl.ps1')

try {
    $target = switch ($PSCmdlet.ParameterSetName) {
        'Mute'   { $true }
        'Unmute' { $false }
        default  { -not (Get-MicrophoneMute) }
    }

    $count = Set-MicrophoneMute -Mute $target -AllDevices:$AllDevices

    if (-not $Quiet) {
        $device = Get-DefaultAudioDevice -Capture
        $detail = if ($AllDevices) {
            "$count microphone(s)"
        } elseif ($device) {
            $device.Name
        } else {
            ''
        }

        if ($target) {
            Show-AudioOsd -Title 'Microphone muted' -Detail $detail -Style Alert
        } else {
            Show-AudioOsd -Title 'Microphone live' -Detail $detail
        }
    }

    exit 0
}
catch {
    Write-AudioError $_.Exception.Message
    exit 1
}
