#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$MsiPath = (Join-Path $PSScriptRoot '..\dist\msi-menu-repro\MsiMenuRepro.msi'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.build\smoke')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$productCode = '{5808E40F-7F07-400C-ADE4-8F502704811D}'
$uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
$payloadPath = Join-Path $env:ProgramFiles 'MSI Menu Reproduction\payload.txt'
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (Test-Path -LiteralPath $uninstallKey) {
    throw 'MSI Menu Reproduction is already installed. Run this smoke test on a clean machine.'
}

function Invoke-QuietMsi([string]$Operation, [string]$Target, [string]$LogName) {
    $logPath = Join-Path $OutputDirectory $LogName
    $arguments = "$Operation `"$Target`" /qn /norestart /L*vx! `"$logPath`""
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -PassThru
    if (-not $process.WaitForExit(120000)) {
        throw "MSI operation timed out. See $logPath."
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) {
        throw "MSI exited with $($process.ExitCode). See $logPath."
    }
}

try {
    Invoke-QuietMsi '/i' $MsiPath 'install.log'
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        throw "The installer did not create $payloadPath."
    }
    if ((Get-ItemProperty -LiteralPath $uninstallKey).DisplayName -ne 'MSI Menu Reproduction') {
        throw 'The installed product identity does not match.'
    }
}
finally {
    if (Test-Path -LiteralPath $uninstallKey) {
        Invoke-QuietMsi '/x' $productCode 'uninstall.log'
    }
}
if (Test-Path -LiteralPath $payloadPath) {
    throw 'The uninstaller left the payload behind.'
}
if (Test-Path -LiteralPath $uninstallKey) {
    throw 'The uninstaller left the product registered.'
}
Write-Host 'Quiet install/uninstall passed. Interactive menu behavior is not exercised by this test.'
