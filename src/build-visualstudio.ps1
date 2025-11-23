#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

$ErrorActionPreference="Stop"

# Visual Studio Extensions
# How to run: .\build-visualstudio.ps1   or   .\build-visualstudio.ps1 -configuration Debug


. $script:PSScriptRoot\build-include.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	#if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
	$configuration = "Debug"
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

# Visual Studio extensions are Windows-only
if (-not $script:isWindowsPlatform) {
    Write-Host "Skipping Visual Studio extension build (Windows-only - requires Visual Studio SDK)" -ForegroundColor Yellow
    Pop-Location
    exit 0
}

try {

	# This component is hard to debug (fragile dependencies) so it's better to clean on each build
	Get-ChildItem .\VisualStudio\ -Recurse | Where{$_.FullName -CMatch ".*\\bin$" -and $_.PSIsContainer} | Remove-Item -Recurse -Force -ErrorAction Ignore
	Get-ChildItem .\VisualStudio\ -Recurse | Where{$_.FullName -CMatch ".*\\obj$" -and $_.PSIsContainer} | Remove-Item -Recurse -Force -ErrorAction Ignore
	Get-ChildItem .\VisualStudio\ -Recurse | Where{$_.FullName -Match ".*\\obj\\.*project.assets.json$"} | Remove-Item


	# CodegenCS.Runtime.VisualStudio
	dotnet restore ".\VisualStudio\CodegenCS.Runtime.VisualStudio\CodegenCS.Runtime.VisualStudio.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\VisualStudio\CodegenCS.Runtime.VisualStudio\CodegenCS.Runtime.VisualStudio.csproj", "/t:Restore", "/t:Build"
	$build_args += "/p:Configuration=$configuration", "/p:IncludeSymbols=true"
	$build_args += "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

	dotnet restore ".\VisualStudio\VS2022Extension\VS2022Extension.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\VisualStudio\VS2022Extension\VS2022Extension.csproj", "/t:Restore", "/t:Build"
	$build_args += "/p:Configuration=$configuration"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }
	$packagesLocalPath = Join-Path $script:PSScriptRoot "packages-local"
	Copy-Item ".\VisualStudio\VS2022Extension\bin\$configuration\CodegenCS.VisualStudio.VS2022Extension.vsix" $packagesLocalPath

	dotnet restore ".\VisualStudio\VS2019Extension\VS2019Extension.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\VisualStudio\VS2019Extension\VS2019Extension.csproj", "/t:Restore", "/t:Build"
	$build_args += "/p:Configuration=$configuration"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }
	Copy-Item ".\VisualStudio\VS2019Extension\bin\$configuration\CodegenCS.VisualStudio.VS2019Extension.vsix" $packagesLocalPath	# The secret to VSIX painless-troubleshooting is inspecting the VSIX package:
	# & "C:\Program Files\7-Zip\7zFM.exe" .\VisualStudio\VS2022Extension\bin\Debug\CodegenCS.VSExtensions.VisualStudio2022.vsix
	# Sometimes command-line shows errors that Visual Studio ignores
	# Sometimes in the extension folder we will have ZERO-bytes files



} finally {
    Pop-Location
}
