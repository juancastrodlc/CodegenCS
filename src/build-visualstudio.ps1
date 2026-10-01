#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# Visual Studio Extensions (VSIX)
# How to run: .\build-visualstudio.ps1   or   .\build-visualstudio.ps1 -configuration Debug

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1")

# Visual Studio extensions require the Visual Studio SDK and full msbuild.exe, which only
# exist on Windows. Skip entirely on other platforms.
if (-not $IsWindows) {
    Write-Host "Skipping Visual Studio extensions build: this is a Windows-only target." -ForegroundColor Yellow
    Pop-Location
    return
}
if (-not $global:msbuildExe) {
    Write-Host "Skipping Visual Studio extensions build: full msbuild.exe (Visual Studio) not found." -ForegroundColor Yellow
    Pop-Location
    return
}

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	$configuration = "Debug"
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

try {

	# This component is hard to debug (fragile dependencies) so it's better to clean on each build
	Get-ChildItem (Join-Path $dir "VisualStudio") -Recurse -Directory -ErrorAction Ignore |
		Where-Object { $_.Name -eq "bin" -or $_.Name -eq "obj" } |
		Remove-Item -Recurse -Force -ErrorAction Ignore

	# CodegenCS.Runtime.VisualStudio
	$p = Join-Path $dir "VisualStudio/CodegenCS.Runtime.VisualStudio/CodegenCS.Runtime.VisualStudio.csproj"
	dotnet restore $p
	Invoke-MSBuild $p `
		/t:Restore /t:Build `
		/p:Configuration=$configuration `
		/p:IncludeSymbols=true `
		/verbosity:minimal `
		/p:ContinuousIntegrationBuild=true

	$p = Join-Path $dir "VisualStudio/VS2022Extension/VS2022Extension.csproj"
	dotnet restore $p
	Invoke-MSBuild $p /t:Restore /t:Build /p:Configuration=$configuration
	Copy-Item (Join-Path $dir "VisualStudio/VS2022Extension/bin/$configuration/CodegenCS.VisualStudio.VS2022Extension.vsix") (Join-Path $dir "packages-local") -Force

	$p = Join-Path $dir "VisualStudio/VS2019Extension/VS2019Extension.csproj"
	dotnet restore $p
	Invoke-MSBuild $p /t:Restore /t:Build /p:Configuration=$configuration
	Copy-Item (Join-Path $dir "VisualStudio/VS2019Extension/bin/$configuration/CodegenCS.VisualStudio.VS2019Extension.vsix") (Join-Path $dir "packages-local") -Force

} finally {
    Pop-Location
}
