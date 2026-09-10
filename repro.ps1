#Requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('Input')][ValidateSet('TightVncReset','AltTap','None')][string]$InputMode = 'TightVncReset',
    [ValidateSet('Full','Passive')][string]$UI = 'Full',
    [string]$MsiPath,
    [string]$OutputDirectory,
    [ValidateRange(15,120)][int]$ObserveSeconds = 25,
    [switch]$KeepInstalled
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$productCode = '{5808E40F-7F07-400C-ADE4-8F502704811D}'
$productName = 'MSI Menu Reproduction'
$completionAction = if ($UI -eq 'Full') { 'ExecuteAction' } else { 'INSTALL' }
$completionPattern = 'Action ended [^\r\n]*' + $completionAction + '\. Return value 1\.'
if ($env:OS -ne 'Windows_NT') { throw 'Run this reproduction on Windows.' }
if (-not [Environment]::Is64BitProcess) { throw 'Run the reproduction in 64-bit Windows PowerShell.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run repro.ps1 from an elevated PowerShell window so input can reach the installer.'
}
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'An interactive desktop session is required.' }
$assetDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $assetDir 'MsiMenuRepro.msi'))) { $assetDir = Join-Path $assetDir 'dist\msi-menu-repro' }
if (-not $MsiPath) { $MsiPath = Join-Path $assetDir 'MsiMenuRepro.msi' }
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
$nativePath = Join-Path $assetDir 'Repro.Native.dll'
$sleeperPath = Join-Path $assetDir 'msi-menu-repro-sleeper.exe'
foreach ($path in $nativePath,$sleeperPath) { if (-not (Test-Path -LiteralPath $path)) { throw "Missing $path; run build.ps1 or extract the complete ZIP." } }
Add-Type -Path $nativePath
$created = $false
$mutex = New-Object Threading.Mutex($true,'Local\MsiMenuRepro',[ref]$created)
if (-not $created) { $mutex.Dispose(); throw 'Another reproduction runner is active in this session.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot ('results\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + $InputMode + '-' + $UI) }
if (Test-Path -LiteralPath $OutputDirectory) { $mutex.ReleaseMutex(); $mutex.Dispose(); throw "Output directory already exists: $OutputDirectory" }
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$logPath = Join-Path $OutputDirectory 'install.log'
$eventPath = Join-Path $OutputDirectory 'events.log'
$msi = $null
$sleeper = $null
$packageValidated = $false
$dialog = [IntPtr]::Zero
$result = [ordered]@{
    schemaVersion=1; input=$InputMode; ui=$UI; startedAt=[DateTime]::UtcNow.ToString('o'); verdict='InvalidTest'
    package=$MsiPath; productCode=$productCode; packageSha256=(Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash
    observeSeconds=$ObserveSeconds; totalObservationSeconds=(10+$ObserveSeconds); injectionAt=$null; injection=$null; keyboardBefore=$null; windowAtInjection=$null
    menuSeen=$false; menuModeAtObservationEnd=$false; completedBeforeRelease=$false
    preReleaseLogQuietSeconds=$null; releaseSent=$false; releaseInput=$null; progressedAfterRelease=$false
    installerExitCode=$null; cleanupExitCode=$null; keepInstalled=[bool]$KeepInstalled; error=$null; cleanupError=$null
}
function Log([string]$message) {
    $stream = [IO.File]::Open($eventPath,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    $writer = New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false)))
    try { $writer.WriteLine(('{0} {1}' -f [DateTime]::UtcNow.ToString('o'),$message)) } finally { $writer.Dispose() }
}
function ReadLog {
    if (-not (Test-Path -LiteralPath $logPath)) { return '' }
    $stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::Unicode,$true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Snapshot([IntPtr]$window) {
    $s = [MsiMenuRepro.Native]::Snapshot($window)
    return [ordered]@{valid=$s.Valid;error=$s.Error;hwnd=('0x{0:X}' -f $window.ToInt64());pid=$s.Pid;tid=$s.Tid;className=$s.ClassName;isForeground=$s.IsForeground;flags=$s.Flags;menuOwner=('0x{0:X}' -f $s.MenuOwner.ToInt64());focus=('0x{0:X}' -f $s.Focus.ToInt64())}
}
function CheckInput($sent) { if (-not $sent.Success) { throw ('Input injection failed: ' + ($sent | ConvertTo-Json -Depth 5 -Compress)) } }
function CheckNavigationInput($sent) {
    # Enter can replace the wizard window before SendInput returns.
    if ($sent.Attempted -eq 0 -and $sent.Injected -eq 0) { Log 'Wizard window changed before Enter; retrying'; return }
    if ($sent.Attempted -ne 2 -or $sent.Injected -ne 2) { CheckInput $sent }
}
function ReadIdentity {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $null
    try {
        $db = $installer.OpenDatabase($MsiPath,0)
        $properties = @{}
        foreach ($name in 'ProductCode','ProductName') {
            $view = $db.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$name'")
            $record = $null
            try {
                [void]$view.Execute(); $record=$view.Fetch()
                if ($record) { $properties[$name] = $record.GetType().InvokeMember('StringData','GetProperty',$null,$record,@(1)) }
            } finally {
                if ($record) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) }
                [void]$view.Close(); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)
            }
        }
        return $properties
    } finally {
        if ($db) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($db) }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
    }
}
function Installed {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
    if (-not (Test-Path $key)) { return $false }
    $product = Get-ItemProperty -LiteralPath $key
    if ($product.DisplayName -ne $productName) { throw 'Unexpected product owns the reproduction ProductCode; refusing cleanup.' }
    return $true
}
function RemoveProduct([string]$name) {
    $path = Join-Path $OutputDirectory $name
    $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList ('/x "{0}" /qn /norestart /L*V! "{1}"' -f $productCode,$path) -PassThru
    if (-not $p.WaitForExit(120000)) { throw "Timed out removing the reproduction; msiexec PID $($p.Id)." }
    $p.WaitForExit(); Log "Uninstall exit=$($p.ExitCode) log=$name"
    if ($p.ExitCode -notin 0,1605,3010) { throw "Reproduction uninstall failed with code $($p.ExitCode); see $path" }
    return $p.ExitCode
}
try {
    $props = ReadIdentity
    if ($props.ProductCode -ne $productCode -or $props.ProductName -ne $productName) { throw 'The MSI is not the expected standalone reproduction package.' }
    $packageValidated = $true
    Log "Start input=$InputMode ui=$UI"
    $versionFiles = foreach ($name in 'msi.dll','msihnd.dll','user32.dll','win32u.dll') {
        $file = Get-Item -LiteralPath (Join-Path "$env:SystemRoot\System32" $name)
        [ordered]@{name=$name;fileVersion=$file.VersionInfo.FileVersion;sha256=(Get-FileHash $file.FullName -Algorithm SHA256).Hash}
    }
    $windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $environment = [ordered]@{build=$windows.CurrentBuildNumber;ubr=$windows.UBR;displayVersion=$windows.DisplayVersion;sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;is64BitProcess=[Environment]::Is64BitProcess;dlls=@($versionFiles);helperSha256=(Get-FileHash $nativePath -Algorithm SHA256).Hash}
    $environment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'environment.json') -Encoding UTF8
    if (Installed) { [void](RemoveProduct 'prepare-uninstall.log') }
    if (Get-Process -Name 'msi-menu-repro-sleeper' -ErrorAction SilentlyContinue) { throw 'A reproduction sleeper is already running; wait for it to exit before starting another run.' }
    $sleeper = Start-Process -FilePath $sleeperPath -PassThru
    Log "Sleeper pid=$($sleeper.Id)"
    $passive = if ($UI -eq 'Passive') { ' /passive' } else { '' }
    $msi = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList ('/i "{0}" /norestart /L*V! "{1}"{2}' -f $MsiPath,$logPath,$passive) -PassThru
    $result['msiPid'] = $msi.Id
    Log "MSI pid=$($msi.Id)"
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $lastEnter = [DateTime]::MinValue
    $executeSeen = $false
    $boundary = $false
    $className = if ($UI -eq 'Full') { 'MsiDialogCloseClass' } else { '#32770' }
    while (-not $msi.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $text = ReadLog
        if ($text -match 'Doing action: ExecuteAction') { $executeSeen = $true }
        if ($text -match 'Entrypoint: WixCloseApplications(?:\r|\n|$)') { $boundary=$true; break }
        if ($UI -eq 'Full' -and -not $executeSeen -and ([DateTime]::UtcNow-$lastEnter).TotalSeconds -gt 1.2) {
            $dialog = [MsiMenuRepro.Native]::FindDialog([uint32]$msi.Id,$className)
            if ($dialog -ne [IntPtr]::Zero -and [MsiMenuRepro.Native]::TryForeground($dialog)) {
                Start-Sleep -Milliseconds 100
                CheckNavigationInput ([MsiMenuRepro.Native]::PressKey($dialog,0x0D))
                $lastEnter=[DateTime]::UtcNow; Log 'Wizard Enter'
            }
        }
        Start-Sleep -Milliseconds 50
    }
    if (-not $boundary) { throw 'The close-action boundary was not reached; input was not injected.' }
    Log 'Close action started; waiting 1500ms inside its 10-second timeout'
    Start-Sleep -Milliseconds 1500
    $dialog = [MsiMenuRepro.Native]::FindDialog([uint32]$msi.Id,$className)
    if ($dialog -eq [IntPtr]::Zero) { throw 'Expected progress dialog was not found; input was not injected.' }
    if (-not [MsiMenuRepro.Native]::TryForeground($dialog)) { throw 'Could not foreground the progress dialog; input was not injected.' }
    Start-Sleep -Milliseconds 150
    $snapshot = Snapshot $dialog
    if (-not $snapshot.valid -or -not $snapshot.isForeground -or $snapshot.pid -ne $msi.Id) { throw 'Foreground progress-window validation failed.' }
    if ($snapshot.flags -band 4) { throw 'The progress window is already in menu mode before the test input.' }
    $result.windowAtInjection=$snapshot
    $result.keyboardBefore=[MsiMenuRepro.Native]::KeyboardState()
    if (@($result.keyboardBefore.Keys | Where-Object Down).Count) { throw 'A modifier or Delete key is down. Release keys and start a fresh run; the runner will not reset keyboard state before replay.' }
    Log ('Before input: ' + ($snapshot | ConvertTo-Json -Compress))
    $result.injectionAt=[DateTime]::UtcNow.ToString('o')
    switch ($InputMode) {
        'TightVncReset' { $sent=[MsiMenuRepro.Native]::ResetModifiers($dialog); $result.injection=$sent; CheckInput $sent }
        'AltTap' { $sent=[MsiMenuRepro.Native]::AltTap($dialog); $result.injection=$sent; CheckInput $sent }
        'None' { Log 'No input injected (control)' }
    }
    Log ('Input result: ' + ($result.injection | ConvertTo-Json -Depth 5 -Compress))
    # Observe past the real close timeout before calling a quiet log a stall.
    $until=[DateTime]::UtcNow.AddSeconds(10+$ObserveSeconds)
    $lastFlags=-1
    while ([DateTime]::UtcNow -lt $until -and -not $msi.HasExited) {
        $text=ReadLog
        if ($text -match $completionPattern) { $result.completedBeforeRelease=$true; break }
        $snapshot=Snapshot $dialog
        if (-not $snapshot.valid -or -not $snapshot.isForeground -or $snapshot.pid -ne $msi.Id -or $snapshot.tid -ne $result.windowAtInjection.tid -or $snapshot.className -ne $className) {
            # The success dialog can replace the progress dialog during this sample.
            $text=ReadLog
            if ($text -match $completionPattern -or $msi.HasExited) { break }
            throw 'The progress window changed or lost foreground during observation; the run is invalid.'
        }
        if ($snapshot.flags -band 4) { $result.menuSeen=$true }
        if ($snapshot.flags -ne $lastFlags) { Log ('GUI state: ' + ($snapshot | ConvertTo-Json -Compress)); $lastFlags=$snapshot.flags }
        Start-Sleep -Milliseconds 20
    }
    if ($msi.HasExited) { $msi.WaitForExit(); $result.completedBeforeRelease=($msi.ExitCode -eq 0 -or $msi.ExitCode -eq 3010) }
    $before=ReadLog
    if ($before -match $completionPattern) { $result.completedBeforeRelease=$true }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'before-release.log'),$before,(New-Object Text.UTF8Encoding($false)))
    $snapshot=Snapshot $dialog
    $result.menuModeAtObservationEnd=($snapshot.valid -and $snapshot.pid -eq $msi.Id -and $snapshot.tid -eq $result.windowAtInjection.tid -and [bool]($snapshot.flags -band 4))
    $result.preReleaseLogQuietSeconds=([DateTime]::UtcNow-(Get-Item -LiteralPath $logPath).LastWriteTimeUtc).TotalSeconds
    Log ('Observation ended: ' + ([ordered]@{menuMode=$result.menuModeAtObservationEnd;completed=$result.completedBeforeRelease;quietSeconds=$result.preReleaseLogQuietSeconds} | ConvertTo-Json -Compress))
    $stalled=$result.menuModeAtObservationEnd -and -not $result.completedBeforeRelease -and $result.preReleaseLogQuietSeconds -ge 10
    if ($stalled) { $result.verdict='StallNotReleased' }
    if ($result.menuModeAtObservationEnd) {
        if (-not $snapshot.isForeground) { throw 'Foreground changed before release; refusing to send Esc.' }
        $result['releaseAt']=[DateTime]::UtcNow.ToString('o')
        $result.releaseInput=[MsiMenuRepro.Native]::PressKey($dialog,0x1B)
        $result.releaseSent=($result.releaseInput.Injected -gt 0)
        CheckInput $result.releaseInput
        Log 'Sent one Esc after observation'
        $resumeUntil=[DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $resumeUntil) {
            $after=ReadLog
            $newText=if ($after.Length -gt $before.Length) { $after.Substring($before.Length) } else { '' }
            if ($newText -match 'Action ended [^\r\n]*Wix4CloseApplications_X64\. Return value 1\.' -or $newText -match $completionPattern) { $result.progressedAfterRelease=$true; break }
            Start-Sleep -Milliseconds 50
        }
    }
    $finishUntil=[DateTime]::UtcNow.AddSeconds(60)
    while (-not $msi.HasExited -and [DateTime]::UtcNow -lt $finishUntil) {
        $text=ReadLog
        if ($UI -eq 'Full' -and $text -match $completionPattern) {
            $finish=[MsiMenuRepro.Native]::FindDialog([uint32]$msi.Id,$className)
            if ($finish -ne [IntPtr]::Zero -and [MsiMenuRepro.Native]::TryForeground($finish)) {
                Start-Sleep -Milliseconds 100; CheckNavigationInput ([MsiMenuRepro.Native]::PressKey($finish,0x0D)); Log 'Finish Enter'
            }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $msi.HasExited) { throw "Installer is still running (PID $($msi.Id)); inspect its dialog and log." }
    $msi.WaitForExit(); $result.installerExitCode=$msi.ExitCode
    if ($msi.ExitCode -notin 0,3010) { throw "Installer exited $($msi.ExitCode); this is not a successful reproduction/control run." }
    if ($stalled -and $result.progressedAfterRelease) { $result.verdict='Reproduced' }
    elseif ($stalled) { $result.verdict='StallNotReleased' }
    elseif ($result.menuSeen) { $result.verdict='MenuModeWithoutStall' }
    elseif ($InputMode -eq 'None') { $result.verdict='ControlCompleted' }
    else { $result.verdict='TriggerNotReproduced' }
} catch {
    $result.error=$_.Exception.Message
    Log ('ERROR: ' + $result.error)
} finally {
    if ($sleeper -and -not $sleeper.HasExited) { try { $sleeper.Kill(); [void]$sleeper.WaitForExit(5000); Log 'Stopped own sleeper PID' } catch { if (-not $sleeper.HasExited) { $result.cleanupError=$_.Exception.Message; Log ('Sleeper cleanup: '+$result.cleanupError) } } }
    try {
        if ($packageValidated -and -not $KeepInstalled -and ($null -eq $msi -or $msi.HasExited) -and (Installed)) { $result.cleanupExitCode=RemoveProduct 'cleanup.log' }
    } catch { $result.cleanupError=$_.Exception.Message; Log ('CLEANUP ERROR: '+$result.cleanupError) }
    if ($msi -and $msi.HasExited -and $null -eq $result.installerExitCode) { $msi.WaitForExit(); $result.installerExitCode=$msi.ExitCode }
    $result['finishedAt']=[DateTime]::UtcNow.ToString('o')
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
Write-Host ("{0}: {1}" -f $result.verdict,$OutputDirectory)
if ($result.error) { Write-Warning $result.error }
if ($result.cleanupError) { Write-Warning $result.cleanupError }
if ($result.verdict -in 'InvalidTest','StallNotReleased' -or $result.error -or $result.cleanupError) { exit 2 }
exit 0
