#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# How to run: .\build.ps1   or   .\build.ps1 -configuration Debug


. .\build-include.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

# Use script:PSScriptRoot from build-include.ps1 (which forces symlink path on Linux)
$packagesPath = Join-Path $script:PSScriptRoot "packages-local"

# CodegenCS.Models.DbSchema + nupkg/snupkg
dotnet restore ".\Models\CodegenCS.Models.DbSchema\CodegenCS.Models.DbSchema.csproj"
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\Models\CodegenCS.Models.DbSchema\CodegenCS.Models.DbSchema.csproj", "/t:Restore", "/t:Build", "/t:Pack"
$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
$build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

# CodegenCS.Models.DbSchema.Extractor (build only, no pack)
dotnet restore ".\Models\CodegenCS.Models.DbSchema.Extractor\CodegenCS.Models.DbSchema.Extractor.csproj"
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\Models\CodegenCS.Models.DbSchema.Extractor\CodegenCS.Models.DbSchema.Extractor.csproj", "/t:Restore", "/t:Build"
$build_args += "/p:Configuration=$configuration", "/p:IncludeSymbols=true"
$build_args += "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

# CodegenCS.Models.NSwagAdapter + nupkg/snupkg
dotnet restore ".\Models\CodegenCS.Models.NSwagAdapter\CodegenCS.Models.NSwagAdapter.csproj"
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\Models\CodegenCS.Models.NSwagAdapter\CodegenCS.Models.NSwagAdapter.csproj", "/t:Restore", "/t:Build", "/t:Pack"
$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
$build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

Pop-Location
