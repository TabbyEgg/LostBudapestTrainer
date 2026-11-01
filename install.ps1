# Lost Budapest Noclip installer. Windows PowerShell 5.1 or newer.
[CmdletBinding()]
param([string]$GameDirectory, [switch]$Update)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Product = 'LostBudapestNoclip'
$ReceiptName = 'LostBudapestNoclip.install.json'
$ExpectedExe = 'EltuntBP-Win64-Shipping.exe'
$ExpectedGameSha256 = '2e5f4d5b66da873a488287b580c2ba3dd91ed892727cfd71ecbd610d6a08f284'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Resolve-Child([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '(^[\\/]|:|[\x00-\x1f<>"|?*]|(^|[\\/])\.\.?([\\/]|$))') {
        throw "Unsafe relative path: $Relative"
    }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $path = [IO.Path]::GetFullPath([IO.Path]::Combine($rootPath, $Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path leaves the installation directory: $Relative"
    }
    $part = $path
    while ($part -and $part.Length -ge $rootPath.Length) {
        if (Test-Path -LiteralPath $part) {
            if (((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "A linked/junction path needs a direct installation path: $part"
            }
        }
        if ($part -eq $rootPath) { break }
        $part = [IO.Path]::GetDirectoryName($part)
    }
    return $path
}
function Test-AllowedTarget([string]$Relative) {
    $name = $Relative.Replace('\', '/')
    return $name -in @('UE4SS.dll', 'dwmapi.dll', 'UE4SS-settings.ini', 'Mods/mods.txt') -or
        $name.StartsWith('Mods/LostBudapestNoclip/', [StringComparison]::OrdinalIgnoreCase) -or
        $name.StartsWith('Mods/shared/', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-GameClosed {
    if (@(Get-Process -Name 'EltuntBP-Win64-Shipping' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Fully quit Lost Budapest before installing or uninstalling the trainer.'
    }
}
function Select-GameFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Lost Budapest game folder, or its Binaries\Win64 folder.'
    $dialog.ShowNewFolderButton = $false
    try {
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'No game folder was selected.' }
        return $dialog.SelectedPath
    } finally { $dialog.Dispose() }
}
function Find-GameFolder([string]$Folder) {
    $root = [IO.Path]::GetFullPath($Folder)
    foreach ($relative in @('', 'Eltunt_Budapest3/Binaries/Win64', 'Binaries/Win64')) {
        $candidate = if ($relative) { [IO.Path]::Combine($root, $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)) } else { $root }
        if (Test-Path -LiteralPath ([IO.Path]::Combine($candidate, $ExpectedExe)) -PathType Leaf) { return $candidate }
    }
    throw "Could not find $ExpectedExe. Select the game root or Eltunt_Budapest3\Binaries\Win64."
}
function Set-IniValue([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($Text -split '\r?\n')) { $lines.Add($line) }
    $inside = $false; $seenSection = $false; $changed = $false; $insertAt = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[([^]]+)\]\s*(?:[;#].*)?$') {
            if ($inside -and $insertAt -lt 0) { $insertAt = $i }
            $inside = $Matches[1] -ieq $Section
            if ($inside) { $seenSection = $true }
            continue
        }
        if ($inside -and $lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = "$Key = $Value"; $changed = $true
        }
    }
    if (-not $changed) {
        if ($seenSection) {
            if ($insertAt -lt 0) { $lines.Add("$Key = $Value") } else { $lines.Insert($insertAt, "$Key = $Value") }
        } else {
            if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
            $lines.Add("[$Section]"); $lines.Add("$Key = $Value")
        }
    }
    return ([string]::Join($newline, $lines.ToArray())).TrimEnd([char[]]"`r`n") + $newline
}
function Merge-ModEntry([string]$Text) {
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object 'System.Collections.Generic.List[string]'; $found = $false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*LostBudapestNoclip\s*:') {
            if (-not $found) { $lines.Add('LostBudapestNoclip : 1'); $found = $true }
        } else { $lines.Add($line) }
    }
    if (-not $found) { $lines.Add('LostBudapestNoclip : 1') }
    return ([string]::Join($newline, $lines.ToArray())).TrimEnd([char[]]"`r`n") + $newline
}
function Write-BytesAtomic([string]$Path, [byte[]]$Bytes) {
    $temp = $Path + '.lbn-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

try {
    Assert-GameClosed
    if (-not $GameDirectory) { $GameDirectory = Select-GameFolder }
    $target = Find-GameFolder $GameDirectory
    $game = Resolve-Child $target $ExpectedExe
    if ((Get-Sha256 $game) -ne $ExpectedGameSha256) {
        throw 'This package targets the supplied demo build. Its EXE hash differs; no files were changed.'
    }
    $receiptPath = Resolve-Child $target $ReceiptName
    $prior = $null; $priorFiles = @{}
    if (Test-Path -LiteralPath $receiptPath) {
        if (-not $Update) { throw 'An installation receipt already exists. Run Update.cmd to upgrade this installation.' }
        if ((Get-Item -LiteralPath $receiptPath).Length -gt 1048576) { throw 'Installation receipt is oversized.' }
        $prior = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        if ($prior.format -ne 1 -or $prior.product -ne $Product -or $prior.gameExe -ne $ExpectedExe -or
            $prior.backupDirectory -notmatch '^LostBudapestNoclip\.backup-[a-fA-F0-9]{32}$') { throw 'Invalid installation receipt.' }
        foreach ($record in @($prior.files)) {
            $null = Resolve-Child $target ([string]$record.path)
            if (-not (Test-AllowedTarget $record.path) -or $priorFiles.ContainsKey($record.path) -or
                $record.installedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid file entry in installation receipt.' }
            if ($record.beforeExisted) {
                if ($record.backupPath -ne ($prior.backupDirectory + '/' + $record.path) -or $record.beforeSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid backup entry.' }
                $backup = Resolve-Child $target $record.backupPath
                if (-not [IO.File]::Exists($backup) -or (Get-Sha256 $backup) -ine $record.beforeSha256) { throw 'Original backup is missing or changed; update stopped.' }
            }
            $priorFiles[$record.path] = $record
        }
    }
    $runtime = [IO.Path]::Combine($PSScriptRoot, 'Runtime')
    $manifestPath = [IO.Path]::Combine($PSScriptRoot, 'payload-manifest.json')
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.format -ne 1) { throw 'Unsupported payload manifest.' }
    $payload = @{}; $known = @{}
    foreach ($record in @($manifest.files)) {
        $relative = [string]$record.path
        $source = Resolve-Child $runtime $relative
        if (-not (Test-AllowedTarget $relative) -or $known.ContainsKey($relative)) { throw "Unexpected or duplicate payload path: $relative" }
        $known[$relative] = $true
        if (-not [IO.File]::Exists($source) -or [long]$record.size -ne (Get-Item -LiteralPath $source).Length -or
            [string]$record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-Sha256 $source) -ine [string]$record.sha256) {
            throw "Payload integrity check failed: $relative"
        }
        $payload[$relative] = [IO.File]::ReadAllBytes($source)
    }
    foreach ($required in @('UE4SS.dll', 'dwmapi.dll', 'UE4SS-settings.ini',
        'Mods/LostBudapestNoclip/Scripts/main.lua', 'Mods/LostBudapestNoclip/Scripts/controller.lua',
        'Mods/LostBudapestNoclip/Scripts/adapter.lua', 'Mods/LostBudapestNoclip/Scripts/config.lua',
        'Mods/LostBudapestNoclip/Scripts/protection.lua', 'Mods/LostBudapestNoclip/Scripts/vehicles.lua',
        'Mods/LostBudapestNoclip/Scripts/vehicle_engine.lua', 'Mods/LostBudapestNoclip/Scripts/native_spawn.lua',
        'Mods/LostBudapestNoclip/Scripts/menu.lua', 'Mods/LostBudapestNoclip/Scripts/menu_engine.lua',
        'Mods/LostBudapestNoclip/Scripts/player_vehicle.lua')) {
        if (-not $payload.ContainsKey($required)) { throw "Required payload file is missing: $required" }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $runtime -File -Recurse -Force)) {
        $relative = $file.FullName.Substring($runtime.Length).TrimStart([char[]]'\/').Replace('\', '/')
        if (-not $known.ContainsKey($relative)) { throw "Unmanifested payload file: $relative" }
    }
    $settingsPath = Resolve-Child $target 'UE4SS-settings.ini'
    $existingSettings = [IO.File]::Exists($settingsPath)
    $settings = if ($existingSettings) { [IO.File]::ReadAllText($settingsPath) } else { $Utf8.GetString($payload['UE4SS-settings.ini']) }
    $insideOverrides = $false
    foreach ($line in ($settings -split '\r?\n')) {
        if ($line -match '^\s*\[([^]]+)\]\s*(?:[;#].*)?$') { $insideOverrides = $Matches[1] -ieq 'Overrides'; continue }
        if ($insideOverrides -and $line -match '^\s*ModsFolderPath\s*=\s*(.*)$') {
            $customMods = ($Matches[1] -split '[;#]', 2)[0].Trim().Trim([char[]]'"''')
            if ($customMods) { throw 'An existing custom ModsFolderPath is configured. No files were changed; use an installation with the standard local Mods folder.' }
        }
    }
    $settings = Set-IniValue $settings 'EngineVersionOverride' 'MajorVersion' '4'
    $settings = Set-IniValue $settings 'EngineVersionOverride' 'MinorVersion' '27'
    $settings = Set-IniValue $settings 'General' 'EnableHotReloadSystem' '0'
    if (-not $existingSettings) {
        foreach ($key in @('ConsoleEnabled', 'GuiConsoleEnabled', 'GuiConsoleVisible')) { $settings = Set-IniValue $settings 'Debug' $key '0' }
    }
    $payload['UE4SS-settings.ini'] = $Utf8.GetBytes($settings)
    $modsPath = Resolve-Child $target 'Mods/mods.txt'
    $mods = if ([IO.File]::Exists($modsPath)) { [IO.File]::ReadAllText($modsPath) } else { '' }
    $payload['Mods/mods.txt'] = $Utf8.GetBytes((Merge-ModEntry $mods))
    $backupRelative = if ($prior) { $prior.backupDirectory } else { 'LostBudapestNoclip.backup-' + [Guid]::NewGuid().ToString('N') }
    # Preserve edited trainer configuration, without claiming ownership of edits.
    $configRelative = 'Mods/LostBudapestNoclip/Scripts/config.lua'
    if ($priorFiles.ContainsKey($configRelative)) {
        $configPath = Resolve-Child $target $configRelative
        if ([IO.File]::Exists($configPath) -and (Get-Sha256 $configPath) -ne $priorFiles[$configRelative].installedSha256) {
            $payload[$configRelative] = [IO.File]::ReadAllBytes($configPath)
            Write-Host 'Preserved your edited trainer configuration.'
        }
    }
    $plans = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relative in @($payload.Keys | Sort-Object)) {
        $path = Resolve-Child $target $relative
        $bytes = [byte[]]$payload[$relative]; $newHash = Get-BytesSha256 $bytes
        $exists = [IO.File]::Exists($path); $oldHash = if ($exists) { Get-Sha256 $path } else { $null }
        if ($exists -and $oldHash -eq $newHash) { continue }
        if ($exists -and ($relative -in @('dwmapi.dll', 'UE4SS.dll') -or $relative.StartsWith('Mods/shared/', [StringComparison]::OrdinalIgnoreCase)) -and
            -not ($priorFiles.ContainsKey($relative) -and $oldHash -eq $priorFiles[$relative].installedSha256)) {
            throw "A different loader/shared file already exists: $relative. No files were changed; keep your existing loader installation separate."
        }
        if ($priorFiles.ContainsKey($relative) -and $exists -and $oldHash -ne $priorFiles[$relative].installedSha256) {
            # Recover a trainer-disabled mod entry only when merging it back on
            # reproduces the exact bytes previously owned by this installation.
            # Other mod-list edits still stop the update and remain untouched.
            $restoresOwnedModList = $relative -eq 'Mods/mods.txt' -and $newHash -eq $priorFiles[$relative].installedSha256
            if (-not $restoresOwnedModList) {
                throw "An installed file was edited: $relative. Update stopped without overwriting it."
            }
        }
        $backup = if ($exists) { $backupRelative + '/' + $relative } else { $null }
        $plans.Add([pscustomobject]@{ path = $relative; beforeExisted = $exists; beforeSha256 = $oldHash; backupPath = $backup; installedSha256 = $newHash })
    }
    # All payload/build/conflict checks finish before the first game-directory write.
    Assert-GameClosed
    $written = New-Object 'System.Collections.Generic.List[object]'
    $created = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($plan in $plans) {
            Assert-GameClosed
            $path = Resolve-Child $target $plan.path
            $parent = [IO.Path]::GetDirectoryName($path)
            $missing = New-Object 'System.Collections.Generic.List[string]'
            while ($parent -and $parent -ne $target -and -not [IO.Directory]::Exists($parent)) {
                $missing.Add($parent); $parent = [IO.Path]::GetDirectoryName($parent)
            }
            for ($i = $missing.Count - 1; $i -ge 0; $i--) {
                [IO.Directory]::CreateDirectory($missing[$i]) | Out-Null
                $created.Add($missing[$i].Substring($target.Length).TrimStart([char[]]'\/').Replace('\', '/'))
            }
            if ($plan.beforeExisted) {
                if ((Get-Sha256 $path) -ne $plan.beforeSha256) { throw "File changed during installation: $($plan.path)" }
                $plan | Add-Member -NotePropertyName rollbackBytes -NotePropertyValue ([IO.File]::ReadAllBytes($path))
                if (-not $priorFiles.ContainsKey($plan.path)) {
                    $backup = Resolve-Child $target $plan.backupPath
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
                    if ([IO.File]::Exists($backup)) {
                        if ((Get-Sha256 $backup) -ne $plan.beforeSha256) { throw 'An existing backup differs; update stopped.' }
                    } else { [IO.File]::Copy($path, $backup, $false) }
                }
            }
            $written.Add($plan)
            Write-BytesAtomic $path ([byte[]]$payload[$plan.path])
        }
        $finalFiles = @{}
        foreach ($key in $priorFiles.Keys) { $finalFiles[$key] = $priorFiles[$key] }
        foreach ($plan in $plans) {
            if ($priorFiles.ContainsKey($plan.path)) {
                $old = $priorFiles[$plan.path]
                $finalFiles[$plan.path] = [pscustomobject]@{path=$plan.path;beforeExisted=$old.beforeExisted;beforeSha256=$old.beforeSha256;backupPath=$old.backupPath;installedSha256=$plan.installedSha256}
            } else {
                $finalFiles[$plan.path] = [pscustomobject]@{path=$plan.path;beforeExisted=$plan.beforeExisted;beforeSha256=$plan.beforeSha256;backupPath=$plan.backupPath;installedSha256=$plan.installedSha256}
            }
        }
        $allCreated = @($created.ToArray())
        if ($prior) { $allCreated = @(@($prior.createdDirectories) + $allCreated | Select-Object -Unique) }
        $receipt = [ordered]@{ format = 1; product = $Product; gameExe = $ExpectedExe; gameSha256 = $ExpectedGameSha256;
            installedAtUtc = [DateTime]::UtcNow.ToString('o'); backupDirectory = $backupRelative;
            files = @($finalFiles.Values); createdDirectories = $allCreated }
        Write-BytesAtomic $receiptPath ($Utf8.GetBytes(($receipt | ConvertTo-Json -Depth 6)))
    } catch {
        $installError = $_
        for ($i = $written.Count - 1; $i -ge 0; $i--) {
            $plan = $written[$i]; $path = Resolve-Child $target $plan.path
            try {
                if ([IO.File]::Exists($path) -and (Get-Sha256 $path) -eq $plan.installedSha256) {
                    if ($plan.beforeExisted) { Write-BytesAtomic $path ([byte[]]$plan.rollbackBytes) }
                    else { [IO.File]::Delete($path) }
                }
            } catch { Write-Warning "Rollback needs manual attention for $($plan.path): $($_.Exception.Message)" }
        }
        for ($i = $created.Count - 1; $i -ge 0; $i--) {
            $path = Resolve-Child $target $created[$i]
            if ([IO.Directory]::Exists($path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { [IO.Directory]::Delete($path) }
        }
        throw $installError
    }
    Write-Host 'Lost Budapest Noclip installed/updated. Start the game normally; F6 toggles noclip.' -ForegroundColor Green
    Write-Host "Receipt and original-file backups are in: $target"
    exit 0
} catch {
    Write-Host ('Installation stopped: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
