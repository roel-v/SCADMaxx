#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BuildProfile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot/Common.ps1"
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$directory = Join-Path $workspace "runs/tool-tests/runtime-$([guid]::NewGuid().ToString('N'))"
$dependencyBin = Join-Path $directory 'dependency-bin'
$staging = Join-Path $directory 'staging'
$missing = Join-Path $directory 'missing-dependency'
$empty = Join-Path $directory 'empty-bin'
Assert-ChildPath $directory (Join-Path $workspace 'runs')
New-Item -ItemType Directory $directory,$dependencyBin,$staging,$missing,$empty | Out-Null
$script:LogPath = Join-Path $directory 'test.log'
$script:CommandRecords = [Collections.Generic.List[object]]::new()
$p = Get-Content -LiteralPath $BuildProfile -Raw | ConvertFrom-Json -AsHashtable
Import-Module (Join-Path $p.visualStudio 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $p.visualStudio -Arch amd64 -HostArch amd64 -SkipAutomaticLocation `
    -DevCmdArguments "-vcvars_ver=$($p.toolset) -winsdk=$($p.sdk)" | Out-Null
$compiler = Join-Path $env:VCToolsInstallDir 'bin/Hostx64/x64/cl.exe'
'extern "C" __declspec(dllexport) int deployment_probe() { return 42; }' |
    Set-Content (Join-Path $directory 'dependency.cc') -Encoding ascii
'extern "C" __declspec(dllimport) int deployment_probe(); int main() { return deployment_probe() == 42 ? 0 : 1; }' |
    Set-Content (Join-Path $directory 'main.cc') -Encoding ascii
Push-Location $directory
try {
    Invoke-Logged $compiler @('/nologo','/MD','/LD','dependency.cc',"/Fe:$dependencyBin/deployment-probe.dll",'/link',"/IMPLIB:$directory/deployment-probe.lib")
    Invoke-Logged $compiler @('/nologo','/MD','main.cc',"/Fe:$staging/scadmaxx.exe",'/link',"$directory/deployment-probe.lib")
    Invoke-Logged $p.cmake @("-DSTAGING=$staging","-DDEPENDENCY_BIN=$dependencyBin",'-P',"$PSScriptRoot/Deploy-Runtime.cmake")
    if (!(Test-Path (Join-Path $staging 'deployment-probe.dll'))) { throw 'Deployment did not copy the required DLL.' }
    Invoke-Logged (Join-Path $staging 'scadmaxx.exe') @()
    Copy-Item (Join-Path $staging 'scadmaxx.exe') (Join-Path $missing 'scadmaxx.exe')
    $rejected = $false
    try {
        Invoke-Logged $p.cmake @("-DSTAGING=$missing","-DDEPENDENCY_BIN=$empty",'-P',"$PSScriptRoot/Deploy-Runtime.cmake")
    } catch {
        if ($script:CommandRecords[-1].exitCode -eq 0) { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'Deployment silently accepted a missing runtime DLL.' }
    if (!(Get-Content $script:LogPath -Raw).Contains('Unresolved runtime dependencies: deployment-probe.dll')) {
        throw 'The failure did not identify the intentionally missing DLL.'
    }
    Save-Json (Join-Path $directory 'result.json') @{status='passed'; checks=@('copy required DLL','run deployed executable','reject missing DLL')}
    "Passed runtime deployment checks. Evidence: $directory"
} finally {
    Pop-Location
    Save-Json (Join-Path $directory 'commands.json') @($script:CommandRecords.ToArray())
}
