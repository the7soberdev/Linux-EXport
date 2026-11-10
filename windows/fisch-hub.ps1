#requires -version 5.1
<#
    fisch-hub.ps1 - install, sync, verify and watch the Fisch Hub on Windows.

    No admin rights, no downloads, no service installs. It copies two files it
    already ships with into the folders your executor reads at injection time.

        .\fisch-hub.ps1              install + sync + summary
        .\fisch-hub.ps1 -Status      what is installed and where
        .\fisch-hub.ps1 -Verify      hash every installed copy against the source
        .\fisch-hub.ps1 -Sync        copy again into every folder found now
        .\fisch-hub.ps1 -Watch       keep adopting executor folders as they appear
        .\fisch-hub.ps1 -Uninstall   remove only the files this script wrote
        .\fisch-hub.ps1 -Launch      start the Roblox player, if one is installed
        .\fisch-hub.ps1 -SearchPath 'D:\stuff'   extra roots to scan

    Everything it writes is recorded in manifest.json together with its SHA-256.
    Uninstall only deletes files whose hash still matches, so nothing of yours
    can be removed by accident.
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Verify,
    [switch]$Sync,
    [switch]$Watch,
    [switch]$Uninstall,
    [switch]$Launch,
    [string[]]$SearchPath = @(),
    [int]$IntervalSeconds = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:InstallDir = Join-Path $env:LOCALAPPDATA 'FischHub'
$script:ManifestPath = Join-Path $script:InstallDir 'manifest.json'

function Write-Say  { param([string]$Text) Write-Host "  $Text" }
function Write-Ok   { param([string]$Text) Write-Host "  ok   $Text" -ForegroundColor Green }
function Write-Note { param([string]$Text) Write-Host "  !!   $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "  xx   $Text" -ForegroundColor Red }
function Write-Step { param([string]$Text) Write-Host ""; Write-Host $Text -ForegroundColor White }

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FirstExisting {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Get-SourceBundle {
    $root = $PSScriptRoot
    $parent = Split-Path -Parent $root
    $candidates = @(
        (Join-Path $root 'FischHub.lua'),
        (Join-Path $root 'dist\FischHub.lua'),
        (Join-Path $parent 'dist\FischHub.lua'),
        (Join-Path $parent 'FischHub.lua')
    )
    return Get-FirstExisting $candidates
}

function Get-SourceLoader {
    $root = $PSScriptRoot
    $parent = Split-Path -Parent $root
    $candidates = @(
        (Join-Path $root 'loader.lua'),
        (Join-Path $root 'autoload\loader.lua'),
        (Join-Path $parent 'autoload\loader.lua')
    )
    return Get-FirstExisting $candidates
}

function Find-AutoexecDirs {
    param([string[]]$Bases, [int]$MaxDepth = 3)

    $names = @('autoexec', 'autoload', 'auto_exec', 'autoexecs')
    $skip = @('node_modules', '.git', 'cache', 'temp', 'tmp', 'packages',
              'microsoft', 'windowsapps', 'crashdumps', 'appdata', 'onedrivetemp')

    $found = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    foreach ($base in $Bases) {
        if (-not $base) { continue }
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }

        # an explicit path that *is* an autoexec folder counts as a hit
        $baseLeaf = [System.IO.Path]::GetFileName($base.TrimEnd('\', '/'))
        if ($baseLeaf -and $names -contains $baseLeaf.ToLowerInvariant()) {
            if ($seen.Add($base)) { $found.Add($base) }
            continue
        }

        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue(@($base, 0))

        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $dir = [string]$item[0]
            $depth = [int]$item[1]
            if ($depth -gt $MaxDepth) { continue }

            $children = @()
            try { $children = [System.IO.Directory]::GetDirectories($dir) } catch { continue }

            foreach ($child in $children) {
                $leaf = [System.IO.Path]::GetFileName($child)
                $lower = $leaf.ToLowerInvariant()

                if ($skip -contains $lower) { continue }
                if ($found.Contains($child)) { continue }

                if ($names -contains $lower) {
                    if ($seen.Add($child)) { $found.Add($child) }
                    continue
                }
                if ($depth -lt $MaxDepth) { $queue.Enqueue(@($child, $depth + 1)) }
            }
        }
    }

    return @($found | Sort-Object)
}

function Get-SearchBases {
    $bases = New-Object System.Collections.Generic.List[string]
    $bases.Add($env:LOCALAPPDATA)
    $bases.Add($env:APPDATA)
    $bases.Add((Join-Path $env:USERPROFILE 'Documents'))
    $bases.Add((Join-Path $env:USERPROFILE 'Desktop'))
    $bases.Add((Join-Path $env:USERPROFILE 'Downloads'))
    $bases.Add($script:InstallDir)
    foreach ($extra in $SearchPath) { $bases.Add($extra) }
    return @($bases | Where-Object { $_ } | Select-Object -Unique)
}

function Write-Manifest {
    param([object[]]$Entries)
    if (-not (Test-Path -LiteralPath $script:InstallDir)) {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
    }

    $existing = @()
    if (Test-Path -LiteralPath $script:ManifestPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:ManifestPath)
            if ($raw.Trim().Length -gt 0) {
                $parsed = $raw | ConvertFrom-Json
                $prop = $parsed.PSObject.Properties['installed']
                if ($prop -and $prop.Value) { $existing = @($prop.Value) }
            }
        } catch { $existing = @() }
    }

    $merged = @{}
    foreach ($entry in @($existing + $Entries)) {
        if ($entry -and $entry.path) { $merged[[string]$entry.path] = $entry }
    }

    $payload = [pscustomobject]@{
        version   = 1
        updated   = (Get-Date).ToString('o')
        installed = @($merged.Values | Sort-Object { $_.path })
    }

    $json = $payload | ConvertTo-Json -Depth 6
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($script:ManifestPath, $json, $encoding)
}

function Read-Manifest {
    if (-not (Test-Path -LiteralPath $script:ManifestPath)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($script:ManifestPath)
        if ($raw.Trim().Length -eq 0) { return @() }
        $parsed = $raw | ConvertFrom-Json
        $prop = $parsed.PSObject.Properties['installed']
        if ($prop -and $prop.Value) { return @($prop.Value) }
    } catch { }
    return @()
}

function Write-IfChanged {
    param([string]$Path, [byte[]]$Bytes, [string]$Hash)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            if ((Get-Sha256 $Path) -eq $Hash) { return $false }
        } catch { }
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
    return $true
}

function Install-Into {
    param(
        [string]$TargetDir,
        [byte[]]$LoaderBytes,
        [byte[]]$BundleBytes,
        [string]$LoaderHash,
        [string]$BundleHash
    )

    $written = @()
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    # loader sits in the autoexec folder so it runs on every injection
    $loaderPath = Join-Path $TargetDir 'FischHub.lua'
    $null = Write-IfChanged -Path $loaderPath -Bytes $LoaderBytes -Hash $LoaderHash
    $written += [pscustomobject]@{ path = $loaderPath; sha256 = $LoaderHash; role = 'loader' }

    # bundle lives one level down; the loader prefers this relative path
    $hubDir = Join-Path $TargetDir 'fischhub'
    if (-not (Test-Path -LiteralPath $hubDir)) {
        New-Item -ItemType Directory -Path $hubDir -Force | Out-Null
    }
    $hubPath = Join-Path $hubDir 'hub.lua'
    $null = Write-IfChanged -Path $hubPath -Bytes $BundleBytes -Hash $BundleHash
    $written += [pscustomobject]@{ path = $hubPath; sha256 = $BundleHash; role = 'bundle' }

    # executors resolve readfile() against their workspace root, which is usually
    # the parent of the autoexec folder. Give that path the same bundle.
    $parent = Split-Path -Parent $TargetDir
    if ($parent) {
        $workspaceHubDir = Join-Path $parent 'fischhub'
        try {
            if (-not (Test-Path -LiteralPath $workspaceHubDir)) {
                New-Item -ItemType Directory -Path $workspaceHubDir -Force | Out-Null
            }
            $workspaceHubPath = Join-Path $workspaceHubDir 'hub.lua'
            $null = Write-IfChanged -Path $workspaceHubPath -Bytes $BundleBytes -Hash $BundleHash
            $written += [pscustomobject]@{ path = $workspaceHubPath; sha256 = $BundleHash; role = 'bundle' }
        } catch { }
    }

    return $written
}

function Invoke-Sync {
    param([switch]$QuietWhenEmpty, [switch]$Quiet)

    $bundle = Get-SourceBundle
    $loader = Get-SourceLoader
    if (-not $bundle) { Write-Bad 'FischHub.lua not found next to this script'; return $null }
    if (-not $loader) { Write-Bad 'loader.lua not found next to this script'; return $null }

    $bundleBytes = [System.IO.File]::ReadAllBytes($bundle)
    $loaderBytes = [System.IO.File]::ReadAllBytes($loader)
    $bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
    $loaderHash = (Get-FileHash -LiteralPath $loader -Algorithm SHA256).Hash.ToLowerInvariant()

    if (-not (Test-Path -LiteralPath $script:InstallDir)) {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
    }
    $installBundle = Join-Path $script:InstallDir 'FischHub.lua'
    $installLoader = Join-Path $script:InstallDir 'loader.lua'
    $null = Write-IfChanged -Path $installBundle -Bytes $bundleBytes -Hash $bundleHash
    $null = Write-IfChanged -Path $installLoader -Bytes $loaderBytes -Hash $loaderHash

    $dirs = @(Find-AutoexecDirs -Bases (Get-SearchBases))
    $dirs = @($dirs | Where-Object { $_ -ne $script:InstallDir })

    if ($dirs.Count -eq 0 -and -not $QuietWhenEmpty) {
        Write-Note 'no executor autoexec folder found yet'
        Write-Say  'start your executor once, then run this again with -Sync'
        Write-Say  'or point it at a folder:  .\fisch-hub.ps1 -SearchPath "C:\path\to\autoexec"'
    }

    $entries = @(
        [pscustomobject]@{ path = $installBundle; sha256 = $bundleHash; role = 'install' },
        [pscustomobject]@{ path = $installLoader; sha256 = $loaderHash; role = 'install' }
    )
    foreach ($dir in $dirs) {
        try {
            $entries += Install-Into -TargetDir $dir -LoaderBytes $loaderBytes -BundleBytes $bundleBytes -LoaderHash $loaderHash -BundleHash $bundleHash
            if (-not $Quiet) { Write-Ok "synced  $dir" }
        } catch {
            Write-Bad "failed  $dir  ($($_.Exception.Message))"
        }
    }

    Write-Manifest -Entries $entries

    return [pscustomobject]@{
        Bundle      = $bundle
        BundleHash  = $bundleHash
        Loader      = $loader
        LoaderHash  = $loaderHash
        Directories = $dirs
        Entries     = $entries
    }
}

function Show-Status {
    $bundle = Get-SourceBundle
    $loader = Get-SourceLoader
    Write-Step 'fisch hub'
    if ($bundle) {
        Write-Ok ("bundle    {0}" -f $bundle)
        Write-Say ("          {0} bytes, sha {1}" -f (Get-Item -LiteralPath $bundle).Length, (Get-Sha256 $bundle).Substring(0, 16))
    } else {
        Write-Bad 'bundle    missing next to this script'
    }
    if ($loader) { Write-Ok "loader    $loader" } else { Write-Bad 'loader    missing next to this script' }

    if (Test-Path -LiteralPath $script:InstallDir) { Write-Ok "install   $script:InstallDir" } else { Write-Note "install   not created yet" }

    $dirs = @(Find-AutoexecDirs -Bases (Get-SearchBases) | Where-Object { $_ -ne $script:InstallDir })
    Write-Step ("executor folders ({0})" -f $dirs.Count)
    if ($dirs.Count -eq 0) {
        Write-Note 'none detected'
        Write-Say  'run with -SearchPath "<folder>" if you know where your executor keeps them'
    } else {
        foreach ($dir in $dirs) {
            $hub = Join-Path (Join-Path $dir 'fischhub') 'hub.lua'
            if (Test-Path -LiteralPath $hub) {
                Write-Ok "synced    $dir"
            } else {
                Write-Note "empty     $dir"
            }
        }
    }

    $manifest = @(Read-Manifest)
    Write-Step ("manifest ({0} files)" -f $manifest.Count)
    if ($manifest.Count -eq 0) { Write-Note 'nothing installed' } else { Write-Ok $script:ManifestPath }
}

function Invoke-Verify {
    Write-Step 'verify'
    if (-not (Test-Path -LiteralPath $script:ManifestPath)) {
        Write-Bad 'no manifest - run the installer first'
        return
    }

    $manifest = @(Read-Manifest)
    if ($manifest.Count -eq 0) { Write-Bad 'manifest is empty'; return }

    $bad = 0
    $missing = 0
    foreach ($entry in $manifest) {
        if (-not (Test-Path -LiteralPath $entry.path -PathType Leaf)) {
            Write-Bad "missing   $($entry.path)"; $missing++; continue
        }
        $hash = Get-Sha256 $entry.path
        if ($hash -eq [string]$entry.sha256) {
            Write-Ok "match     $($entry.path)"
        } else {
            Write-Bad "changed   $($entry.path)"; $bad++
        }
    }

    Write-Step 'result'
    if ($bad -eq 0 -and $missing -eq 0) {
        Write-Ok ("all {0} files match" -f $manifest.Count)
    } else {
        Write-Note ("{0} changed, {1} missing - run -Sync to repair" -f $bad, $missing)
    }
}

function Invoke-Uninstall {
    Write-Step 'uninstall'
    $manifest = @(Read-Manifest)
    $removed = 0
    $kept = 0

    foreach ($entry in $manifest) {
        $path = [string]$entry.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $hash = Get-Sha256 $path
        if ($hash -eq [string]$entry.sha256) {
            Remove-Item -LiteralPath $path -Force
            $removed++
        } else {
            Write-Note "kept (modified)  $path"
            $kept++
        }
    }

    foreach ($entry in $manifest) {
        $dir = Split-Path -Parent ([string]$entry.path)
        if ($dir -and (Test-Path -LiteralPath $dir)) {
            try {
                if (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $dir -Force
                }
            } catch { }
        }
    }

    if (Test-Path -LiteralPath $script:ManifestPath) { Remove-Item -LiteralPath $script:ManifestPath -Force }

    Write-Ok ("removed {0} files, kept {1}" -f $removed, $kept)
}

function Invoke-Watch {
    Write-Step 'watching for executor folders'
    Write-Say 'ctrl+c to stop'
    $known = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    $initial = Invoke-Sync -QuietWhenEmpty -Quiet
    if ($initial) {
        foreach ($dir in $initial.Directories) { $null = $known.Add($dir) }
        if ($initial.Directories.Count -gt 0) {
            Write-Ok ("already synced {0} folder(s)" -f $initial.Directories.Count)
        }
    }

    while ($true) {
        try {
            $result = Invoke-Sync -QuietWhenEmpty -Quiet
            if ($result) {
                foreach ($dir in $result.Directories) {
                    if ($known.Add($dir)) { Write-Ok ("adopted  $dir") }
                }
            }
        } catch {
            Write-Note "sync error: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Invoke-Launch {
    $versions = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
    if (-not (Test-Path -LiteralPath $versions)) {
        Write-Bad 'Roblox player not found in LOCALAPPDATA\Roblox\Versions'
        return
    }
    $players = @(Get-ChildItem -LiteralPath $versions -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'RobloxPlayerBeta.exe' } |
        Where-Object { Test-Path -LiteralPath $_ })
    if ($players.Count -eq 0) { Write-Bad 'RobloxPlayerBeta.exe not found'; return }
    $newest = $players | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending | Select-Object -First 1
    Write-Ok "launching $newest"
    Start-Process -FilePath $newest | Out-Null
}

# ---------------------------------------------------------------- entry point

if ($Uninstall) {
    Invoke-Uninstall
    return
}

if ($Watch) {
    Invoke-Watch
    return
}

if ($Status) {
    Show-Status
    return
}

if ($Verify) {
    Invoke-Verify
    return
}

if ($Sync) {
    $result = Invoke-Sync
    if ($result) { Write-Step 'source'; Write-Say ("{0}  sha {1}" -f $result.Bundle, $result.BundleHash.Substring(0, 16)) }
    if ($Launch) { Invoke-Launch }
    return
}

# default: install, sync, report
$result = Invoke-Sync
Write-Step 'source'
if ($result) {
    Write-Ok ("{0}" -f $result.Bundle)
    Write-Say ("sha {0}  -  {1} folders" -f $result.BundleHash.Substring(0, 16), $result.Directories.Count)
} else {
    Write-Bad 'nothing installed'
}
if ($Launch) { Invoke-Launch }
Write-Step 'done'
Write-Say 'paste nothing: the loader runs from autoexec on the next injection'
Write-Say 'in game press RightControl to open the panel, Delete to panic'
