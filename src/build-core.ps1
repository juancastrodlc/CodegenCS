#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# How to run:
#   .\build-core.ps1
#   .\build-core.ps1 -configuration Debug

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

	$projects = @(
		"Core/CodegenCS/CodegenCS.Core.csproj",
		"Core/CodegenCS.Models/CodegenCS.Models.csproj",
		"Core/CodegenCS.Runtime/CodegenCS.Runtime.csproj",
		"Core/CodegenCS.DotNet/CodegenCS.DotNet.csproj"
	)

	foreach ($project in $projects) {
		$projectPath = Join-Path $dir $project
		dotnet restore $projectPath
		Invoke-MSBuild $projectPath `
			/t:Restore /t:Build /t:Pack `
			"/p:PackageOutputPath=$(Join-Path $dir packages-local)" `
			/p:Configuration=$configuration `
			/p:IncludeSymbols=true `
			/verbosity:minimal `
			/p:ContinuousIntegrationBuild=true
	}

} finally {
    Pop-Location
}
