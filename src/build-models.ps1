#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# How to run: .\build-models.ps1   or   .\build-models.ps1 -configuration Debug

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1")

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

try {

	$packOutput = Join-Path $dir "packages-local"

	# CodegenCS.Models.DbSchema + nupkg/snupkg
	$p = Join-Path $dir "Models/CodegenCS.Models.DbSchema/CodegenCS.Models.DbSchema.csproj"
	dotnet restore $p
	Invoke-MSBuild $p `
		/t:Restore /t:Build /t:Pack `
		/p:PackageOutputPath=$packOutput `
		/p:Configuration=$configuration `
		/p:IncludeSymbols=true `
		/verbosity:minimal `
		/p:ContinuousIntegrationBuild=true

	# CodegenCS.Models.DbSchema.Extractor (build only)
	$p = Join-Path $dir "Models/CodegenCS.Models.DbSchema.Extractor/CodegenCS.Models.DbSchema.Extractor.csproj"
	dotnet restore $p
	Invoke-MSBuild $p `
		/t:Restore /t:Build `
		/p:Configuration=$configuration `
		/p:IncludeSymbols=true `
		/verbosity:minimal `
		/p:ContinuousIntegrationBuild=true

	# CodegenCS.Models.NSwagAdapter + nupkg/snupkg
	$p = Join-Path $dir "Models/CodegenCS.Models.NSwagAdapter/CodegenCS.Models.NSwagAdapter.csproj"
	dotnet restore $p
	Invoke-MSBuild $p `
		/t:Restore /t:Build /t:Pack `
		/p:PackageOutputPath=$packOutput `
		/p:Configuration=$configuration `
		/p:IncludeSymbols=true `
		/verbosity:minimal `
		/p:ContinuousIntegrationBuild=true

} finally {
	Pop-Location
}
