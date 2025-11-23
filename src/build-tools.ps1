#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration,
    [Parameter(Mandatory=$False)][string]$dotnetcodegencsTargetFrameworks="net8"
)

$ErrorActionPreference="Stop"

# CLI tool (dotnet-codegencs)
# How to run: .\build-tools.ps1   or   .\build-tools.ps1 -configuration Debug

. $script:PSScriptRoot\build-include.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

try {

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

# Use script:PSScriptRoot from build-include.ps1 (which forces symlink path on Linux)
$packagesPath = Join-Path $script:PSScriptRoot "packages-local"

# TemplateBuilder
dotnet restore .\Tools\TemplateBuilder\CodegenCS.Tools.TemplateBuilder.csproj
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\Tools\TemplateBuilder\CodegenCS.Tools.TemplateBuilder.csproj", "/t:Restore", "/t:Build"
$build_args += "/p:Configuration=$configuration", "/p:IncludeSymbols=true"
$build_args += "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

# TemplateLauncher
dotnet restore .\Tools\TemplateLauncher\CodegenCS.Tools.TemplateLauncher.csproj
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\Tools\TemplateLauncher\CodegenCS.Tools.TemplateLauncher.csproj", "/t:Restore", "/t:Build"
$build_args += "/p:Configuration=$configuration", "/p:IncludeSymbols=true"
$build_args += "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

# TemplateDownloader
dotnet restore .\Tools\TemplateDownloader\CodegenCS.Tools.TemplateDownloader.csproj
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\Tools\TemplateDownloader\CodegenCS.Tools.TemplateDownloader.csproj", "/t:Restore", "/t:Build"
$build_args += "/p:Configuration=$configuration", "/p:IncludeSymbols=true"
$build_args += "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

# dotnet-codegencs (DotnetTool nupkg/snupkg)
dotnet restore ".\Tools\dotnet-codegencs\dotnet-codegencs.csproj"
if ($dotnetcodegencsTargetFrameworks.IndexOf(";") -eq -1) {
    # single target
    $maxVer = $dotnetcodegencsTargetFrameworks.Substring($dotnetcodegencsTargetFrameworks.Length-1)
    $build_args = @()
    if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
    $build_args += ".\Tools\dotnet-codegencs\dotnet-codegencs.csproj", "/t:Restore", "/t:Build", "/t:Pack"
    $build_args += "/p:PackageOutputPath=$packagesPath", "/p:targetFrameworks=$dotnetcodegencsTargetFrameworks"
    $build_args += "/p:Configuration=$configuration", "/p:NETCoreAppMaximumVersion=$maxVer"
    $build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
    & $msbuild @build_args
    if (! $?) { throw "msbuild failed" }
} else {
    # release is multitarget - build for all "net6.0;net7.0;net8.0"
    $build_args = @()
    if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
    $build_args += ".\Tools\dotnet-codegencs\dotnet-codegencs.csproj", "/t:Restore", "/t:Build", "/t:Pack"
    $build_args += "/p:PackageOutputPath=$packagesPath", '/p:targetFrameworks="net6.0;net7.0;net8.0"'
    $build_args += "/p:Configuration=$configuration", "/p:IncludeSymbols=true"
    $build_args += "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
    & $msbuild @build_args
    if (! $?) { throw "msbuild failed" }
}

# Global tool (like all other nuget packages) will be in .\packages-local\

# uninstall/reinstall global tool from local dotnet-codegencs.*.nupkg:
dotnet tool uninstall -g dotnet-codegencs
dotnet tool install --global --add-source .\packages-local --no-cache dotnet-codegencs
# Cross-platform path to dotnet tools
if ($script:isWindowsPlatform) {
	$codegencs = Join-Path $env:USERPROFILE ".dotnet\tools\dotnet-codegencs.exe"
} else {
	$codegencs = Join-Path $env:HOME ".dotnet/tools/dotnet-codegencs"
}
if (Test-Path $codegencs) {
	& $codegencs --version
} else {
	Write-Warning "dotnet-codegencs not found at: $codegencs"
	dotnet-codegencs --version
}

} finally {
	Pop-Location
}
