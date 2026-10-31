#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration,
    [string[]]$Source = @(),
    # Reuse the CodegenCS.SourceGenerator package already in packages-local instead of packing it again.
    [switch]$SkipPack = $false,
    # Sample folders to build (e.g. "SourceGenerator1","SourceGenerator2"). Default: every project in Samples/Samples.slnx
    [string[]]$Projects
)

# Compiles the samples (../Samples/Samples.slnx) against the locally built packages.
# How to run:
#   Windows: .\build-samples.ps1
#   Linux/macOS: pwsh ./build-samples.ps1 [-configuration Debug] [-SkipPack] [-Projects SourceGenerator1,SourceGenerator2]

$ErrorActionPreference = "Stop"

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$samplesDir = [System.IO.Path]::GetFullPath((Join-Path $dir "../Samples"))
Push-Location $dir

. (Join-Path $dir "build-include.ps1") -Source $Source

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

$generatorFailures = 'CS9057|CS8032|CS8033|CS8034|CS8784|CS8785|CODEGENCS\d+'

try {
	$version = "3.5.2"
	$nupkg = Join-Path $dir "packages-local/CodegenCS.SourceGenerator.$version.nupkg"
	if (-not $SkipPack -or -not (Test-Path $nupkg)) {
		& (Join-Path $dir "build-sourcegenerator.ps1") -Configuration $configuration -Source $Source -SkipSampleBuild
	}

	# Make sure the samples restore the package that was just built (and not a stale copy).
	$nugetGlobal = Get-NuGetGlobalPackagesFolder
	Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $nugetGlobal "codegencs.sourcegenerator")
	& dotnet build-server shutdown | Out-Null

	if ($Projects) {
		$targets = @($Projects | ForEach-Object { Join-Path $samplesDir "$_/$_.csproj" })
	} else {
		$targets = @(Join-Path $samplesDir "Samples.slnx")
	}
	$targetNames = @($targets | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
	$buildsAll = $targetNames -contains "Samples"

	if ($buildsAll -or $targetNames -contains "PrebuildEvent") {
		$codegencs = Get-DotnetToolsPath
		if (-not (Test-Path $codegencs)) {
			throw "Samples/PrebuildEvent requires the dotnet-codegencs global tool. Run .\build-tools.ps1 first (or build only the source generator samples with -Projects SourceGenerator1,SourceGenerator2)."
		}
	}

	# Template1.csx uses CodegenCSOutput="File": delete its output so we verify a clean build generates it again.
	Remove-Item -Force -ErrorAction Ignore (Join-Path $samplesDir "SourceGenerator1/Template1.g.cs")

	foreach ($target in $targets) {
		Write-Host "Building $target..." -ForegroundColor Cyan
		& dotnet restore $target @global:nugetSourceArguments
		if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed for $target (exit code $LASTEXITCODE)" }

		$log = & dotnet build $target --no-restore --no-incremental -c $configuration -v:minimal 2>&1 | Tee-Object -Variable buildLog
		$log | Out-Host
		if ($LASTEXITCODE -ne 0) { throw "dotnet build failed for $target (exit code $LASTEXITCODE)" }
		$failures = @($buildLog | Where-Object { "$_" -match $generatorFailures })
		if ($failures.Count -gt 0) {
			throw "The source generator did not run correctly for ${target}:`n$($failures -join "`n")"
		}
	}

	if ($buildsAll -or $targetNames -contains "SourceGenerator1") {
		$fileOutput = Join-Path $samplesDir "SourceGenerator1/Template1.g.cs"
		if (-not (Test-Path $fileOutput)) { throw "Template1.csx output ($fileOutput) was not generated" }
		Write-Host "SourceGenerator1: generated $fileOutput" -ForegroundColor Green
	}

	if ($buildsAll -or $targetNames -contains "SourceGenerator2") {
		$dll = Join-Path $samplesDir "SourceGenerator2/bin/$configuration/net8.0/SourceGenerator2.dll"
		Write-Host "Running $dll..." -ForegroundColor Cyan
		& dotnet $dll
		if ($LASTEXITCODE -ne 0) { throw "SourceGenerator2 sample failed (exit code $LASTEXITCODE)" }
	}

	Write-Host "Samples successfully built." -ForegroundColor Green

} finally {
	Pop-Location
}
