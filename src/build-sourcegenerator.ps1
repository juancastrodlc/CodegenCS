#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

$ErrorActionPreference="Stop"

$version = "3.5.2"

# Source Generator (CodegenCS.SourceGenerator)
# How to run: .\build-sourcegenerator.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1")

$nugetGlobal = Get-NuGetGlobalPackagesFolder
Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $nugetGlobal "codegencs.sourcegenerator")

# CompilerServer MVID mismatch workaround: clear cached copies of the source generator dll.
$tempDir = if ($IsWindows) { $env:TEMP } else { ($env:TMPDIR ? $env:TMPDIR : "/tmp") }
Get-ChildItem $tempDir -Recurse -Filter CodegenCS.SourceGenerator.dll -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore
Get-ChildItem (Join-Path $tempDir "VBCSCompiler/AnalyzerAssemblyLoader") -Recurse -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

try {

	# Roslyn Analyzers / Source Generators / MSBuild Tasks have poor support for referencing other
	# assemblies. To ship a Nupkg with SourceLink/Deterministic PDBs we extract PDBs from symbol
	# packages and embed them.
	$symbolsDir = Join-Path $dir "ExternalSymbolsToEmbed"
	New-Item -ItemType Directory -Force -Path $symbolsDir | Out-Null
	$snupkgs = @(
		"interpolatedcolorconsole.1.0.3.snupkg",
		"newtonsoft.json.13.0.3.snupkg",
		"nswag.core.14.0.7.snupkg",
		"nswag.core.yaml.14.0.7.snupkg",
		"njsonschema.11.0.0.snupkg",
		"njsonschema.annotations.11.0.0.snupkg"
	)
	foreach ($snupkg in $snupkgs){
		$target = Join-Path $symbolsDir $snupkg
		if (-not (Test-Path $target)) {
			curl -L "https://globalcdn.nuget.org/symbol-packages/$snupkg" -o $target
		}
	}

	# Extract *.pdb from each snupkg (snupkg is a zip). Expand-Archive is cross-platform.
	foreach ($snupkgFile in (Get-ChildItem (Join-Path $symbolsDir "*.snupkg"))) {
		$name = $snupkgFile.BaseName
		$extractDir = Join-Path $symbolsDir $name
		New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
		$zipCopy = Join-Path $symbolsDir "$name.zip"
		Copy-Item $snupkgFile.FullName $zipCopy -Force
		try {
			Expand-Archive -Path $zipCopy -DestinationPath $extractDir -Force
		} catch {
			Write-Host "Warning: could not expand $($snupkgFile.Name): $_" -ForegroundColor Yellow
		} finally {
			Remove-Item $zipCopy -Force -ErrorAction Ignore
		}
	}

	$sg = Join-Path $dir "SourceGenerator/CodegenCS.SourceGenerator/CodegenCS.SourceGenerator.csproj"
	dotnet restore $sg
	Invoke-MSBuild $sg `
		/t:Restore /t:Build /t:Pack `
		"/p:PackageOutputPath=$(Join-Path $dir packages-local)" `
		/p:Configuration=$configuration `
		/verbosity:minimal `
		/p:IncludeSymbols=true `
		/p:ContinuousIntegrationBuild=true

	# Build the sample project that consumes the source generator as a sanity check.
	$sample = Join-Path $dir "../Samples/SourceGenerator1/SourceGenerator1.csproj"
	if (Test-Path $sample) {
		dotnet restore $sample
		Invoke-MSBuild $sample /t:Restore /t:Rebuild /p:Configuration=$configuration /verbosity:normal
	}

} finally {
	Pop-Location
}
