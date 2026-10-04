#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildProfile,
    [Parameter(Mandatory)][string]$DependencyPrefix
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot/Common.ps1"
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$directory = Join-Path $workspace "runs/tool-tests/qt-$([guid]::NewGuid().ToString('N'))"
$staging = Join-Path $directory 'staging'
Assert-ChildPath $directory (Join-Path $workspace 'runs')
New-Item -ItemType Directory $directory,$staging | Out-Null
$script:LogPath = Join-Path $directory 'test.log'
$script:CommandRecords = [Collections.Generic.List[object]]::new()
$p = Get-Content -LiteralPath $BuildProfile -Raw | ConvertFrom-Json -AsHashtable
Import-Module (Join-Path $p.visualStudio 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $p.visualStudio -Arch amd64 -HostArch amd64 -SkipAutomaticLocation `
    -DevCmdArguments "-vcvars_ver=$($p.toolset) -winsdk=$($p.sdk)" | Out-Null
$compiler = Join-Path $env:VCToolsInstallDir 'bin/Hostx64/x64/cl.exe'
@'
#include <QtWidgets/QApplication>
#include <QtCore/QDir>
#include <QtCore/QLibraryInfo>
#include <QtCore/QDebug>
#include <QtGui/QImage>
#include <QtGui/QPainter>
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    const auto plugins = QDir(QLibraryInfo::path(QLibraryInfo::PluginsPath)).canonicalPath();
    const auto application = QDir(QCoreApplication::applicationDirPath()).canonicalPath();
    qInfo() << "Platform:" << app.platformName() << "Plugins:" << plugins;
    if (plugins.compare(application, Qt::CaseInsensitive) != 0 || app.platformName() != "windows") return 2;
    QImage image(320, 80, QImage::Format_ARGB32);
    image.fill(Qt::white);
    { QPainter painter(&image); painter.setPen(Qt::black); painter.drawText(image.rect(), Qt::AlignCenter, "Qt deployment check"); }
    return image.save(QCoreApplication::applicationDirPath() + "/qt-probe.png") ? 0 : 3;
}
'@ | Set-Content (Join-Path $directory 'probe.cc') -Encoding ascii
$oldPath = $env:PATH
$oldPluginPath = $env:QT_PLUGIN_PATH
$oldQpaPath = $env:QT_QPA_PLATFORM_PLUGIN_PATH
$oldQpa = $env:QT_QPA_PLATFORM
Push-Location $directory
try {
    Invoke-Logged $compiler @('/nologo','/MD','/EHsc','/std:c++17','/Zc:__cplusplus','/permissive-',"/I$DependencyPrefix/include/Qt6",'probe.cc',
        "/Fe:$staging/scadmaxx.exe",'/link',"/LIBPATH:$DependencyPrefix/lib",'Qt6Widgets.lib','Qt6Gui.lib','Qt6Core.lib')
    Copy-QtRuntime $DependencyPrefix $staging
    Invoke-Logged $p.cmake @("-DSTAGING=$staging","-DDEPENDENCY_BIN=$DependencyPrefix/bin",'-P',"$PSScriptRoot/Deploy-Runtime.cmake")
    $env:PATH = "$env:SystemRoot/System32;$env:SystemRoot"
    $env:QT_PLUGIN_PATH = ''
    $env:QT_QPA_PLATFORM_PLUGIN_PATH = ''
    $env:QT_QPA_PLATFORM = 'windows'
    Invoke-Logged (Join-Path $staging 'scadmaxx.exe') @()
    if ((Get-Item (Join-Path $staging 'qt-probe.png')).Length -lt 100) { throw 'Qt fixture did not create its image.' }
    Save-Json (Join-Path $directory 'result.json') @{status='passed'; dependencyPrefix=$DependencyPrefix;
        checks=@('load staged Windows Qt plugin','use app-local Qt paths','render image with controlled PATH')}
    "Passed Qt deployment checks. Evidence: $directory"
} finally {
    $env:PATH = $oldPath
    $env:QT_PLUGIN_PATH = $oldPluginPath
    $env:QT_QPA_PLATFORM_PLUGIN_PATH = $oldQpaPath
    $env:QT_QPA_PLATFORM = $oldQpa
    Pop-Location
    Save-Json (Join-Path $directory 'commands.json') @($script:CommandRecords.ToArray())
}
