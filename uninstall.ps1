# Removes only this installer's unchanged files; edited files are left alone.
[CmdletBinding()]
param([string]$GameDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$ReceiptName = 'LostBudapestNoclip.install.json'
$ExpectedExe = 'EltuntBP-Win64-Shipping.exe'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Resolve-Child([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '(^[\\/]|:|[\x00-\x1f<>"|?*]|(^|[\\/])\.\.?([\\/]|$))') {
        throw "Unsafe relative path in receipt: $Relative"
    }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $path = [IO.Path]::GetFullPath([IO.Path]::Combine($rootPath, $Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Receipt path leaves game directory: $Relative" }
    $part = $path
    while ($part -and $part.Length -ge $rootPath.Length) {
        if (Test-Path -LiteralPath $part) {
            if (((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Use a direct path, not a linked/junction path: $part" }
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
        throw 'Fully quit Lost Budapest before uninstalling the trainer.'
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
        if (Test-Path -LiteralPath ([IO.Path]::Combine($candidate, $ReceiptName)) -PathType Leaf) { return $candidate }
    }
    throw 'No Lost Budapest Noclip installation receipt was found in the selected folder.'
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
    $receiptPath = Resolve-Child $target $ReceiptName
    if ((Get-Item -LiteralPath $receiptPath).Length -gt 1048576) { throw 'The installation receipt is unexpectedly large.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.format -ne 1 -or $receipt.product -ne 'LostBudapestNoclip' -or $receipt.gameExe -ne $ExpectedExe -or
        $receipt.backupDirectory -notmatch '^LostBudapestNoclip\.backup-[a-fA-F0-9]{32}$') { throw 'Invalid installation receipt; no files were changed.' }
    $known = @{}
    foreach ($record in @($receipt.files)) {
        $relative = [string]$record.path
        $null = Resolve-Child $target $relative
        if (-not (Test-AllowedTarget $relative) -or $known.ContainsKey($relative) -or
            [string]$record.installedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw "Invalid file entry in installation receipt: $relative" }
        $known[$relative] = $true
        if ($record.beforeExisted) {
            $expectedBackup = $receipt.backupDirectory + '/' + $relative
            if ($record.backupPath -ne $expectedBackup -or [string]$record.beforeSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw "Invalid original-file backup entry: $relative" }
            $null = Resolve-Child $target ([string]$record.backupPath)
        }
    }
    foreach ($relative in @($receipt.createdDirectories)) {
        $name = [string]$relative
        $null = Resolve-Child $target $name
        if ($name -notin @('Mods', 'Mods/shared', 'Mods/LostBudapestNoclip') -and
            -not $name.StartsWith('Mods/shared/', [StringComparison]::OrdinalIgnoreCase) -and
            -not $name.StartsWith('Mods/LostBudapestNoclip/', [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid created-directory entry: $name" }
    }
    $foreignMods = $false
    $modsDirectory = Resolve-Child $target 'Mods'
    if ([IO.Directory]::Exists($modsDirectory)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $modsDirectory -Directory -Force)) {
            if ($directory.Name -notin @('LostBudapestNoclip', 'shared')) { $foreignMods = $true }
        }
    }
    $remaining = New-Object 'System.Collections.Generic.List[object]'
    $cleanups = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in @($receipt.files)) {
        Assert-GameClosed
        $path = Resolve-Child $target ([string]$record.path)
        if (-not [IO.File]::Exists($path) -and -not $record.beforeExisted) { $cleanups.Add($record); continue }
        if ($record.beforeExisted -and [IO.File]::Exists($path) -and (Get-Sha256 $path) -ieq [string]$record.beforeSha256) {
            $cleanups.Add($record); continue # A prior interrupted uninstall already restored these bytes.
        }
        if (-not [IO.File]::Exists($path) -or (Get-Sha256 $path) -ine [string]$record.installedSha256) {
            Write-Warning "Kept your changed/missing file: $($record.path)"
            $remaining.Add($record); continue
        }
        if ($foreignMods -and -not $record.beforeExisted -and $record.path -in @('UE4SS.dll', 'dwmapi.dll', 'UE4SS-settings.ini')) {
            Write-Host "Kept shared loader/configuration for other mods: $($record.path)"
            $cleanups.Add($record); continue
        }
        if ($record.beforeExisted) {
            $backup = Resolve-Child $target ([string]$record.backupPath)
            if (-not [IO.File]::Exists($backup) -or (Get-Sha256 $backup) -ine [string]$record.beforeSha256) {
                Write-Warning "Original backup is missing or changed; kept $($record.path)."
                $remaining.Add($record); continue
            }
            Write-BytesAtomic $path ([IO.File]::ReadAllBytes($backup))
        } else { [IO.File]::Delete($path) }
        $cleanups.Add($record)
    }
    foreach ($record in $cleanups) {
        if ($record.beforeExisted) {
            $backup = Resolve-Child $target ([string]$record.backupPath)
            if ([IO.File]::Exists($backup) -and (Get-Sha256 $backup) -ieq [string]$record.beforeSha256) { [IO.File]::Delete($backup) }
        }
    }
    foreach ($relative in @($receipt.createdDirectories | Sort-Object -Property Length -Descending)) {
        $path = Resolve-Child $target ([string]$relative)
        if ([IO.Directory]::Exists($path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { [IO.Directory]::Delete($path) }
    }
    $backupRoot = Resolve-Child $target ([string]$receipt.backupDirectory)
    if ([IO.Directory]::Exists($backupRoot)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Recurse -Force | Sort-Object -Property FullName -Descending)) {
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and @(Get-ChildItem -LiteralPath $directory.FullName -Force).Count -eq 0) { [IO.Directory]::Delete($directory.FullName) }
        }
        if (@(Get-ChildItem -LiteralPath $backupRoot -Force).Count -eq 0) { [IO.Directory]::Delete($backupRoot) }
    }
    if ($remaining.Count -gt 0) {
        $receipt.files = @($remaining.ToArray())
        Write-BytesAtomic $receiptPath ($Utf8.GetBytes(($receipt | ConvertTo-Json -Depth 6)))
        Write-Warning 'Uninstall preserved edited files. The receipt and any original backups remain for those files.'
        Write-Host "Review: $receiptPath"
        exit 2
    }
    [IO.File]::Delete($receiptPath)
    Write-Host 'Lost Budapest Noclip uninstalled. Pre-existing unchanged files were restored; other mods were preserved.' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ('Uninstall stopped: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
