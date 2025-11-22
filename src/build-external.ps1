#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# How to run: .\build-external.ps1   or   .\build-external.ps1 -configuration Debug

. .\build-include.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

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
