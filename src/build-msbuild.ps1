#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

$ErrorActionPreference="Stop"

$version = "3.5.2"

# MSBuild Task (CodegenCS.MSBuild)
# How to run: .\build-msbuild.ps1

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1")

$nugetGlobal = Get-NuGetGlobalPackagesFolder
Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $nugetGlobal "codegencs.msbuild")

$tempDir = if ($IsWindows) { $env:TEMP } else { ($env:TMPDIR ? $env:TMPDIR : "/tmp") }
Get-ChildItem $tempDir -Recurse -Filter CodegenCS.MSBuild.dll -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore
Get-ChildItem (Join-Path $dir "packages") -Filter "CodegenCS.MSBuild.*" -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

try {

	# Embed PDBs from symbol packages (see build-sourcegenerator.ps1 for the rationale).
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

	$mb = Join-Path $dir "MSBuild/CodegenCS.MSBuild/CodegenCS.MSBuild.csproj"
	dotnet restore $mb
	Invoke-MSBuild $mb `
		/t:Restore /t:Build /t:Pack `
		"/p:PackageOutputPath=$(Join-Path $dir packages-local)" `
		/p:Configuration=$configuration `
		/verbosity:minimal `
		/p:IncludeSymbols=true `
		/p:ContinuousIntegrationBuild=true

	# Sanity test: SDK-style project consuming the MSBuild task via "dotnet build" (cross-platform).
	$sample = Join-Path $dir "../Samples/MSBuild1/MSBuild1.csproj"
	if (Test-Path $sample) {
		Get-ChildItem (Join-Path $dir "../Samples/MSBuild1") -Filter *.g.cs -ErrorAction Ignore | Remove-Item -Force -ErrorAction Ignore
		Get-ChildItem (Join-Path $dir "../Samples/MSBuild1") -Filter *.generated.cs -ErrorAction Ignore | Remove-Item -Force -ErrorAction Ignore
		dotnet restore $sample
		& dotnet build $sample /t:Restore /t:Rebuild /p:Configuration=$configuration /verbosity:normal
		if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
		if (-not (Get-ChildItem (Join-Path $dir "../Samples/MSBuild1") -Filter *.g.cs -ErrorAction Ignore)) {
			throw "Template failed (classes were not added to the compilation)"
		}
	}

	# The non-SDK Microsoft Framework Web Application sample (Samples/MSBuild2) requires
	# .NET Framework msbuild.exe + nuget.exe and is Windows-only. Skip elsewhere.
	if ($IsWindows -and $global:msbuildExe) {
		$webApp = Join-Path $dir "../Samples/MSBuild2/WebApplication.csproj"
		if (Test-Path $webApp) {
			Get-ChildItem (Join-Path $dir "../Samples/MSBuild2") -Filter *.g.cs -ErrorAction Ignore | Remove-Item -Force -ErrorAction Ignore
			Get-ChildItem (Join-Path $dir "../Samples/MSBuild2") -Filter *.generated.cs -ErrorAction Ignore | Remove-Item -Force -ErrorAction Ignore
			$nugetExe = Join-Path $dir "nuget.exe"
			if (Test-Path $nugetExe) {
				& $nugetExe restore -PackagesDirectory (Join-Path $dir "packages") $webApp
			}
			Invoke-MSBuild $webApp /t:Restore /t:Rebuild /p:Configuration=$configuration /verbosity:normal
			if (-not (Get-ChildItem (Join-Path $dir "../Samples/MSBuild2") -Filter *.g.cs -ErrorAction Ignore)) {
				throw "Template failed (classes were not added to the compilation)"
			}
		}
	} else {
		Write-Host "Skipping non-SDK WebApplication sample (Windows/.NET Framework only)." -ForegroundColor DarkGray
	}

} finally {
	Pop-Location
}
