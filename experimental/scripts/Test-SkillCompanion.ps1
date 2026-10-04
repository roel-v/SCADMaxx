#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot/Common.ps1"
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$container = Split-Path $workspace -Parent
$root = [IO.Path]::GetFullPath($OutputRoot)
Assert-ChildPath $root (Join-Path $container 'runs')
$case = Join-Path $root ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $case | Out-Null
$script:LogPath = Join-Path $case 'commands.log'
$script:CommandRecords = [Collections.Generic.List[object]]::new()
$checks = [Collections.Generic.List[string]]::new()
function Check([string]$Name, [scriptblock]$Action) { & $Action; $checks.Add($Name) }
function Fail([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null } catch { if ($_.ToString() -notmatch $Pattern) { throw }; return }
    throw "Expected failure matching: $Pattern"
}
function Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message : expected '$Expected', got '$Actual'" }
}
function InventoryText([string]$Path) {
    return (@(Get-FileInventory $Path | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n")
}
function ZipContents([string]$Path) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $result = @{}
        foreach ($entry in $archive.Entries) {
            if (!$entry.Name) { continue }
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $result[$entry.FullName.Replace('\','/')] = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
        }
        return $result
    } finally { $archive.Dispose() }
}

# The phase explicitly permits fixture commits, only inside this fresh retained evidence directory.
$source = Join-Path $case 'source'
New-Item -ItemType Directory -Path (Join-Path $source 'doc'),(Join-Path $source 'contrib/openscad-agent-server') | Out-Null
$canonical = Join-Path $source 'doc/customizer-attributes.md'
$canonicalText = "# Canonical fixture`nUnicode α and exact attribute details.`n"
[IO.File]::WriteAllText($canonical,$canonicalText)
'# HTTP source skill' | Set-Content (Join-Path $source 'contrib/openscad-agent-server/SKILL.md') -Encoding utf8NoBOM
'{"version":1}' | Set-Content (Join-Path $source 'contrib/openscad-agent-server/contract.json') -Encoding utf8NoBOM
'excluded driver' | Set-Content (Join-Path $source 'contrib/openscad-agent-server/driver.py') -Encoding utf8NoBOM
Invoke-Logged git @('init','-b','main',$source)
Invoke-Logged git @('-C',$source,'config','core.autocrlf','false')
Invoke-Logged git @('-C',$source,'add','--','doc','contrib')
$hooks = Join-Path $case 'empty-hooks'
New-Item -ItemType Directory -Path $hooks | Out-Null
Invoke-Logged git @('-C',$source,'-c','user.name=Skill companion fixture','-c','user.email=fixture@example.invalid',
    '-c',"core.hooksPath=$hooks",'-c','commit.gpgsign=false','commit','-m','Create skill companion source fixture')
$sourceSha = Read-Git $source @('rev-parse','HEAD')
$snapshotRun = Join-Path $case 'run'
New-Item -ItemType Directory -Path $snapshotRun | Out-Null
'# Frozen selection fixture' | Set-Content (Join-Path $snapshotRun 'PR_STACK.md')
$snapshot = Save-ControlSnapshot $workspace $snapshotRun 'stage' ''
$manifest = Join-Path $snapshot 'snapshot.json'
$skill = Join-Path $snapshot 'skills/scadmaxx'
$builder = Join-Path $snapshot 'experimental/scripts/Build-ScadmaxxSkill.ps1'
$arguments = @{CustomizerSourceRoot=$source; SkillRoot=$skill; ControlManifestPath=$manifest;
    WorkDirectory=(Join-Path $case 'work'); OutputZip=(Join-Path $case 'fixture-scadmaxx-skill.zip')}
$before = InventoryText $snapshot
$beforeSource = InventoryText (Join-Path $source 'doc')
Check 'snapshot includes authored skill, builder and runbook hashes' {
    Assert-ControlSnapshot $snapshot | Out-Null
    $info = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable
    foreach ($relative in @('skills/scadmaxx/SKILL.md','skills/scadmaxx/references/task-routing.md',
        'experimental/scripts/Build-ScadmaxxSkill.ps1','docs/scadmaxx-skill.md')) {
        $matches = @($info.files | Where-Object { $_.path.Replace('\','/') -eq $relative })
        Equal $matches.Count 1 "Snapshot inventory $relative"
        Equal $matches[0].sha256 (Get-FileHash (Join-Path $snapshot $relative)).Hash "Snapshot hash $relative"
    }
}
Check 'later live authored changes leave saved skill snapshot intact' {
    $live = Join-Path $case 'live-controls'
    Copy-Item -LiteralPath $snapshot -Destination $live -Recurse
    Remove-Item -LiteralPath (Join-Path $live 'snapshot.json')
    Invoke-Logged git @('init','-b','main',$live)
    $saved = Save-ControlSnapshot $live $snapshotRun 'live-isolation' ''
    $frozenHash = (Get-FileHash (Join-Path $saved 'skills/scadmaxx/SKILL.md')).Hash
    Add-Content -LiteralPath (Join-Path $live 'skills/scadmaxx/SKILL.md') -Value 'changed only in fixture live controls'
    Assert-ControlSnapshot $saved | Out-Null
    Equal (Get-FileHash (Join-Path $saved 'skills/scadmaxx/SKILL.md')).Hash $frozenHash 'Saved skill after live edit'
    if ((Get-FileHash (Join-Path $live 'skills/scadmaxx/SKILL.md')).Hash -eq $frozenHash) { throw 'Fixture live edit did not change content.' }
}
$built = @(& $builder @arguments)
Check 'builder returns one structured verified artifact' {
    Equal $built.Count 1 'Result count'
    Equal $built[0].path $arguments.OutputZip 'Output path'
    Equal $built[0].source_revision $sourceSha 'Source revision'
    Equal $built[0].sha256 (Get-FileHash $arguments.OutputZip).Hash.ToLowerInvariant() 'Archive hash'
    Equal $built[0].document_sha256 (Get-FileHash $canonical).Hash.ToLowerInvariant() 'Document hash'
    Equal $built[0].control_manifest_sha256 (Get-FileHash $manifest).Hash.ToLowerInvariant() 'Manifest hash'
}
$contents = ZipContents $arguments.OutputZip
Check 'single archive root and exact generated canonical/provenance contents' {
    foreach ($path in $contents.Keys) { if (!$path.StartsWith('scadmaxx/')) { throw "Unexpected archive root: $path" } }
    Equal $contents['scadmaxx/references/customizer-attributes.md'] $canonicalText 'Generated reference'
    $provenance = $contents['scadmaxx/references/bundle-source.json'] | ConvertFrom-Json -AsHashtable
    Equal $provenance.schema_version 1 'Schema version'
    Equal $provenance.source_revision $sourceSha 'Embedded source'
    Equal $provenance.canonical_document 'doc/customizer-attributes.md' 'Relative canonical path'
    Equal $provenance.document_sha256 $built[0].document_sha256 'Embedded document hash'
    Equal $provenance.control_manifest_sha256 $built[0].control_manifest_sha256 'Embedded manifest hash'
    if ($contents['scadmaxx/references/bundle-source.json'] -match '[A-Za-z]:[\\/]') { throw 'Private absolute path in provenance.' }
}
Check 'building preserves all frozen and canonical authored inputs' {
    Equal (InventoryText $snapshot) $before 'Frozen input inventory'
    Equal (InventoryText (Join-Path $source 'doc')) $beforeSource 'Canonical input inventory'
}
$next = @{} + $arguments
$next.OutputZip = Join-Path $case 'second-scadmaxx-skill.zip'
$next.WorkDirectory = Join-Path $case 'second-work'
& $builder @next | Out-Null
$secondContents = ZipContents $next.OutputZip
Check 'identical semantic inputs produce identical archive contents' {
    Equal $contents.Count $secondContents.Count 'Archive file count'
    foreach ($path in $contents.Keys) { Equal $contents[$path] $secondContents[$path] "Repeated content $path" }
}

$failureNumber = 0
function New-FailureArguments {
    $script:failureNumber++
    $fresh = @{} + $arguments
    $fresh.WorkDirectory = Join-Path $case "failure-$script:failureNumber-work"
    $fresh.OutputZip = Join-Path $case "failure-$script:failureNumber.zip"
    return $fresh
}
Check 'missing canonical document rejects before creating outputs' {
    $a = New-FailureArguments
    $missingSource = Join-Path $case 'missing-source'
    New-Item -ItemType Directory $missingSource | Out-Null
    $a.CustomizerSourceRoot = $missingSource
    Fail { & $builder @a } 'Missing canonical document'
    if ((Test-Path $a.WorkDirectory) -or (Test-Path $a.OutputZip)) { throw 'Missing input created output.' }
}
Check 'missing manifest and skill reject before creating outputs' {
    foreach ($field in @('ControlManifestPath','SkillRoot')) {
        $a = New-FailureArguments; $a[$field] = Join-Path $case 'absent'
        Fail { & $builder @a } 'Missing'
        if ((Test-Path $a.WorkDirectory) -or (Test-Path $a.OutputZip)) { throw 'Missing input created output.' }
    }
}
Check 'unidentified source revision rejects before creating outputs' {
    $a = New-FailureArguments
    $noGit = Join-Path $case 'unidentified-source'
    New-Item -ItemType Directory -Path (Join-Path $noGit 'doc') | Out-Null
    Copy-Item -LiteralPath $canonical -Destination (Join-Path $noGit 'doc/customizer-attributes.md')
    $a.CustomizerSourceRoot = $noGit
    Fail { & $builder @a } 'Cannot establish canonical source provenance'
    if ((Test-Path $a.WorkDirectory) -or (Test-Path $a.OutputZip)) { throw 'Unidentified source created output.' }
}
Check 'dirty canonical document rejects without altering inputs' {
    $a = New-FailureArguments
    [IO.File]::WriteAllText($canonical,$canonicalText + 'modified')
    try {
        Fail { & $builder @a } 'Canonical document differs'
        Equal (Get-Content $canonical -Raw) ($canonicalText + 'modified') 'Dirty document preserved'
        if (Test-Path $a.WorkDirectory) { throw 'Dirty canonical created staging.' }
    } finally { [IO.File]::WriteAllText($canonical,$canonicalText) }
}
Check 'existing work and archive paths are preserved' {
    $archiveHash = (Get-FileHash $arguments.OutputZip).Hash
    Fail { & $builder @arguments } 'Output already exists'
    Equal (Get-FileHash $arguments.OutputZip).Hash $archiveHash 'Existing archive preserved'
    $a = New-FailureArguments; New-Item -ItemType Directory $a.WorkDirectory | Out-Null
    Fail { & $builder @a } 'Work directory already exists'
    if (Test-Path $a.OutputZip) { throw 'Existing work produced artifact.' }
}
Check 'nested input/output paths reject without authored mutations' {
    foreach ($field in @('WorkDirectory','OutputZip')) {
        $a = New-FailureArguments; $a[$field] = Join-Path $skill 'nested.zip'
        Fail { & $builder @a } 'outside authored/frozen inputs'
    }
    $a = New-FailureArguments; $a.OutputZip = Join-Path $a.WorkDirectory 'nested.zip'
    Fail { & $builder @a } 'outside WorkDirectory'
    Equal (InventoryText $snapshot) $before 'Input inventory after rejected overlap'
}
Check 'changed and extra frozen skill inputs reject' {
    $entry = Join-Path $skill 'SKILL.md'; $original = [IO.File]::ReadAllBytes($entry)
    $a = New-FailureArguments
    try { Add-Content $entry 'changed'; Fail { & $builder @a } 'differs from control snapshot manifest' }
    finally { [IO.File]::WriteAllBytes($entry,$original) }
    $extra = Join-Path $skill 'unexpected.md'
    try { 'extra' | Set-Content $extra; $a = New-FailureArguments; Fail { & $builder @a } 'differs from control snapshot manifest' }
    finally { Remove-Item -LiteralPath $extra }
}
Check 'missing frozen skill input rejects' {
    $reference = Join-Path $skill 'references/inspection.md'; $original = [IO.File]::ReadAllBytes($reference)
    try {
        Remove-Item -LiteralPath $reference
        $a = New-FailureArguments
        Fail { & $builder @a } 'inventory differs from control snapshot manifest'
    } finally { [IO.File]::WriteAllBytes($reference,$original) }
}
Check 'unreadable skill input rejects before creating outputs' {
    $a = New-FailureArguments
    $locked = [IO.File]::Open((Join-Path $skill 'SKILL.md'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try { Fail { & $builder @a } 'being used|cannot access|access.*denied|Unable to access' } finally { $locked.Dispose() }
    if ((Test-Path $a.WorkDirectory) -or (Test-Path $a.OutputZip)) { throw 'Unreadable input created output.' }
}

$lifecycle = New-SkillCompanion $snapshot $source (Join-Path $case 'lifecycle-work') (Join-Path $case 'lifecycle-scadmaxx-skill.zip')
Check 'Stage helper invokes frozen builder and ties recorded metadata to ZIP' {
    Assert-SkillCompanion $lifecycle.path $lifecycle.metadata $snapshot $source
    Equal $lifecycle.metadata.filename 'lifecycle-scadmaxx-skill.zip' 'Relative filename'
    Equal $lifecycle.metadata.source_revision $sourceSha 'Stage source'
}
Check 'changed frozen builder is rejected before Stage invocation' {
    $original = [IO.File]::ReadAllBytes($builder)
    try {
        Add-Content $builder '# modified'
        Fail { New-SkillCompanion $snapshot $source (Join-Path $case 'bad-builder-work') (Join-Path $case 'bad-builder.zip') } 'snapshot file/hash mismatch'
    } finally { [IO.File]::WriteAllBytes($builder,$original) }
}
Check 'Package rejects missing and modified companion artifacts' {
    Fail { Assert-SkillCompanion (Join-Path $case "absent/$($lifecycle.metadata.filename)") $lifecycle.metadata $snapshot $source } 'missing or its SHA-256 changed'
    $original = [IO.File]::ReadAllBytes($lifecycle.path)
    try { Add-Content $lifecycle.path 'tampered'; Fail { Assert-SkillCompanion $lifecycle.path $lifecycle.metadata $snapshot $source } 'missing or its SHA-256 changed' }
    finally { [IO.File]::WriteAllBytes($lifecycle.path,$original) }
}
Check 'Package rejects conflicting source and manifest provenance' {
    foreach ($field in @('source_revision','document_sha256','control_manifest_sha256')) {
        $bad = @{} + $lifecycle.metadata; $bad[$field] = '0' * $(if ($field -eq 'source_revision') { 40 } else { 64 })
        Fail { Assert-SkillCompanion $lifecycle.path $bad $snapshot $source } 'provenance does not match|manifest hash does not match'
    }
}
Check 'Package rejects archive provenance mismatch despite updated archive hash' {
    $tampered = Join-Path $case 'tampered'
    New-Item -ItemType Directory $tampered | Out-Null
    $zip = Join-Path $tampered $lifecycle.metadata.filename
    Copy-Item -LiteralPath $lifecycle.path -Destination $zip
    $archive = [IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = @($archive.Entries | Where-Object { $_.FullName.Replace('\','/') -eq 'scadmaxx/references/bundle-source.json' })[0]
        $name = $entry.FullName; $entry.Delete(); $replacement = $archive.CreateEntry($name)
        $writer = [IO.StreamWriter]::new($replacement.Open())
        try { $writer.Write('{"schema_version":1,"canonical_document":"doc/customizer-attributes.md","source_revision":"wrong","document_sha256":"wrong","control_manifest_sha256":"wrong"}') }
        finally { $writer.Dispose() }
    } finally { $archive.Dispose() }
    $bad = @{} + $lifecycle.metadata; $bad.sha256 = (Get-FileHash $zip).Hash.ToLowerInvariant()
    Fail { Assert-SkillCompanion $zip $bad $snapshot $source } 'archive provenance mismatch'
}
Check 'Package delivers exact Stage artifact with checksum and preserves existing deliveries' {
    $delivery = Join-Path $case 'delivery'; New-Item -ItemType Directory $delivery | Out-Null
    $delivered = Copy-SkillCompanion $lifecycle.path $lifecycle.metadata $snapshot $source $delivery
    Equal (Get-FileHash $delivered).Hash.ToLowerInvariant() $lifecycle.metadata.sha256 'Delivered hash'
    Equal (Get-Content "$delivered.sha256" -Raw).Trim() "$($lifecycle.metadata.sha256)  $($lifecycle.metadata.filename)" 'Checksum file'
    Fail { Copy-SkillCompanion $lifecycle.path $lifecycle.metadata $snapshot $source $delivery } 'Existing companion delivery is preserved'
}
Check 'source HTTP bundle still delivers selected tracked documentation only' {
    $staging = Join-Path $case 'application-staging'; New-Item -ItemType Directory $staging | Out-Null
    Copy-SourceAgentBundles $source $staging @(@{id='http-agent-server'})
    foreach ($name in @('SKILL.md','contract.json')) {
        Equal (Get-FileHash (Join-Path $staging "openscad-agent-server/$name")).Hash `
            (Get-FileHash (Join-Path $source "contrib/openscad-agent-server/$name")).Hash "HTTP bundle $name"
    }
    if (Test-Path (Join-Path $staging 'openscad-agent-server/driver.py')) { throw 'Source test driver shipped.' }
    $unselected = Join-Path $case 'unselected-staging'; New-Item -ItemType Directory $unselected | Out-Null
    Copy-SourceAgentBundles $source $unselected @(@{id='other'})
    if (Test-Path (Join-Path $unselected 'openscad-agent-server')) { throw 'Unselected source HTTP bundle shipped.' }
}
Check 'all failure cases preserve final frozen and canonical authored input hashes' {
    Equal (InventoryText $snapshot) $before 'Final frozen input inventory'
    Equal (InventoryText (Join-Path $source 'doc')) $beforeSource 'Final canonical input inventory'
}
Save-Json (Join-Path $case 'evidence.json') @{casesPassed=$checks.Count; checks=@($checks.ToArray());
    sourceRevision=$sourceSha; snapshot=$snapshot; artifact=$lifecycle; commands=@($script:CommandRecords.ToArray())}
"Passed $($checks.Count) companion artifact/lifecycle checks. Evidence: $case"
