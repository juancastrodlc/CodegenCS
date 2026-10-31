#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration,
    [string[]]$Source = @(),
    [switch]$SkipSampleBuild = $false
)

$ErrorActionPreference="Stop"

$version = "3.5.2"

# Source Generator (CodegenCS.SourceGenerator)
# How to run: .\build-sourcegenerator.ps1
#
# The package contains two builds of the generator:
#   analyzers/dotnet/roslyn5.9/cs - netstandard2.0, compiled against the Microsoft.CodeAnalysis package (portable, for compilers >= 5.9)
#   analyzers/dotnet/roslynX.Y/cs - compiled against the Roslyn shipped with the .NET SDK running this build
# The .NET SDK picks the folder that matches the compiler (CompilerApiVersion), so the generator is never rejected with CS9057.

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1") -Source $Source

$nugetGlobal = Get-NuGetGlobalPackagesFolder
Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $nugetGlobal "codegencs.sourcegenerator")

# The compiler server caches analyzers: stop it so the freshly built generator is loaded.
& dotnet build-server shutdown | Out-Null
$tempDir = if ($IsWindows) { $env:TEMP } else { ($env:TMPDIR ? $env:TMPDIR : "/tmp") }
Get-ChildItem (Join-Path $tempDir "VBCSCompiler/AnalyzerAssemblyLoader") -Recurse -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

try {

	Get-ChildItem (Join-Path $dir "packages-local") -Filter "CodegenCS.SourceGenerator.*nupkg" -ErrorAction Ignore | Remove-Item -Force -ErrorAction Ignore

	$sg = Join-Path $dir "SourceGenerator/CodegenCS.SourceGenerator/CodegenCS.SourceGenerator.csproj"
	dotnet restore $sg @global:nugetSourceArguments -p:Configuration=$configuration
	if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed (exit code $LASTEXITCODE)" }
	Invoke-MSBuild $sg `
		/t:Build /t:Pack `
		"/p:PackageOutputPath=$(Join-Path $dir packages-local)" `
		/p:Configuration=$configuration `
		/verbosity:minimal `
		/p:IncludeSymbols=true `
		/p:ContinuousIntegrationBuild=true

	$nupkg = Join-Path $dir "packages-local/CodegenCS.SourceGenerator.$version.nupkg"
	if (-not (Test-Path $nupkg)) { throw "Package $nupkg was not created" }
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$zip = [System.IO.Compression.ZipFile]::OpenRead($nupkg)
	try {
		$analyzers = @($zip.Entries | Where-Object { $_.FullName -like "analyzers/dotnet/*/cs/CodegenCS.SourceGenerator.dll" } | ForEach-Object { $_.FullName })
	} finally {
		$zip.Dispose()
	}
	if ($analyzers.Count -eq 0) { throw "Package $nupkg does not contain the source generator" }
	Write-Host "Packed generator builds:" -ForegroundColor DarkGray
	$analyzers | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

	# Sanity check: compile the samples that consume the package with the real SDK compiler.
	if (-not $SkipSampleBuild) {
		& (Join-Path $dir "build-samples.ps1") -Configuration $configuration -Source $Source -SkipPack -Projects "SourceGenerator1","SourceGenerator2"
	}

} finally {
	Pop-Location
}
