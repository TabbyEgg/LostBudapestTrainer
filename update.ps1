# Fetch the official latest trainer release and upgrade the selected installation.
[CmdletBinding()]
param([string]$GameDirectory, [string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$temporary = $null
try {
    if (@(Get-Process -Name 'EltuntBP-Win64-Shipping' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Fully quit Lost Budapest before updating.'
    }
    if (-not $PackageDirectory) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $headers = @{'User-Agent'='LostBudapestTrainer-Updater';'Accept'='application/vnd.github+json'}
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/TabbyEgg/LostBudapestTrainer/releases/latest' -Headers $headers
        $assets = @($release.assets | Where-Object { $_.name -match '^LostBudapest-Noclip-[0-9]+\.[0-9]+\.[0-9]+\.zip$' })
        if ($assets.Count -ne 1) { throw 'The latest release has no unambiguous trainer ZIP.' }
        $asset = $assets[0]
        if ($asset.browser_download_url -notmatch '^https://github\.com/TabbyEgg/LostBudapestTrainer/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/LostBudapest-Noclip-[0-9]+\.[0-9]+\.[0-9]+\.zip$' -or
            $asset.size -le 0 -or $asset.size -gt 33554432 -or
            $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Release asset metadata is invalid; no game files were changed.' }
        $expected = $Matches[1].ToLowerInvariant()
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('LostBudapest-update-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($temporary) | Out-Null
        $zip = Join-Path $temporary 'release.zip'
        Write-Host ('Downloading ' + $release.tag_name + ' from TabbyEgg/LostBudapestTrainer...')
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -UseBasicParsing -OutFile $zip
        if ((Get-Item -LiteralPath $zip).Length -ne $asset.size -or
            (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Release download hash mismatch; installation unchanged.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        $PackageDirectory = Join-Path $temporary 'package'
        [IO.Directory]::CreateDirectory($PackageDirectory) | Out-Null
        try {
            if ($archive.Entries.Count -gt 2000) { throw 'Unexpectedly large archive entry count.' }
            $total = 0L
            foreach ($entry in $archive.Entries) {
                $name = $entry.FullName.Replace('\','/')
                if ($name -match '(^/|:|[\x00-\x1f]|(^|/)\.\.?(/|$))' -or
                    (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'Unsafe archive path.' }
                $total += $entry.Length
                if ($total -gt 104857600) { throw 'Archive expands beyond the trainer size limit.' }
            }
        } finally { $archive.Dispose() }
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$PackageDirectory)
    }
    $installer = Join-Path ([IO.Path]::GetFullPath($PackageDirectory)) 'install.ps1'
    if (-not [IO.File]::Exists($installer)) { throw 'The trainer installer is missing.' }
    $engine = (Get-Process -Id $PID).Path
    $arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-Update')
    if ($GameDirectory) { $arguments += @('-GameDirectory',$GameDirectory) }
    & $engine @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Update did not complete. Review the installer message; the prior installation was retained or rolled back.' }
    Write-Host 'Update complete. Start the game normally.' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ('Update stopped: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($temporary -and [IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
