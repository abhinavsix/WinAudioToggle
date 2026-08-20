<#
.SYNOPSIS
    Switches the default audio output device, shows a brief confirmation, and exits.

.DESCRIPTION
    Designed to be launched from a taskbar shortcut or a global hotkey. The
    process lives for about a second and a half and then goes away - nothing
    stays resident, and no modules are installed.

    With no arguments it cycles to the next output. Most machines expose
    several endpoints you never actually use (HDMI monitors, virtual cables),
    so you can narrow the rotation by creating an outputs.txt beside this
    script with one name fragment per line, in the order you want to cycle:

        Headset
        Speakers

    Anything that does not match an active device is skipped, so the same
    file can be shared across a laptop and a dock.

.PARAMETER Name
    Switch straight to the first device whose name matches. Wildcards allowed;
    a bare substring works too.

.PARAMETER List
    Print the active output devices and exit without changing anything.

.PARAMETER Quiet
    Skip the on-screen confirmation.

.EXAMPLE
    .\Switch-Output.ps1
    Moves to the next output device in the rotation.

.EXAMPLE
    .\Switch-Output.ps1 -Name 'Headset'
    Switches directly to the first device with "Headset" in its name.

.EXAMPLE
    .\Switch-Output.ps1 -List
    Shows what is available, with the current default marked.
#>
[CmdletBinding(DefaultParameterSetName = 'Cycle')]
param(
    [Parameter(ParameterSetName = 'Named', Position = 0)][string]$Name,
    [Parameter(ParameterSetName = 'List')][switch]$List,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AudioControl.ps1')

try {
    $devices = @(Get-AudioDeviceList)

    if ($devices.Count -eq 0) {
        throw 'Windows reports no active audio output devices.'
    }

    if ($List) {
        # Written out by hand rather than with Format-Table: the formatter
        # needs a console width to render, and produces nothing at all in
        # hosts that do not report one.
        Write-Host ''
        Write-Host '  Active output devices (* = current):'
        Write-Host ''
        foreach ($device in ($devices | Sort-Object Name)) {
            $marker = if ($device.IsDefault) { '*' } else { ' ' }
            Write-Host "   $marker  $($device.Name)"
        }
        Write-Host ''
        Write-Host '  Use any part of a name with -Name, or in outputs.txt.' -ForegroundColor DarkGray
        Write-Host ''
        exit 0
    }

    if ($PSCmdlet.ParameterSetName -eq 'Named') {
        $target = $devices | Where-Object { $_.Name -like "*$Name*" } | Select-Object -First 1
        if (-not $target) {
            throw "No active output device matches '$Name'. Run with -List to see what is available."
        }
    }
    else {
        $rotation = @(Get-OutputRotation -Devices $devices -ConfigDirectory $PSScriptRoot)
        if ($rotation.Count -eq 0) { $rotation = @($devices | Sort-Object Name) }

        if ($rotation.Count -eq 1) {
            throw "Only one output device is active ($($rotation[0].Name)), so there is nothing to switch to."
        }

        $currentIndex = -1
        for ($i = 0; $i -lt $rotation.Count; $i++) {
            if ($rotation[$i].IsDefault) { $currentIndex = $i; break }
        }

        # If the current default sits outside the rotation, jump into it at the top.
        $target = if ($currentIndex -lt 0) {
            $rotation[0]
        } else {
            $rotation[($currentIndex + 1) % $rotation.Count]
        }
    }

    if ($target.IsDefault) {
        if (-not $Quiet) { Show-AudioOsd -Title 'Output unchanged' -Detail $target.Name }
        exit 0
    }

    Set-DefaultAudioDevice -Id $target.Id

    if (-not $Quiet) {
        Show-AudioOsd -Title 'Output switched' -Detail $target.Name
    }

    exit 0
}
catch {
    Write-AudioError $_.Exception.Message
    exit 1
}
