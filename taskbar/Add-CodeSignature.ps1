<#
.SYNOPSIS
    Signs the scripts in this folder with a self-signed certificate.

.DESCRIPTION
    Only needed when Group Policy pins the execution policy to AllSigned.
    In that situation -ExecutionPolicy Bypass is ignored and unsigned scripts
    will not run, no matter how they are launched.

    This creates a code-signing certificate in your own certificate store,
    trusts it for your own account, and signs the .ps1 files. No admin rights
    and no machine-wide changes are involved: everything lands under
    Cert:\CurrentUser.

    Windows will show a security prompt when the certificate is added to your
    trusted roots. That prompt is expected - you are being asked to confirm
    that you trust code you signed yourself.

    A caveat worth reading before you start: some managed environments do not
    honour the per-user root store for script signing, or block writes to it
    outright. If that is the case here, this will not help and the
    shortcut-only approach (Install-Shortcuts.ps1 -NativeOnly) is the answer.

.PARAMETER Subject
    Certificate subject name. Defaults to CN=Audio Tray Tools (self-signed).

.PARAMETER Remove
    Delete the certificate this script created and stop trusting it. Existing
    signatures stay on the files but no longer validate.

.EXAMPLE
    .\Add-CodeSignature.ps1
#>
[CmdletBinding()]
param(
    [string]$Subject = 'CN=Audio Tray Tools (self-signed)',
    [switch]$Remove
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$stores = @('Cert:\CurrentUser\My', 'Cert:\CurrentUser\Root', 'Cert:\CurrentUser\TrustedPublisher')

if ($Remove) {
    $removed = 0
    foreach ($store in $stores) {
        Get-ChildItem -Path $store -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -eq $Subject } |
            ForEach-Object {
                Remove-Item -Path $_.PSPath -Force
                Write-Host "Removed $($_.Thumbprint) from $store"
                $removed++
            }
    }
    if ($removed -eq 0) { Write-Host 'Nothing to remove.' }
    exit 0
}

if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
    throw 'New-SelfSignedCertificate is not available on this system (needs Windows 8.1 or newer).'
}

$existing = Get-ChildItem -Path Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $Subject -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1

if ($existing) {
    $certificate = $existing
    Write-Host "Reusing certificate $($certificate.Thumbprint)"
}
else {
    Write-Host 'Creating a code-signing certificate...'
    $certificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $Subject `
        -CertStoreLocation Cert:\CurrentUser\My `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy NonExportable `
        -NotAfter (Get-Date).AddYears(5)
    Write-Host "Created $($certificate.Thumbprint)"
}

# Trusting it for this user only. Both stores are needed: Root makes the chain
# valid, TrustedPublisher stops PowerShell asking about every script.
Write-Host 'Adding it to your trusted roots and trusted publishers...'
Write-Host '(Approve the Windows security prompt if one appears.)' -ForegroundColor DarkGray

foreach ($storeName in @('Root', 'TrustedPublisher')) {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, 'CurrentUser')
    $store.Open('ReadWrite')
    try {
        if (-not $store.Certificates.Find('FindByThumbprint', $certificate.Thumbprint, $false).Count) {
            $store.Add($certificate)
            Write-Host "  added to CurrentUser\$storeName"
        } else {
            Write-Host "  already in CurrentUser\$storeName"
        }
    }
    finally { $store.Close() }
}

Write-Host ''
Write-Host 'Signing scripts:'

$failed = 0
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | Sort-Object Name) {
    $result = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $certificate `
        -HashAlgorithm SHA256 -ErrorAction Continue

    $colour = if ($result.Status -eq 'Valid') { 'Green' } else { 'Red' }
    if ($result.Status -ne 'Valid') { $failed++ }

    Write-Host "  $($file.Name.PadRight(26))" -NoNewline
    Write-Host $result.Status -ForegroundColor $colour
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host "$failed script(s) did not sign cleanly. This machine may be blocking the signing key." -ForegroundColor Yellow
    Write-Host 'Fall back to:  .\Install-Shortcuts.ps1 -NativeOnly' -ForegroundColor Yellow
    exit 1
}

Write-Host 'Done. Re-run Install-Shortcuts.ps1 if you have not already.' -ForegroundColor Green
Write-Host 'Note: editing a script invalidates its signature - re-run this afterwards.' -ForegroundColor DarkGray
