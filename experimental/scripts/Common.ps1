Set-StrictMode -Version Latest

function Get-IntegrationNames([string]$Workspace, [string]$Repository, [string]$CreationDate) {
    if ($CreationDate -notmatch '^\d{8}$') { throw 'Creation date must be YYYYMMDD.' }
    $refs = @(Read-Git $Repository @('for-each-ref','--format=%(refname)',
        "refs/heads/scadmaxx-$CreationDate*", "refs/remotes/origin/scadmaxx-$CreationDate*")) -split '\r?\n'
    $number = 1
    do {
        $suffix = if ($number -eq 1) { '' } else { "-$number" }
        $branch = "scadmaxx-$CreationDate$suffix"
        $source = Join-Path $Workspace "wt-$branch"
        $occupied = (Test-Path -LiteralPath $source) -or
            "refs/heads/$branch" -in $refs -or "refs/remotes/origin/$branch" -in $refs
        $number++
    } while ($occupied)
    return @{branch=$branch; source=$source}
}

function Read-RunInputs([string]$RunDirectory) {
    $path = Join-Path $RunDirectory 'inputs.json'
    $info = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    $overlayPath = Join-Path $RunDirectory 'layout-migration.json'
    if (Test-Path -LiteralPath $overlayPath) {
        $overlay = Get-Content -LiteralPath $overlayPath -Raw | ConvertFrom-Json -AsHashtable
        if ($overlay.inputsSha256 -ne (Get-FileHash -LiteralPath $path).Hash -or
            $overlay.oldSource -ne $info.source -or $overlay.oldBranch -ne $info.branch) {
            throw 'Layout migration does not match frozen run inputs.'
        }
        if (![IO.Path]::IsPathFullyQualified($overlay.source) -or $overlay.branch -notmatch '^scadmaxx-\d{8}(-\d+)?$') {
            throw 'Invalid migrated source path or branch.'
        }
        $info.source = $overlay.source
        $info.branch = $overlay.branch
        $info.layoutMigration = $overlay
    }
    return $info
}

function Get-SharedVcpkgConfiguration([hashtable]$Profile) {
    if (!$Profile.vcpkgInstalled -or ![IO.Path]::IsPathFullyQualified($Profile.vcpkgInstalled)) {
        throw 'Set vcpkgInstalled to the absolute path of the existing shared installed tree.'
    }
    $installed = [IO.Path]::GetFullPath($Profile.vcpkgInstalled)
    foreach ($relative in @('vcpkg/status','x64-windows/include','x64-windows/lib','x64-windows/bin')) {
        if (!(Test-Path -LiteralPath (Join-Path $installed $relative))) {
            throw "Shared vcpkg installation is incomplete: $installed/$relative. Automatic installation is disabled."
        }
    }
    # This object is hashed as part of the build identity; key order must survive separate PowerShell processes.
    return [ordered]@{
        installed = $installed
        statusHash = (Get-FileHash -LiteralPath (Join-Path $installed 'vcpkg/status')).Hash
        cmakeArguments = @('-DVCPKG_TARGET_TRIPLET=x64-windows','-DVCPKG_MANIFEST_MODE=OFF',
            '-DVCPKG_MANIFEST_INSTALL=OFF',"-DVCPKG_INSTALLED_DIR=$installed")
    }
}

function Assert-ChildPath([string]$Path, [string]$Parent) {
    $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (![IO.Path]::GetFullPath($Path).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be inside $Parent : $Path"
    }
    # Reject existing junctions/symlinks in output ancestry, which could escape the lexical boundary.
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor -and $cursor.Length -ge $prefix.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Output path traverses a reparse point: $cursor"
            }
        }
        $cursor = Split-Path $cursor -Parent
    }
}

function Save-Json([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Read-Git([string]$Repository, [string[]]$Arguments) {
    $result = & git -C $Repository @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed ($LASTEXITCODE): $($Arguments -join ' ')" }
    return ($result -join "`n").TrimEnd()
}

function Refresh-ClipperGeneratedHeader([string]$Source) {
    # Clipper's configure_file writes a tracked header with LF even on an autocrlf checkout.
    # Git can keep reporting it modified despite an identical normalized blob. Refresh only this
    # known generated file, and only when HEAD, index, and normalized working content are identical.
    $repository = Join-Path $Source 'submodules/Clipper2'
    $relative = 'CPP/Clipper2Lib/include/clipper2/clipper.version.h'
    if (!(Test-Path (Join-Path $repository $relative))) { return }
    if (!(Read-Git $repository @('status','--porcelain','--',$relative))) { return }
    $committed = Read-Git $repository @('rev-parse',"HEAD:$relative")
    $indexed = Read-Git $repository @('rev-parse',":$relative")
    $working = Read-Git $repository @('hash-object',"--path=$relative",$relative)
    if ($committed -ne $indexed -or $committed -ne $working) {
        throw 'Clipper generated header has a real source change; preserve and review it before continuing.'
    }
    Invoke-Logged 'git' @('-C',$repository,'add','--',$relative)
    if ((Read-Git $repository @('rev-parse',":$relative")) -ne $committed) { throw 'Unexpected generated-header index change.' }
}

function Get-TextHash([string]$Text) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLower()
}

function Get-FileInventory([string]$Directory) {
    # Bounded enumeration of this script's own staging/snapshot output, not filesystem discovery.
    @(Get-ChildItem -LiteralPath $Directory -Recurse -File | Sort-Object FullName | ForEach-Object {
        @{path=[IO.Path]::GetRelativePath($Directory,$_.FullName); sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
}

function Copy-QtRuntime([string]$Triplet, [string]$Destination) {
    # A complete locked Release runtime includes indirect plugin dependencies; exclude the debug tree.
    Get-ChildItem -LiteralPath (Join-Path $Triplet 'bin') -Filter '*.dll' -File | Copy-Item -Destination $Destination
    $plugins = Join-Path $Triplet 'Qt6/plugins'
    if (!(Test-Path (Join-Path $plugins 'platforms/qwindows.dll'))) { throw 'The locked Qt runtime is missing its Windows platform plugin.' }
    Get-ChildItem -LiteralPath $plugins -Directory | Copy-Item -Destination $Destination -Recurse
    $translations = Join-Path $Triplet 'translations/Qt6'
    if (Test-Path $translations) { Copy-Item -LiteralPath $translations -Destination (Join-Path $Destination 'translations') -Recurse }
    "[Paths]`nPrefix=.`nBinaries=.`nLibraries=.`nPlugins=.`nTranslations=translations`n" |
        Set-Content (Join-Path $Destination 'qt.conf') -Encoding ascii
}

function Save-ControlSnapshot([string]$Workspace, [string]$RunDirectory, [string]$Attempt, [string]$ProfilePath) {
    $destination = Join-Path $RunDirectory "control/$Attempt"
    New-Item -ItemType Directory $destination | Out-Null
    $files = @('AGENTS.md','README.md','docs/git-layout.md','docs/worktrees.md',
        'docs/workspace.md','docs/layout-migration.md',
        'workflows/update-and-build-scadmaxx.md','workflows/experimental-builds.md','experimental/PR_STACK.md',
        'experimental/SOURCES.json','experimental/integration-inputs.md','experimental/REPAIRS.md','experimental/versioning-and-releases.md',
        'experimental/profiles/windows-x64.md','experimental/templates/run-report.md')
    $files += @(Get-ChildItem (Join-Path $Workspace 'experimental/scripts') -File | ForEach-Object {
        [IO.Path]::GetRelativePath($Workspace,$_.FullName)
    })
    $repairDirectory = Join-Path $Workspace 'experimental/repairs'
    if (Test-Path $repairDirectory) {
        $files += @(Get-ChildItem $repairDirectory -Filter '*.md' -File | ForEach-Object {
            [IO.Path]::GetRelativePath($Workspace,$_.FullName)
        })
    }
    foreach ($relative in $files) {
        $target = Join-Path $destination $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        $inputPath = if ($relative -eq 'experimental/PR_STACK.md') { Join-Path $RunDirectory 'PR_STACK.md' }
            elseif ($relative -eq 'experimental/SOURCES.json' -and (Test-Path (Join-Path $RunDirectory 'source-definitions.json'))) {
                Join-Path $RunDirectory 'source-definitions.json'
            } else { Join-Path $Workspace $relative }
        Copy-Item -LiteralPath $inputPath -Destination $target
    }
    if ($ProfilePath) { Copy-Item -LiteralPath $ProfilePath -Destination (Join-Path $destination 'machine-profile.json') }
    $controlHead = & git -C $Workspace rev-parse --verify HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { $controlHead = 'unborn' }
    $inventory = Get-FileInventory $destination
    Save-Json (Join-Path $destination 'snapshot.json') @{commit=$controlHead; files=$inventory;
        status=(Read-Git $Workspace @('status','--porcelain','--untracked-files=all'))}
    return $destination
}

function Invoke-Logged([string]$Executable, [string[]]$Arguments, [switch]$RejectErrors) {
    $entry = [ordered]@{exe=$Executable; arguments=$Arguments; started=[DateTime]::UtcNow.ToString('o')}
    $script:CommandRecords.Add($entry)
    "COMMAND: $Executable $($Arguments -join ' ')" | Add-Content -LiteralPath $script:LogPath
    $reportedErrors = [Collections.Generic.List[string]]::new()
    & $Executable @Arguments 2>&1 | ForEach-Object {
        if ($RejectErrors -and "$_" -match '^ERROR:|OpenGL Program Linker Error:') { $reportedErrors.Add("$_") }
        $_
    } | Tee-Object -FilePath $script:LogPath -Append | Out-Host
    $code = $LASTEXITCODE
    $entry.exitCode = $code
    $entry.finished = [DateTime]::UtcNow.ToString('o')
    if ($code -ne 0) { throw "Command failed with exit code ${code}: $Executable (see $script:LogPath)" }
    if ($reportedErrors.Count) { throw "Application reported errors despite exit code zero: $($reportedErrors -join '; ')" }
}

function Invoke-Smoke([string]$Executable, [string]$Directory, [string]$Version, [switch]$CleanPath) {
    $runtime = Split-Path $Executable
    foreach ($obsolete in @('openscad.exe','openscad.com')) {
        if (Test-Path (Join-Path $runtime $obsolete)) { throw "Obsolete executable in SCADMaxx runtime: $obsolete" }
    }
    $console = Join-Path $runtime 'scadmaxx.com'
    if (!(Test-Path $console)) { throw 'Missing SCADMaxx console launcher.' }
    New-Item -ItemType Directory -Path $Directory | Out-Null
    $fixture = Join-Path $Directory 'smoke.scad'
    'difference() { cube([12,12,6], center=true); cylinder(h=10,r=3,center=true,$fn=32); }' |
        Set-Content -LiteralPath $fixture -Encoding ascii
    $oldPath = $env:PATH
    $oldQt = $env:QT_PLUGIN_PATH
    $oldQpa = $env:QT_QPA_PLATFORM_PLUGIN_PATH
    Push-Location (Split-Path $Executable)
    try {
        if ($CleanPath) {
            $env:PATH = "$env:SystemRoot/System32;$env:SystemRoot"
            $env:QT_PLUGIN_PATH = ''
            $env:QT_QPA_PLATFORM_PLUGIN_PATH = ''
        }
        $actualVersion = (& $Executable --version 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or !$actualVersion.Contains($Version)) { throw "Unexpected application identity: $actualVersion" }
          $actualVersion | Set-Content (Join-Path $Directory 'version.txt')
          $consoleVersion = (& $console --version 2>&1 | Out-String)
          if ($LASTEXITCODE -ne 0 -or !$consoleVersion.Contains($Version)) { throw "Unexpected console identity: $consoleVersion" }
          $consoleVersion | Set-Content (Join-Path $Directory 'console-version.txt')
        $stl = Join-Path $Directory 'smoke.stl'
        Invoke-Logged $Executable @('-o',$stl,$fixture) -RejectErrors
        if (!(Test-Path $stl) -or (Get-Item $stl).Length -lt 100) { throw 'CLI render produced no useful STL.' }
        $cgalStl = Join-Path $Directory 'smoke-cgal.stl'
        Invoke-Logged $Executable @('--backend=CGAL','-o',$cgalStl,$fixture) -RejectErrors
        if (!(Test-Path $cgalStl) -or (Get-Item $cgalStl).Length -lt 100) { throw 'CGAL render produced no useful STL.' }
        $flatFixture = Join-Path $Directory 'smoke-2d.scad'
        'difference() { square([20,20], center=true); circle(r=5,$fn=64); }' |
            Set-Content -LiteralPath $flatFixture -Encoding ascii
        $pdf = Join-Path $Directory 'smoke.pdf'
        Invoke-Logged $Executable @('-o',$pdf,$flatFixture) -RejectErrors
        if (!(Test-Path $pdf) -or (Get-Item $pdf).Length -lt 100) { throw 'Cairo export produced no useful PDF.' }
        $png = Join-Path $Directory 'preview.png'
        Invoke-Logged $Executable @('--viewall','--autocenter','--imgsize=640,480','-o',$png,$fixture) -RejectErrors
        if (!(Test-Path $png) -or (Get-Item $png).Length -lt 100) { throw 'CLI preview produced no PNG.' }
    } finally { $env:PATH = $oldPath; $env:QT_PLUGIN_PATH = $oldQt; $env:QT_QPA_PLATFORM_PLUGIN_PATH = $oldQpa; Pop-Location }
}

function Export-SourceTree([string]$Repository, [string]$Destination, [string]$ArchiveDirectory, [string]$CMake) {
    New-Item -ItemType Directory -Force $Destination,$ArchiveDirectory | Out-Null
    $sha = Read-Git $Repository @('rev-parse','HEAD')
    $archive = Join-Path $ArchiveDirectory "$sha.tar"
    Invoke-Logged 'git' @('-C',$Repository,'archive','--format=tar',"--output=$archive",$sha)
    Push-Location $Destination
    try { Invoke-Logged $CMake @('-E','tar','xf',$archive) } finally { Pop-Location }
    foreach ($line in ((Read-Git $Repository @('ls-files','--stage')) -split '\n')) {
        if ($line -match '^160000 ([0-9a-f]{40}) 0\t(.+)$') {
            $expected = $Matches[1]
            $relative = $Matches[2]
            $child = Join-Path $Repository $relative
            if ((Read-Git $child @('rev-parse','HEAD')) -ne $expected) { throw "Submodule changed during source export: $relative" }
            Export-SourceTree $child (Join-Path $Destination $relative) $ArchiveDirectory $CMake
        }
    }
}
