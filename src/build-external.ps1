#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

$ErrorActionPreference="Stop"

# How to run: .\build-external.ps1   or   .\build-external.ps1 -configuration Debug

. $script:PSScriptRoot\build-include.ps1

# Use script:PSScriptRoot from build-include.ps1 (which forces symlink path on Linux)
Push-Location $script:PSScriptRoot

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

# Create workspace temp directory for cross-platform compatibility
$workspaceTempPath = Join-Path $script:PSScriptRoot ".tmp"
New-Item -ItemType Directory -Force -Path $workspaceTempPath -ErrorAction Ignore | Out-Null
# Set TMPDIR (standard Unix environment variable for temp directory) which .NET Core/5+ respects
if (-not $script:isWindowsPlatform) {
    # Resolve to absolute path so it works even when we Push-Location to submodules
    $env:TMPDIR = (Resolve-Path $workspaceTempPath).Path
    Write-Host "Using workspace temp directory: $($env:TMPDIR)" -ForegroundColor Cyan
}

New-Item -ItemType Directory -Force -Path ".\packages-local"

git submodule init
git pull --recurse-submodules
git submodule update --remote --recursive

Push-Location External/command-line-api/
try {
	git checkout main

	# Cross-platform NuGet packages cleanup
	if ($script:isWindowsPlatform) {
		Remove-Item -Recurse "$env:USERPROFILE\.nuget\packages\System.CommandLine*" -Force -ErrorAction Ignore
	} else {
		Remove-Item -Recurse "$env:HOME/.nuget/packages/System.CommandLine*" -Force -ErrorAction Ignore
	}

	dotnet clean

	dotnet pack /p:PackageVersion=2.0.0-codegencs -c $configuration
	if (! $?) { throw "dotnet pack failed" }

	# Use Join-Path for cross-platform path handling
	$artifactsShipping = Join-Path "artifacts" "packages" $configuration "Shipping"
	$packagesLocal = Join-Path ".." ".." "packages-local"

	Copy-Item (Join-Path $artifactsShipping "System.CommandLine.2.0.0-codegencs.nupkg") $packagesLocal
	Copy-Item (Join-Path $artifactsShipping "System.CommandLine.2.0.0-codegencs.snupkg") $packagesLocal
	Copy-Item (Join-Path $artifactsShipping "System.CommandLine.NamingConventionBinder.2.0.0-codegencs.nupkg") $packagesLocal
	Copy-Item (Join-Path $artifactsShipping "System.CommandLine.NamingConventionBinder.2.0.0-codegencs.snupkg") $packagesLocal

} finally {
	Pop-Location
}

Pop-Location
