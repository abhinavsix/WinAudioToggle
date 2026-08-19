<#
.SYNOPSIS
    Reports whether the taskbar audio tools will work on this machine.

.DESCRIPTION
    Read-only. Nothing is installed, no device is changed, no policy is
    touched. Run this first on a managed or work PC to find out which of the
    three approaches in the README you can actually use.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Compatibility.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0

$script:Blockers = @()
$script:Warnings = @()

function Write-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('Pass', 'Warn', 'Fail', 'Info')][string]$Result,
        [string]$Detail = ''
    )

    $colour = switch ($Result) {
        'Pass' { 'Green' }
        'Warn' { 'Yellow' }
        'Fail' { 'Red' }
        default { 'Gray' }
    }
    $tag = switch ($Result) {
        'Pass' { ' ok ' }
        'Warn' { 'warn' }
        'Fail' { 'FAIL' }
        default { ' -- ' }
    }

    Write-Host '  [' -NoNewline
    Write-Host $tag -NoNewline -ForegroundColor $colour
    Write-Host '] ' -NoNewline
    Write-Host $Name.PadRight(30) -NoNewline
    Write-Host $Detail -ForegroundColor DarkGray
}

function Add-Blocker { param([string]$Text) $script:Blockers += $Text }
function Add-Warning { param([string]$Text) $script:Warnings += $Text }

Write-Host ''
Write-Host 'Audio Tray Tools - compatibility check' -ForegroundColor Cyan
Write-Host ('-' * 62)
Write-Host ''

# --- PowerShell itself ------------------------------------------------------

Write-Host 'PowerShell' -ForegroundColor White

$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 5) {
    Write-Check 'Version' 'Pass' $psVersion
} else {
    Write-Check 'Version' 'Fail' "$psVersion (need 5.0 or newer)"
    Add-Blocker 'PowerShell is older than 5.0.'
}

$languageMode = $ExecutionContext.SessionState.LanguageMode
if ($languageMode -eq 'FullLanguage') {
    Write-Check 'Language mode' 'Pass' $languageMode
} else {
    Write-Check 'Language mode' 'Fail' $languageMode
    Add-Blocker ("PowerShell is running in $languageMode. This blocks the .NET calls " +
                 'every scripted audio tool needs - including AudioDeviceCmdlets. ' +
                 'Use the shortcut-only approach (Install-Shortcuts.ps1 -NativeOnly).')
}

$policies = Get-ExecutionPolicy -List
$effective = Get-ExecutionPolicy
$forcedBy = $policies | Where-Object {
    ($_.Scope -in @('MachinePolicy', 'UserPolicy')) -and ($_.ExecutionPolicy -ne 'Undefined')
}

if ($forcedBy) {
    $scope = ($forcedBy | Select-Object -First 1)
    if ($scope.ExecutionPolicy -in 'AllSigned', 'Restricted') {
        Write-Check 'Execution policy' 'Fail' "$($scope.ExecutionPolicy), set by Group Policy ($($scope.Scope))"
        Add-Blocker ("Group Policy pins the execution policy to $($scope.ExecutionPolicy), which -ExecutionPolicy Bypass " +
                     'cannot override. Sign the scripts with Add-CodeSignature.ps1, or use -NativeOnly.')
    } else {
        Write-Check 'Execution policy' 'Warn' "$($scope.ExecutionPolicy), set by Group Policy ($($scope.Scope))"
        Add-Warning 'Execution policy is managed by Group Policy but still permits these scripts.'
    }
} else {
    Write-Check 'Execution policy' 'Pass' "$effective (not enforced by policy; shortcuts pass -ExecutionPolicy Bypass)"
}

# --- Compilation ------------------------------------------------------------

Write-Host ''
Write-Host 'Runtime compilation' -ForegroundColor White

$canCompile = $false
try {
    $probe = 'WinAudioToggleProbe' + [Guid]::NewGuid().ToString('N')
    Add-Type -TypeDefinition "public static class $probe { public static int Ping() { return 1; } }" -ErrorAction Stop
    $canCompile = $true
    Write-Check 'Add-Type' 'Pass' 'C# compiles and loads'
}
catch {
    Write-Check 'Add-Type' 'Fail' $_.Exception.Message
    Add-Blocker ('This machine will not let PowerShell compile and load code at runtime, which the ' +
                 'scripted tools require. Use Install-Shortcuts.ps1 -NativeOnly.')
}

# --- The audio APIs themselves ---------------------------------------------

Write-Host ''
Write-Host 'Windows audio APIs' -ForegroundColor White

if ($canCompile) {
    try {
        . (Join-Path $PSScriptRoot 'AudioControl.ps1')
        Initialize-AudioTypes
        Write-Check 'Core Audio interop' 'Pass' 'loaded'

        try {
            $mic = Get-DefaultAudioDevice -Capture
            if ($mic) {
                $state = if (Get-MicrophoneMute) { 'muted' } else { 'live' }
                Write-Check 'Default microphone' 'Pass' "$($mic.Name) - currently $state"
            } else {
                Write-Check 'Default microphone' 'Warn' 'none found'
                Add-Warning 'No microphone is currently active, so Toggle-Mic.ps1 has nothing to act on.'
            }
        }
        catch {
            Write-Check 'Default microphone' 'Fail' $_.Exception.Message
            Add-Blocker 'Reading the microphone mute state failed.'
        }

        try {
            $outputs = @(Get-AudioDeviceList)
            $current = $outputs | Where-Object { $_.IsDefault } | Select-Object -First 1
            $detail = "$($outputs.Count) active"
            if ($current) { $detail += "; now on $($current.Name)" }
            Write-Check 'Output devices' 'Pass' $detail

            if ($outputs.Count -lt 2) {
                Add-Warning 'Only one output device is active, so there is nothing to switch between yet.'
            }
        }
        catch {
            Write-Check 'Output devices' 'Fail' $_.Exception.Message
            Add-Blocker 'Enumerating output devices failed.'
        }

        try {
            $flavour = Test-DefaultDeviceSupport
            if ($flavour) {
                Write-Check 'Device switching' 'Pass' "$flavour available"
            } else {
                Write-Check 'Device switching' 'Fail' 'PolicyConfig refused'
                Add-Blocker ('Windows will not expose the interface used to change the default output device. ' +
                             'Toggle-Mic.ps1 will still work; use the Sound Devices shortcut to switch outputs.')
            }
        }
        catch {
            Write-Check 'Device switching' 'Fail' $_.Exception.Message
            Add-Blocker 'Probing the default-device switching interface failed.'
        }
    }
    catch {
        Write-Check 'Core Audio interop' 'Fail' $_.Exception.Message
        Add-Blocker 'The audio interop layer would not load.'
    }
}
else {
    Write-Check 'Core Audio interop' 'Info' 'skipped - Add-Type is unavailable'
}

# --- Things that commonly get in the way ------------------------------------

Write-Host ''
Write-Host 'Security policy' -ForegroundColor White

try {
    $guard = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    $enforcement = $guard.CodeIntegrityPolicyEnforcementStatus
    switch ($enforcement) {
        0 { Write-Check 'WDAC code integrity' 'Pass' 'off' }
        1 { Write-Check 'WDAC code integrity' 'Warn' 'audit mode'
            Add-Warning 'WDAC is in audit mode. It will not block you today, but it may once enforced.' }
        2 { Write-Check 'WDAC code integrity' 'Warn' 'enforced'
            Add-Warning ('WDAC is enforced. Runtime-compiled code is frequently blocked under it; ' +
                         'if the checks above passed you are fine, otherwise use -NativeOnly.') }
        default { Write-Check 'WDAC code integrity' 'Info' "status $enforcement" }
    }
}
catch {
    Write-Check 'WDAC code integrity' 'Info' 'not reported'
}

$appLockerKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2'
if (Test-Path -LiteralPath $appLockerKey) {
    $scriptRules = Join-Path $appLockerKey 'Script'
    if (Test-Path -LiteralPath $scriptRules) {
        Write-Check 'AppLocker' 'Warn' 'script rules are configured'
        Add-Warning ('AppLocker has script rules. If the scripted tools misbehave, it is likely ' +
                     'refusing to run .ps1 files from your profile - ask IT for the approved location, ' +
                     'or use -NativeOnly.')
    } else {
        Write-Check 'AppLocker' 'Pass' 'present, no script rules'
    }
} else {
    Write-Check 'AppLocker' 'Pass' 'not configured'
}

try {
    $defender = Get-MpPreference -ErrorAction Stop
    if ($defender.EnableControlledFolderAccess -eq 1) {
        Write-Check 'Controlled folder access' 'Warn' 'on'
        Add-Warning ('Controlled folder access is on. If Install-Shortcuts.ps1 cannot write to the ' +
                     'Start Menu or Desktop, that is why.')
    } else {
        Write-Check 'Controlled folder access' 'Pass' 'off'
    }

    # Filter the nulls out: @($null) still has a Count of 1.
    $asr = @($defender.AttackSurfaceReductionRules_Ids | Where-Object { $_ })
    if ($asr.Count -gt 0) {
        Write-Check 'ASR rules' 'Warn' "$($asr.Count) configured"
        Add-Warning ('Defender attack-surface-reduction rules are configured. One of them blocks ' +
                     'obfuscated scripts - these scripts are plain text and should pass, but if a ' +
                     'shortcut silently does nothing, check the Defender log.')
    } else {
        Write-Check 'ASR rules' 'Pass' 'none'
    }
}
catch {
    Write-Check 'Defender settings' 'Info' 'not readable from this account'
}

# --- Verdict ----------------------------------------------------------------

Write-Host ''
Write-Host ('-' * 62)

if ($script:Blockers.Count -eq 0) {
    Write-Host 'Verdict: the scripted tools should work here.' -ForegroundColor Green
    Write-Host '  Run  .\Install-Shortcuts.ps1  to create the taskbar shortcuts.'
} else {
    Write-Host 'Verdict: something will get in the way.' -ForegroundColor Yellow
    foreach ($blocker in $script:Blockers) {
        Write-Host ''
        Write-Host "  * $blocker" -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '  The shortcut-only approach needs none of the above:'
    Write-Host '    .\Install-Shortcuts.ps1 -NativeOnly'
}

if ($script:Warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Also worth knowing:' -ForegroundColor DarkGray
    foreach ($warning in $script:Warnings) {
        Write-Host "  - $warning" -ForegroundColor DarkGray
    }
}

Write-Host ''
exit ([int]($script:Blockers.Count -gt 0))
