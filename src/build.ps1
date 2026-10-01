#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)]
    [ValidateSet('Release','Debug')]
    [string]$configuration="Debug",
    [switch] $RunTests = $false
)

# How to run:
#   Windows: .\build.ps1
#   Linux/macOS: pwsh ./build.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1")

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow
Write-Host ("Running on {0}" -f $(if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" })) -ForegroundColor Yellow

$ErrorActionPreference="Stop"

$dotnetSdk = (& dotnet --list-sdks | ForEach-Object { [int]($_.Substring(0, $_.IndexOf("."))) } | Sort-Object -Descending | Select-Object -First 1)
if (-not $dotnetSdk) { throw "Can't find .NET SDK" }

# .NET Framework 4.7.2 only exists on Windows (registry check). On Linux/macOS it's always absent.
$hasNet472 = $false
if ($IsWindows) {
    $hasNet472 = [bool] (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction Ignore |
        Get-ItemProperty -name Version, Release -EA 0 |
        Where-Object { $_.PSChildName -match '^(?!S)\p{L}'} |
        Select-Object @{name = "NETFramework"; expression = {$_.PSChildName}}, Version, Release |
        Where-Object { $_.NETFramework -eq "Full" -and $_.Release -gt 461814 })
}

if ($configuration -eq "Release") {
    # dotnet-codegencs is released for multiple targets; other projects are single-target.
    $dotnetcodegencsTargetFrameworks="net6.0;net7.0;net8.0"
} else {
    # For debug use the latest installed dotnet SDK.
    $dotnetcodegencsTargetFrameworks = "net$dotnetSdk.0"
}

. (Join-Path $dir "build-clean.ps1")

New-Item -ItemType Directory -Force -Path (Join-Path $dir "packages-local") | Out-Null

# NOTE: We no longer build the customized System.CommandLine "2.0.0-codegencs" fork from
# .\External\command-line-api. That dependency has been removed in favor of the public
# System.CommandLine packages already present in .\packages-local. (build-external.ps1 is
# kept only for historical Windows use and is skipped here.)

. (Join-Path $dir "build-core.ps1") -Configuration $configuration

. (Join-Path $dir "build-models.ps1") -Configuration $configuration

if ($configuration -eq "Release")
{
	# For release builds we clear bin/obj again to ensure that all further builds will use the locally published nugets
    foreach ($sub in @("Core","Models")) {
        Get-ChildItem (Join-Path $dir $sub) -Recurse -Directory -ErrorAction Ignore |
            Where-Object { $_.Name -eq "bin" -or $_.Name -eq "obj" } |
            Remove-Item -Recurse -Force -ErrorAction Ignore
    }
}

. (Join-Path $dir "build-tools.ps1") -Configuration $configuration -dotnetcodegencsTargetFrameworks $dotnetcodegencsTargetFrameworks

if ($configuration -eq "Release") {
  . (Join-Path $dir "build-sourcegenerator.ps1") -Configuration $configuration
  . (Join-Path $dir "build-msbuild.ps1") -Configuration $configuration
}

# Unit tests
if ($RunTests) {
    & (Join-Path $dir "run-tests.ps1") -Configuration $configuration
}

# Visual Studio extensions can only be built on Windows (they require the VS SDK / net472).
if ($IsWindows -and $hasNet472) {
    $env:VSToolsPath="C:\Program Files\Microsoft Visual Studio\2022\Professional\Msbuild\Microsoft\VisualStudio\v17.0"
    . (Join-Path $dir "build-visualstudio.ps1") -Configuration $configuration
} else {
    Write-Host "Skipping Visual Studio extensions build (Windows-only target)." -ForegroundColor DarkGray
}

Pop-Location
