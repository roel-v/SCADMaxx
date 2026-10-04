#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Configure','Build','Test','Stage','Package')][string]$Step,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Build,
    [Parameter(Mandatory)][string]$Run,
    [Parameter(Mandatory)][Alias('Profile')][string]$BuildProfile,
    [string]$Staging,
    [ValidateRange(1,64)][int]$Jobs = 4
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot/Common.ps1"
$Source = [IO.Path]::GetFullPath($Source)
$Build = [IO.Path]::GetFullPath($Build)
$Run = [IO.Path]::GetFullPath($Run)
$controlRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workspace = Split-Path $controlRoot -Parent
Assert-ChildPath $Run (Join-Path $workspace 'runs')
Assert-ChildPath $Build $Run
if ($Staging) {
    $Staging = [IO.Path]::GetFullPath($Staging)
    Assert-ChildPath $Staging (Join-Path $workspace 'artifacts')
}
$p = Get-Content -LiteralPath $BuildProfile -Raw | ConvertFrom-Json -AsHashtable
foreach ($field in @('visualStudio','toolset','sdk','vcpkg','vcpkgCommit','vcpkgInstalled','cmake','flex','bison')) {
    if (!$p[$field]) { throw "Profile field missing: $field" }
}
New-Item -ItemType Directory -Force -Path $Run,$Build,(Join-Path $Run 'logs') | Out-Null
$attemptId = "$(Get-Date -AsUTC -Format yyyyMMddTHHmmssfffZ)-$($Step.ToLower())"
$script:LogPath = Join-Path $Run "logs/$attemptId.log"
$script:CommandRecords = [Collections.Generic.List[object]]::new()
$record = [ordered]@{step=$Step; started=[DateTime]::UtcNow.ToString('o'); status='running'; source=$Source; build=$Build}
$record.testEnvironment = @{osVersion=[Environment]::OSVersion.VersionString;
    architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(); cleanMachine=$false}
$runLock = $null
try {
    $runLock = [IO.File]::Open((Join-Path $Run 'build.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $record.controlSnapshot = Save-ControlSnapshot $controlRoot $Run $attemptId $BuildProfile
    $head = Read-Git $Source @('rev-parse','HEAD')
    $record.sourceSha = $head
    $record.sourceStatus = Read-Git $Source @('status','--porcelain')
    if ($record.sourceStatus) { throw 'Commit source repairs before configuring or building; every checkpoint must identify exact source contents.' }
    $record.submodules = Read-Git $Source @('submodule','status','--recursive')
    if ($record.submodules -match '(?m)^[+\-U]') { throw 'Initialize matching, conflict-free submodule revisions first.' }
    $vcpkgHead = Read-Git $p.vcpkg @('rev-parse','HEAD')
    if ($vcpkgHead -ne $p.vcpkgCommit) { throw 'vcpkg checkout differs from the pinned profile.' }
    if (Read-Git $p.vcpkg @('status','--porcelain','--untracked-files=no')) { throw 'vcpkg checkout has tracked edits.' }
    $dependencies = Get-SharedVcpkgConfiguration $p
    $installed = $dependencies.installed
    $triplet = Join-Path $installed 'x64-windows'
    # translation-make.sh invokes msgfmt by name during the application post-build step.
    $env:PATH = "$(Join-Path $triplet 'tools/gettext/bin');$(Join-Path $triplet 'bin');$env:PATH"
    $record.dependencies = $dependencies
    $missing = @('include/boost/nowide/args.hpp','share/catch2/Catch2Config.cmake') | Where-Object {
        !(Test-Path -LiteralPath (Join-Path $triplet $_))
    }
    if ($missing) {
        throw "Shared dependencies required by this build/test profile are missing: $($missing -join ', '). Automatic installation is disabled; retain the shared tree and report the gap."
    }
    Import-Module (Join-Path $p.visualStudio 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $p.visualStudio -Arch amd64 -HostArch amd64 `
        -SkipAutomaticLocation -DevCmdArguments "-vcvars_ver=$($p.toolset) -winsdk=$($p.sdk)" | Out-Null
    if ($env:VCToolsVersion.TrimEnd('\') -ne $p.toolset -or $env:WindowsSDKVersion.TrimEnd('\') -ne $p.sdk) {
        throw 'Developer environment does not match the pinned MSVC/SDK versions.'
    }
    $ninja = Join-Path $p.visualStudio 'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe'
    $compiler = Join-Path $env:VCToolsInstallDir 'bin/Hostx64/x64/cl.exe'
    $cmake = $p.cmake
    $ctest = Join-Path (Split-Path $cmake) 'ctest.exe'
    $toolHashes = [ordered]@{}
    foreach ($tool in @($compiler,$cmake,$ninja,$p.flex,$p.bison)) {
        if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required build tool is missing: $tool" }
        $toolHashes[$tool] = (Get-FileHash -LiteralPath $tool).Hash
    }
    $record.toolHashes = $toolHashes
    $runInfo = Read-RunInputs $Run
    if ($runInfo.runId -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { throw 'Invalid frozen run ID.' }
    if ((Get-FileHash (Join-Path $Run 'PR_STACK.md')).Hash -ne $runInfo.stackSha256) {
        throw 'The frozen selection was modified after preparation.'
    }
    if (![string]::Equals($Source,[IO.Path]::GetFullPath($runInfo.source),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source does not match the locked worktree for this run.'
    }
    if ((Read-Git $Source @('branch','--show-current')) -ne $runInfo.branch) { throw 'Unexpected integration branch.' }
    Invoke-Logged 'git' @('-C',$Source,'merge-base','--is-ancestor',$runInfo.upstream,$head)
    $version = "$($runInfo.versionDate)-experimental-$($runInfo.runId)"
    $navigationTuning = if (@($runInfo.entries | Where-Object { $_.id -eq 'navigation-cube' }).Count) { 'ON' } else { 'OFF' }
    $record.featureFlags = [ordered]@{
        OPENSCAD_WINDOWS_OUTPUT_NAME='scadmaxx'
        ENABLE_NAVIGATION_CUBE_TUNING=$navigationTuning
        EXPERIMENTAL='ON'
        USE_MANIFOLD_MINKOWSKI='ON'
    }
    $identity = [ordered]@{source=$Source; build=$Build; profile=$p; dependencies=$dependencies; submodules=$record.submodules; toolHashes=$toolHashes;
        cmakeVersion=(& $cmake --version | Select-Object -First 1); flags='Ninja;Release;GUI;Qt6;tests;builtin OpenCSG;app-local MSVC runtime';
        featureFlags=$record.featureFlags; toolset=$env:VCToolsVersion; sdk=$env:WindowsSDKVersion}
    $fingerprint = Get-TextHash ($identity | ConvertTo-Json -Depth 20 -Compress)
    $record.fingerprint = $fingerprint
    $statePath = Join-Path $Build 'experimental-state.json'
    $state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable } else { $null }
    if ($state -and $state.fingerprint -ne $fingerprint) { throw 'Build inputs changed incompatibly; use a fresh build directory.' }
    if ($Step -ne 'Configure' -and (!$state -or $state.configuredSha -ne $head)) { throw 'Configure this source revision before proceeding.' }
    if ($Step -ne 'Configure' -and (Get-FileHash (Join-Path $installed 'vcpkg/status')).Hash -ne $state.dependencyStatusHash) {
        throw 'Installed dependency records changed; reconfigure and verify the dependency profile.'
    }
    if ($Step -in @('Test','Stage','Package') -and (!$state.ContainsKey('builtSha') -or $state.builtSha -ne $head)) {
        throw 'A successful build of this revision is required.'
    }
    # Invalidate the attempted checkpoint and its successors before work starts. A failed retry must not
    # retain an earlier success marker for output that may now be incomplete.
    $invalidated = switch ($Step) {
        Build { @('builtSha','testedSha','stagedSha','staging','stagingInventory') }
        Test { @('testedSha','stagedSha','staging','stagingInventory') }
        Stage { @('stagedSha','staging','stagingInventory') }
    }
    if ($state -and $invalidated) {
        foreach ($key in $invalidated) { $state.Remove($key) }
        Save-Json $statePath $state
    }
    switch ($Step) {
        Configure {
            if (!$state -and (Test-Path (Join-Path $Build 'CMakeCache.txt'))) { throw 'Refusing an unowned CMake build directory.' }
            # Save ownership before invoking CMake so a failed configure can be retried without deleting its evidence.
            $state = @{fingerprint=$fingerprint; configuredSha=$null; identity=$identity; version=$version}
            Save-Json $statePath $state
            $configureArgs = @('-S',$Source,'-B',$Build,'-G','Ninja',"-DCMAKE_MAKE_PROGRAM=$ninja",'-DCMAKE_BUILD_TYPE=Release',
                "-DCMAKE_C_COMPILER=$compiler","-DCMAKE_CXX_COMPILER=$compiler",
                "-DCMAKE_TOOLCHAIN_FILE=$($p.vcpkg)/scripts/buildsystems/vcpkg.cmake") + $dependencies.cmakeArguments + @(
                '-DHEADLESS=OFF','-DUSE_QT6=ON','-DUSE_BUILTIN_OPENCSG=ON','-DENABLE_TESTS=ON',
                '-DOPENSCAD_WINDOWS_OUTPUT_NAME=scadmaxx',
                "-DENABLE_NAVIGATION_CUBE_TUNING=$navigationTuning",
                "-DEXPERIMENTAL=$($record.featureFlags.EXPERIMENTAL)",
                "-DUSE_MANIFOLD_MINKOWSKI=$($record.featureFlags.USE_MANIFOLD_MINKOWSKI)",
                '-DCMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION=.',
                "-DFLEX_EXECUTABLE=$($p.flex)","-DBISON_EXECUTABLE=$($p.bison)",
                "-DQT6QSCINTILLA_INCLUDE_DIR=$triplet/include/Qt6/Qsci",
                "-DQT6QSCINTILLA_LIBRARY=$triplet/lib/qscintilla2_qt6.lib",
                "-DOPENSCAD_VERSION=$version","-DOPENSCAD_COMMIT=$head")
            Invoke-Logged $cmake $configureArgs
            Refresh-ClipperGeneratedHeader $Source
            $state = @{fingerprint=$fingerprint; configuredSha=$head; identity=$identity; version=$version}
            $state.dependencyStatusHash = (Get-FileHash (Join-Path $installed 'vcpkg/status')).Hash
        }
        Build {
            Invoke-Logged $cmake @('--build',$Build,'--config','Release','--parallel',"$Jobs")
            $state.builtSha = $head
        }
        Test {
            $unit = Join-Path $Build 'OpenSCADUnitTests.exe'
            if (!(Test-Path $unit)) { throw 'Expected unit test binary is missing; do not silently skip unit tests.' }
            # vcpkg's app-local hook copies linked DLLs, but Qt loads TLS/platform plugins dynamically.
            $previousTestPath = $env:PATH
            $previousTestPlugins = $env:QT_PLUGIN_PATH
            $previousTestQpa = $env:QT_QPA_PLATFORM_PLUGIN_PATH
            try {
                $env:PATH = "$(Join-Path $triplet 'bin');$previousTestPath"
                $env:QT_PLUGIN_PATH = Join-Path $triplet 'Qt6/plugins'
                $env:QT_QPA_PLATFORM_PLUGIN_PATH = Join-Path $triplet 'Qt6/plugins/platforms'
                $record.testPluginPath = $env:QT_PLUGIN_PATH
                Invoke-Logged $unit @('--reporter','junit','--out',(Join-Path $Run "$attemptId-unit.xml"))
                $testRuntime = Join-Path $Run "$attemptId-runtime"
                New-Item -ItemType Directory $testRuntime | Out-Null
                Invoke-Logged $cmake @('--install',$Build,'--config','Release','--prefix',$testRuntime)
                Copy-QtRuntime $triplet $testRuntime
                Get-ChildItem -LiteralPath $Build -Filter '*.dll' -File | Copy-Item -Destination $testRuntime
                Invoke-Logged $cmake @("-DSTAGING=$testRuntime","-DDEPENDENCY_BIN=$triplet/bin",'-P',"$PSScriptRoot/Deploy-Runtime.cmake")
                Invoke-Smoke (Join-Path $testRuntime 'scadmaxx.exe') (Join-Path $Run $attemptId) $version -CleanPath
            } finally {
                $env:PATH = $previousTestPath
                $env:QT_PLUGIN_PATH = $previousTestPlugins
                $env:QT_QPA_PLATFORM_PLUGIN_PATH = $previousTestQpa
            }
            $state.testedSha = $head
        }
        Stage {
            if (!$Staging) { throw '-Staging is required.' }
            if (Test-Path $Staging) { throw 'Use a new staging directory; existing contents are preserved.' }
            if ($record.sourceStatus) { throw 'Packaging requires a clean committed source checkout.' }
            if (!$state.ContainsKey('testedSha') -or $state.testedSha -ne $head) { throw 'Run Test successfully before staging.' }
            $ledger = Get-Content (Join-Path $Run 'integrations.json') -Raw | ConvertFrom-Json -AsHashtable
            foreach ($entry in $runInfo.entries) {
                $matches = @($ledger | Where-Object { $_.id -eq $entry.id -and $_.sourceHead -eq $entry.head })
                if ($matches.Count -ne 1 -or $matches[0].outcome -notin @('integrated','already-present')) {
                    throw "Missing successful integration evidence for $($entry.id)"
                }
                $checkpoint = $matches[0]
                Invoke-Logged 'git' @('-C',$Source,'merge-base','--is-ancestor',$checkpoint.commit,$head)
                $verificationPath = Join-Path $Run $checkpoint.verificationLog
                Assert-ChildPath $verificationPath (Join-Path $Run 'logs')
                $verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json -AsHashtable
                if ($verification.step -ne 'Test' -or $verification.status -ne 'passed' -or
                    $verification.sourceSha -ne $checkpoint.commit) {
                    throw "Checkpoint $($entry.id) requires a passing Test record for its exact commit."
                }
            }
            New-Item -ItemType Directory $Staging | Out-Null
            Invoke-Logged $cmake @('--install',$Build,'--config','Release','--prefix',$Staging)
            # Ship the locked Release runtime set, including libraries loaded indirectly by plugins.
            # qtbase's optional windeployqt feature is not required by this profile.
            Copy-QtRuntime $triplet $Staging
            # Include application-built runtime libraries copied by vcpkg's app-local hook.
            Get-ChildItem -LiteralPath $Build -Filter '*.dll' -File | Copy-Item -Destination $Staging
            Invoke-Logged $cmake @("-DSTAGING=$Staging","-DDEPENDENCY_BIN=$triplet/bin",'-P',"$PSScriptRoot/Deploy-Runtime.cmake")
            foreach ($requiredResource in @('scadmaxx.exe','scadmaxx.com','msvcp140.dll','vcruntime140.dll','platforms/qwindows.dll','fonts','color-schemes',
                'shaders','examples','templates','libraries/MCAD')) {
                if (!(Test-Path (Join-Path $Staging $requiredResource))) { throw "Missing packaged resource: $requiredResource" }
            }
            Copy-Item (Join-Path $Source 'COPYING') $Staging
            # Selected agent features ship direct-HTTP skills and contracts with the GUI.
            # Copy tracked documentation only; test drivers and caches are not product tools.
            $agentBundles = @{ 'http-agent-server'='openscad-agent-server' }
            foreach ($featureId in $agentBundles.Keys) {
                if ($featureId -notin $runInfo.entries.id) { continue }
                $bundle = $agentBundles[$featureId]
                $tracked = @(& git -C $Source ls-files -- "contrib/$bundle/*.md" "contrib/$bundle/*.json")
                if ($LASTEXITCODE -ne 0 -or !$tracked.Count) { throw "Missing tracked agent skill bundle for $featureId" }
                foreach ($relative in $tracked) {
                    $destination = Join-Path $Staging $relative.Substring('contrib/'.Length)
                    New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
                    Copy-Item -LiteralPath (Join-Path $Source $relative) -Destination $destination
                }
            }
            $licenses = Join-Path $Staging 'licenses'
            New-Item -ItemType Directory $licenses | Out-Null
            Get-ChildItem (Join-Path $triplet 'share') -Directory | ForEach-Object {
                $notice = Join-Path $_.FullName 'copyright'
                if (Test-Path $notice) { Copy-Item $notice (Join-Path $licenses "$($_.Name).txt") }
            }
            foreach ($relative in @('submodules/Clipper2/LICENSE','submodules/manifold/LICENSE',
                'submodules/mimalloc/LICENSE','submodules/OpenCSG/copying.txt',
                'submodules/OpenCSG/doc/license/gpl-2.0.txt','submodules/OpenCSG/doc/license/gpl-3.0.txt',
                'libraries/MCAD/lgpl-2.1.txt','resources/icons/license.txt','resources/icons/tabler/LICENSE')) {
                if (Test-Path (Join-Path $Source $relative)) {
                    Copy-Item (Join-Path $Source $relative) (Join-Path $licenses ($relative.Replace('/','-')))
                }
            }
            $sourceHistory = Read-Git $Source @('log','--reverse','--format=fuller',"$($runInfo.upstream)..$head")
            $sourceHistory | Set-Content (Join-Path $Run 'final-source-commits.txt') -Encoding utf8NoBOM
            $info = @{inputs=$runInfo; finalSource=$head; sourceHistory=$sourceHistory; version=$version; submodules=$record.submodules;
                testEnvironment=$record.testEnvironment;
                profile=$p; featureFlags=$record.featureFlags; fingerprint=$fingerprint; controlSnapshot=$record.controlSnapshot;
                dependencyStatusHash=$state.dependencyStatusHash;
                qtDeployment='locked Release DLLs and Qt plugin directories with app-local qt.conf';
                integrations=$ledger; verification='automated checks only; see GUI evidence'}
            Save-Json (Join-Path $Staging 'build-info.json') $info
            Invoke-Smoke (Join-Path $Staging 'scadmaxx.exe') (Join-Path $Run "$attemptId-smoke") $version -CleanPath
            $state.stagedSha = $head
            $state.staging = $Staging
            $state.stagingInventory = Get-FileInventory $Staging
        }
        Package {
            if (!$Staging -or !$state.ContainsKey('stagedSha') -or $state.stagedSha -ne $head -or $state.staging -ne $Staging) {
                throw 'Stage this revision and path successfully first.'
            }
            if ($record.sourceStatus) { throw 'Packaging requires a clean committed source checkout.' }
            $original = $state.stagingInventory | ForEach-Object { "$($_.path):$($_.sha256)" }
            $current = Get-FileInventory $Staging | ForEach-Object { "$($_.path):$($_.sha256)" }
            if (Compare-Object $original $current) { throw 'Staging changed after verification; stage and test a new attempt.' }
            $zip = Join-Path (Split-Path $Staging) 'scadmaxx-2026100-windows-x64.zip'
            $extract = Join-Path (Split-Path $Staging) 'extracted-check'
            if ((Test-Path $zip) -or (Test-Path $extract)) { throw 'Existing package/extraction is preserved; use a new delivery attempt.' }
            $archiveContents = @(Get-ChildItem -LiteralPath $Staging | Select-Object -ExpandProperty FullName)
            Compress-Archive -LiteralPath $archiveContents -DestinationPath $zip
            Expand-Archive -LiteralPath $zip -DestinationPath $extract
            Invoke-Smoke (Join-Path $extract 'scadmaxx.exe') (Join-Path $Run "$attemptId-smoke") $version -CleanPath
            $hash = Get-FileHash $zip -Algorithm SHA256
            Set-Content "$zip.sha256" "$($hash.Hash.ToLower())  $(Split-Path $zip -Leaf)" -Encoding ascii
            $record.zip = $zip
            $record.sha256 = $hash.Hash
            $sourceStage = Join-Path $Run "$attemptId-source"
            Export-SourceTree $Source $sourceStage (Join-Path $Run "$attemptId-source-tars") $cmake
            $material = Join-Path $sourceStage 'experimental-build-material'
            New-Item -ItemType Directory $material | Out-Null
            Copy-Item (Join-Path $Staging 'build-info.json'),(Join-Path $Run 'inputs.json'),
                (Join-Path $Run 'integrations.json'),(Join-Path $Run 'report.md') $material
            Copy-Item -LiteralPath $record.controlSnapshot -Destination (Join-Path $material 'controls') -Recurse
            Copy-Item -LiteralPath (Join-Path $Run 'logs') -Destination (Join-Path $material 'logs') -Recurse
            foreach ($evidenceFolder in @('feature-checks','baseline-repair-probes')) {
                $evidencePath = Join-Path $Run $evidenceFolder
                if (Test-Path $evidencePath) { Copy-Item -LiteralPath $evidencePath -Destination $material -Recurse }
            }
            Invoke-Logged 'git' @('-C',$Source,'format-patch','--no-signature',
                '--output-directory',(Join-Path $material 'composition-patches'),"$($runInfo.upstream)..$head")
            Get-ChildItem -LiteralPath $Run -File | Where-Object {
                $_.Extension -in @('.patch','.xml') -or $_.Name -like '*-commits.txt'
            } | Copy-Item -Destination $material
            Copy-Item (Join-Path $installed 'vcpkg/status') (Join-Path $material 'dependency-status.txt')
            Copy-Item (Join-Path $Build 'CMakeCache.txt') $material
            @'
This source archive contains OpenSCAD and its exact submodule contents.
The build material identifies the final source commit, locked inputs, toolchain, and dependency versions.
For a checkout-based replay, obtain the recorded Git revisions and use controls/experimental/scripts/README.md.
For this extracted tree, configure CMake directly using the recorded cache options and an existing shared vcpkg
installed tree matching dependency-status.txt. Set VCPKG_MANIFEST_MODE=OFF, VCPKG_MANIFEST_INSTALL=OFF and
VCPKG_INSTALLED_DIR to that tree; replace machine-specific source/build/tool paths. Dependencies are not installed
by these scripts. Set OPENSCAD_VERSION and OPENSCAD_COMMIT from build-info.json.
Set OPENSCAD_WINDOWS_OUTPUT_NAME=scadmaxx to produce scadmaxx.exe and scadmaxx.com.
Then use cmake --build and cmake --install. The orchestration scripts require a Git checkout for provenance;
they must not be used to claim that a newly initialized archive checkout has the original commit identity.
'@ | Set-Content (Join-Path $material 'REBUILD.txt') -Encoding utf8NoBOM
            $sourceZip = Join-Path (Split-Path $Staging) "OpenSCAD-experimental-$($runInfo.runId)-source.zip"
            if (Test-Path $sourceZip) { throw 'Existing source archive is preserved.' }
            Compress-Archive -LiteralPath $sourceStage -DestinationPath $sourceZip
            $sourceHash = Get-FileHash $sourceZip -Algorithm SHA256
            Set-Content "$sourceZip.sha256" "$($sourceHash.Hash.ToLower())  $(Split-Path $sourceZip -Leaf)" -Encoding ascii
            $record.sourceZip = $sourceZip
            $record.sourceSha256 = $sourceHash.Hash
            $record.status = 'packaged-automated-checks-passed'
            # Full release success and tagging also require the documented GUI/feature/source-delivery evidence.
        }
    }
    if ((Read-Git $Source @('rev-parse','HEAD')) -ne $head) { throw 'Source HEAD changed during this step; results are not verified.' }
    if ((Get-FileHash (Join-Path $installed 'vcpkg/status')).Hash -ne $dependencies.statusHash) {
        throw 'Shared dependency records changed during this step; results are not verified.'
    }
    if (Read-Git $Source @('status','--porcelain')) {
        throw 'Source checkout changed during this step; results are not verified.'
    }
    Save-Json $statePath $state
    if ($record.status -eq 'running') { $record.status = 'passed' }
} catch {
    $record.status = 'failed'
    $record.error = $_.ToString()
    throw
} finally {
    $record.finished = [DateTime]::UtcNow.ToString('o')
    $record.commands = @($script:CommandRecords.ToArray())
    Save-Json (Join-Path $Run "logs/$attemptId.json") $record
    if ($runLock) { $runLock.Dispose() }
}
