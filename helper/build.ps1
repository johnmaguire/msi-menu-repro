[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The x64 .NET Framework C# compiler is required. Run this build on 64-bit Windows.'
}

$output = New-Item -ItemType Directory -Path $OutputDirectory -Force
$nativeOutput = Join-Path $output.FullName 'Repro.Native.dll'
$sleeperOutput = Join-Path $output.FullName 'msi-menu-repro-sleeper.exe'

& $compiler /nologo /target:library /platform:x64 /optimize+ /warnaserror+ "/out:$nativeOutput" (Join-Path $PSScriptRoot 'Native.cs')
if ($LASTEXITCODE -ne 0) {
    throw "Native helper compilation failed with exit code $LASTEXITCODE."
}

& $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ "/out:$sleeperOutput" (Join-Path $PSScriptRoot 'Sleeper.cs')
if ($LASTEXITCODE -ne 0) {
    throw "Sleeper compilation failed with exit code $LASTEXITCODE."
}

Get-Item -LiteralPath $nativeOutput, $sleeperOutput
