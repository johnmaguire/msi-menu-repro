#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') {
    throw 'Build on Windows with the .NET 8 SDK and Windows PowerShell 5.1 installed.'
}

$outputRoot = Join-Path $PSScriptRoot 'dist'
$packageDirectory = Join-Path $outputRoot 'msi-menu-repro'
$installerOutput = Join-Path $PSScriptRoot '.build\installer'
New-Item -ItemType Directory -Force -Path $outputRoot, $installerOutput | Out-Null
if (Test-Path -LiteralPath $packageDirectory) {
    Remove-Item -LiteralPath $packageDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $packageDirectory | Out-Null

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $PSScriptRoot 'helper\build.ps1') -OutputDirectory $packageDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Helper build failed with exit code $LASTEXITCODE."
}

Push-Location (Join-Path $PSScriptRoot 'installer')
try {
    & dotnet build Repro.wixproj --configuration Release --output $installerOutput
    if ($LASTEXITCODE -ne 0) {
        throw "WiX build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$builtMsi = Join-Path $installerOutput 'MsiMenuRepro.msi'
if (-not (Test-Path -LiteralPath $builtMsi -PathType Leaf)) {
    throw "WiX did not produce $builtMsi."
}
Copy-Item -LiteralPath $builtMsi -Destination $packageDirectory
foreach ($name in @('repro.ps1', 'standin.ps1', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $packageDirectory
}
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSE') -Destination $packageDirectory
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs') -Destination $packageDirectory -Recurse
foreach ($name in @('Repro.Native.dll', 'msi-menu-repro-sleeper.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageDirectory $name) -PathType Leaf)) {
        throw "Helper build did not produce $name."
    }
}

$checksums = Get-ChildItem -LiteralPath $packageDirectory -File -Recurse | Sort-Object FullName | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.FullName.Substring($packageDirectory.Length + 1).Replace('\','/')
}
[IO.File]::WriteAllText((Join-Path $packageDirectory 'SHA256SUMS'), ($checksums -join "`n") + "`n", [Text.Encoding]::ASCII)

$archive = Join-Path $outputRoot 'msi-menu-repro.zip'
Compress-Archive -Path (Join-Path $packageDirectory '*') -DestinationPath $archive -Force
$archiveChecksum = '{0}  msi-menu-repro.zip' -f (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $outputRoot 'msi-menu-repro.zip.sha256'), $archiveChecksum + "`n", [Text.Encoding]::ASCII)
Write-Host "Built $archive"
