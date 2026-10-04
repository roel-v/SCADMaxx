#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CustomizerSourceRoot,
    [Parameter(Mandatory)][string]$OutputZip,
    [Parameter(Mandatory)][string]$SkillRoot,
    [Parameter(Mandatory)][string]$WorkDirectory,
    [Parameter(Mandatory)][string]$ControlManifestPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Resolve-Input([string]$Path, [string]$Kind, [string]$Label) {
    if (!(Test-Path -LiteralPath $Path -PathType $Kind)) { throw "Missing $Label : $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-NoReparsePoint([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Path traverses a reparse point: $cursor"
        }
        $cursor = Split-Path $cursor -Parent
    }
}

function Read-SourceGit([string[]]$Arguments) {
    $result = & git -c "safe.directory=$($sourceRoot.Replace('\','/'))" -C $sourceRoot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Cannot establish canonical source provenance: git $($Arguments -join ' ')" }
    return ($result -join "`n").TrimEnd()
}

# Validate the complete input/output contract before creating anything. The source document must
# belong to the identified commit; an untracked or modified document cannot describe a release.
$sourceRoot = Resolve-Input $CustomizerSourceRoot Container 'canonical source checkout'
$frozenSkill = Resolve-Input $SkillRoot Container 'frozen skill'
$manifest = Resolve-Input $ControlManifestPath Leaf 'control snapshot manifest'
$canonicalRelative = 'doc/customizer-attributes.md'
$canonical = Resolve-Input (Join-Path $sourceRoot $canonicalRelative) Leaf 'canonical document'
Resolve-Input (Join-Path $frozenSkill 'SKILL.md') Leaf 'skill entry' | Out-Null
Resolve-Input (Join-Path $frozenSkill 'references') Container 'skill references' | Out-Null
$destination = [IO.Path]::GetFullPath($OutputZip)
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $destination) { throw "Output already exists: $destination" }
if (Test-Path -LiteralPath $work) { throw "Work directory already exists: $work" }
if ([IO.Path]::GetExtension($destination) -ne '.zip') { throw 'OutputZip must end in .zip.' }
foreach ($output in @($destination,$work)) {
    Assert-NoReparsePoint $output
    foreach ($inputRoot in @($sourceRoot,$frozenSkill,(Split-Path $manifest))) {
        $prefix = $inputRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        if ($output.Equals($inputRoot,[StringComparison]::OrdinalIgnoreCase) -or
            $output.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Output must be outside authored/frozen inputs: $output"
        }
    }
}
if ($destination.StartsWith($work.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase) -or $work.Equals($destination,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputZip must be outside WorkDirectory.'
}
$sourceRevision = Read-SourceGit @('rev-parse','--verify','HEAD')
if ($sourceRevision -notmatch '^[0-9a-f]{40,64}$') { throw 'Cannot identify source revision.' }
Read-SourceGit @('ls-files','--error-unmatch','--',$canonicalRelative) | Out-Null
if (Read-SourceGit @('status','--porcelain','--',$canonicalRelative)) {
    throw 'Canonical document differs from the source commit; commit the selected document before packaging.'
}

# Validate every skill file against the existing snapshot manifest, including extra files.
$snapshot = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable
if (!$snapshot.ContainsKey('files') -or !$snapshot.ContainsKey('commit')) { throw 'Invalid control snapshot manifest.' }
function Assert-SkillSnapshot([string]$Directory) {
    $skillFiles = @(Get-ChildItem -LiteralPath $Directory -Recurse -File)
    foreach ($file in $skillFiles) {
        Assert-NoReparsePoint $file.FullName
        $relative = 'skills/scadmaxx/' + [IO.Path]::GetRelativePath($Directory,$file.FullName).Replace('\','/')
        $entries = @($snapshot.files | Where-Object { $_.path.Replace('\','/') -eq $relative })
        if ($entries.Count -ne 1 -or $entries[0].sha256 -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
            throw "Frozen skill differs from control snapshot manifest: $relative"
        }
    }
    $recordedSkill = @($snapshot.files | Where-Object { $_.path.Replace('\','/').StartsWith('skills/scadmaxx/') })
    if ($recordedSkill.Count -ne $skillFiles.Count) { throw 'Frozen skill inventory differs from control snapshot manifest.' }
}
Assert-SkillSnapshot $frozenSkill
Assert-NoReparsePoint $canonical
Assert-NoReparsePoint $manifest
$documentHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Verbose "Staging frozen skill for source $sourceRevision"
New-Item -ItemType Directory -Path $work | Out-Null
$stagedSkill = Join-Path $work 'scadmaxx'
Copy-Item -LiteralPath $frozenSkill -Destination $stagedSkill -Recurse
# Validate the actual copy before replacing generated files, closing the validation/copy race.
Assert-SkillSnapshot $stagedSkill
Copy-Item -LiteralPath $canonical -Destination (Join-Path $stagedSkill 'references/customizer-attributes.md')
[ordered]@{
    schema_version = 1
    source_revision = $sourceRevision
    canonical_document = $canonicalRelative
    document_sha256 = $documentHash
    control_manifest_sha256 = $manifestHash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stagedSkill 'references/bundle-source.json') -Encoding utf8NoBOM
if ((Read-SourceGit @('rev-parse','HEAD')) -ne $sourceRevision -or
    (Read-SourceGit @('status','--porcelain','--',$canonicalRelative)) -or
    (Get-FileHash -LiteralPath $canonical).Hash -ne $documentHash -or
    (Get-FileHash -LiteralPath $manifest).Hash -ne $manifestHash) { throw 'Inputs changed during companion staging.' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
Compress-Archive -LiteralPath $stagedSkill -DestinationPath $destination
if (!(Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'Companion archive was not created.' }
Assert-SkillSnapshot $frozenSkill
[pscustomobject][ordered]@{
    path = $destination
    sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    source_revision = $sourceRevision
    document_sha256 = $documentHash
    control_manifest_sha256 = $manifestHash
}
