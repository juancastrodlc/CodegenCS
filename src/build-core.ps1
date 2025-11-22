#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# How to run:
# .\build-core.ps1
# or
# .\build-core.ps1 -configuration Debug


. .\build-include.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow


try {
	# Use script:PSScriptRoot from build-include.ps1 (which forces symlink path on Linux)
	$packagesPath = Join-Path $script:PSScriptRoot "packages-local"

	# CodegenCS.Core + nupkg/snupkg
	dotnet restore ".\Core\CodegenCS\CodegenCS.Core.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\Core\CodegenCS\CodegenCS.Core.csproj", "/t:Restore", "/t:Build", "/t:Pack"
	$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
	$build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

	# CodegenCS.Models + nupkg/snupkg
	dotnet restore ".\Core\CodegenCS.Models\CodegenCS.Models.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\Core\CodegenCS.Models\CodegenCS.Models.csproj", "/t:Restore", "/t:Build", "/t:Pack"
	$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
	$build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

	# CodegenCS.Runtime + nupkg/snupkg
	dotnet restore ".\Core\CodegenCS.Runtime\CodegenCS.Runtime.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\Core\CodegenCS.Runtime\CodegenCS.Runtime.csproj", "/t:Restore", "/t:Build", "/t:Pack"
	$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
	$build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

	# CodegenCS.DotNet + nupkg/snupkg
	dotnet restore ".\Core\CodegenCS.DotNet\CodegenCS.DotNet.csproj"
	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\Core\CodegenCS.DotNet\CodegenCS.DotNet.csproj", "/t:Restore", "/t:Build", "/t:Pack"
	$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
	$build_args += "/p:IncludeSymbols=true", "/verbosity:minimal", "/p:ContinuousIntegrationBuild=true"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

} finally {
    Pop-Location
}
