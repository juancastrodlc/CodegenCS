#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

$ErrorActionPreference="Stop"

$version = "3.5.2"

# Source Generator(CodegenCS.SourceGenerator)
# How to run: .\build-sourcegenerator.ps1

. $script:PSScriptRoot\build-include.ps1

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
	$packagesLocalPath = Join-Path $script:PSScriptRoot "packages-local"

	# Cross-platform NuGet package cache cleanup
	if ($script:isWindowsPlatform) {
		$nugetPackagesPath = Join-Path "$env:HOMEDRIVE$env:HOMEPATH" ".nuget\packages\codegencs.sourcegenerator"
	} else {
		$nugetPackagesPath = Join-Path $env:HOME ".nuget/packages/codegencs.sourcegenerator"
	}
	Remove-Item -Recurse -Force -ErrorAction Ignore $nugetPackagesPath

# CompilerServer: server failed - server rejected the request due to analyzer / generator issues 'analyzer assembly '<source>\CodegenCS\src\SourceGenerator\CodegenCS.SourceGenerator\bin\Release\netstandard2.0\CodegenCS.SourceGenerator.dll'
# has MVID '<someguid>' but loaded assembly 'C:\Users\<user>\AppData\Local\Temp\VBCSCompiler\AnalyzerAssemblyLoader\<randompath>\CodegenCS.SourceGenerator.dll' has MVID '<otherguid>'' - SampleProjectWithSourceGenerator (netstandard2.0)

	# Set up workspace temp directory on Linux to avoid permission issues
	if (-not $script:isWindowsPlatform) {
		$workspaceTempPath = Join-Path $script:PSScriptRoot ".tmp"
		if (-not (Test-Path $workspaceTempPath)) {
			New-Item -ItemType Directory -Path $workspaceTempPath | Out-Null
		}
		$env:TMPDIR = $workspaceTempPath
	}

	gci $env:TEMP -r -filter CodegenCS.SourceGenerator.dll -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore
	if ($script:isWindowsPlatform) {
		gci "$($env:TEMP)\VBCSCompiler\AnalyzerAssemblyLoader" -r -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore
	}

	# Unfortunately Roslyn Analyzers, Source Generators, and MS Build Tasks they all have terrible support for referencing other assemblies without having those added (and conflicting) to the client project
	# To get a Nupkg with SourceLink/Deterministic PDB we have to embed the extract the PDBs from their symbol packages so we can embed them into our published package

	$symbolsDir = Join-Path $script:PSScriptRoot "ExternalSymbolsToEmbed"
	New-Item -ItemType Directory -Path $symbolsDir -ErrorAction SilentlyContinue | Out-Null
	$snupkgs = @(
		"interpolatedcolorconsole.1.0.3.snupkg",
		"newtonsoft.json.13.0.3.snupkg",
		"nswag.core.14.0.7.snupkg",
		"nswag.core.yaml.14.0.7.snupkg",
		"njsonschema.11.0.0.snupkg",
		"njsonschema.annotations.11.0.0.snupkg"
	)

	foreach ($snupkg in $snupkgs){
	    Write-Host $snupkg
	    $snupkgPath = Join-Path $symbolsDir $snupkg
	    if (-not (Test-Path $snupkgPath)) {
	        curl "https://globalcdn.nuget.org/symbol-packages/$snupkg" -o $snupkgPath
	    }
	}
	$packagesLocalPath = Join-Path $script:PSScriptRoot "packages-local"
	$systemCommandLineSnupkg = Join-Path $packagesLocalPath "System.CommandLine.2.0.0-codegencs.snupkg"
	if (Test-Path $systemCommandLineSnupkg) {
	    Copy-Item $systemCommandLineSnupkg $symbolsDir
	}
	$systemCommandLineBinderSnupkg = Join-Path $packagesLocalPath "System.CommandLine.NamingConventionBinder.2.0.0-codegencs.snupkg"
	if (Test-Path $systemCommandLineBinderSnupkg) {
	    Copy-Item $systemCommandLineBinderSnupkg $symbolsDir
	}

	if ($7z) {
	    $snupkgs = gci (Join-Path $symbolsDir "*.snupkg")
	    foreach ($snupkg in $snupkgs){
	        $name = $snupkg.Name
	        $name = $name.Substring(0, $name.Length-7)

	        # Use cross-platform path with forward slashes for 7z
	        $snupkgFile = Join-Path $symbolsDir "$name.snupkg"
	        $snupkgFileForward = $snupkgFile -replace '\\', '/'

	        $zipContents = (& $7z l -ba -slt $snupkgFileForward | Out-String) -split"`n"
	        $zipContents | Select-String "Path = "

	        # NuGet packages are already lowercase from CDN, so we keep the original name
	        $extractPath = Join-Path $symbolsDir $name
	        New-Item -ItemType Directory -Path $extractPath -ErrorAction SilentlyContinue | Out-Null

	        $extractPathForward = $extractPath -replace '\\', '/'
	        & $7z x $snupkgFileForward "-o$extractPathForward" *.pdb -r -aoa
	    }
	} else {
	    Write-Host "WARNING: 7z not available. Skipping PDB extraction from symbol packages." -ForegroundColor Yellow
	}



	dotnet restore .\SourceGenerator\CodegenCS.SourceGenerator\CodegenCS.SourceGenerator.csproj

	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += ".\SourceGenerator\CodegenCS.SourceGenerator\CodegenCS.SourceGenerator.csproj", "/t:Restore", "/t:Build", "/t:Pack"
	$build_args += "/p:PackageOutputPath=$packagesLocalPath", "/p:Configuration=$configuration"
	$build_args += "/verbosity:minimal", "/p:IncludeSymbols=true", "/p:ContinuousIntegrationBuild=true"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

	if ($nugetPE) {
	    & $nugetPE (Join-Path $packagesLocalPath "CodegenCS.SourceGenerator.$version.nupkg")
	} else {
	    Write-Host "WARNING: NuGet Package Explorer not available (Windows-only tool). Skipping package inspection." -ForegroundColor Yellow
	}

	# Build SourceGenerator test project (CodegenCS.SourceGenerator.Tests) to ensure it stays in sync
	Write-Host "Building CodegenCS.SourceGenerator.Tests..." -ForegroundColor Yellow
	dotnet restore ./SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj

	$sgTestsBuildArgs = @()
	if ($msbuild -eq "dotnet") { $sgTestsBuildArgs += "msbuild" }
	$sgTestsBuildArgs += "./SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj", "/t:Restore", "/t:Build"
	$sgTestsBuildArgs += "/p:Configuration=$configuration", "/verbosity:minimal"
	& $msbuild @sgTestsBuildArgs
	if (! $?) { throw "msbuild failed (CodegenCS.SourceGenerator.Tests)" }

	# Optional: run tests (kept minimal, skip if you only need build validation)
	Write-Host "Running SourceGenerator tests..." -ForegroundColor Yellow
	dotnet test ./SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj -c $configuration --no-build --verbosity minimal
	if (! $?) { throw "tests failed (CodegenCS.SourceGenerator.Tests)" }

	if ($7z) {
	    $nupkgPath = Join-Path $packagesLocalPath "CodegenCS.SourceGenerator.$version.nupkg"
	    $nupkgPathForward = $nupkgPath -replace '\\', '/'

	    if ($script:isWindowsPlatform) {
	        $zipContents = (& $7z l -ba -slt $nupkgPathForward | Out-String) -split"`n"
	    } else {
	        $zipContents = (& $7z l $nupkgPathForward | Out-String) -split"`n"
	    }

	    Write-Host "------------" -ForegroundColor Yellow
	    $zipContents|Select-String "Path ="
	    Start-Sleep -Seconds 2

	    # sanity check: nupkg should have debug-build dlls, pdb files, source files, etc.
	    if ($script:isWindowsPlatform) {
	        if (-not ($zipContents|Select-String "Path = "|Select-String "CodegenCS.Core.dll")) { throw "msbuild failed" }
	        if (-not ($zipContents|Select-String "Path = "|Select-String "CodegenCS.Core.pdb") -and $configuration -eq "Debug") { throw "msbuild failed" }
	    } else {
	        # On Linux, 7z output format is different - just check for the file names
	        if (-not ($zipContents|Select-String "CodegenCS.Core.dll")) { throw "msbuild failed" }
	        if (-not ($zipContents|Select-String "CodegenCS.Core.pdb") -and $configuration -eq "Debug") { throw "msbuild failed" }
	    }
	}


	# SourceGenerator1 test - run on all platforms to catch C# path handling bugs
	#dotnet clean ..\Samples\SourceGenerator1\SourceGenerator1.csproj
	dotnet restore ..\Samples\SourceGenerator1\SourceGenerator1.csproj

	$build_args = @()
	if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
	$build_args += "..\Samples\SourceGenerator1\SourceGenerator1.csproj", "/t:Restore", "/t:Rebuild"
	$build_args += "/p:Configuration=$configuration", "/verbosity:normal"
	& $msbuild @build_args
	if (! $?) { throw "msbuild failed" }

	Write-Host "------------" -ForegroundColor Yellow
	if ($decompiler) {
	    if ($decompilerType -eq "dnspy") {
	        & $decompiler ..\Samples\SourceGenerator1\bin\$configuration\netstandard2.0\SourceGenerator1.dll -t MyFirstClass
	        & $decompiler ..\Samples\SourceGenerator1\bin\$configuration\netstandard2.0\SourceGenerator1.dll -t AnotherSampleClass # should show some methods that were generated on the fly
	        if (! $?) { throw "Template failed (classes were not added to the compilation)" }
	    } elseif ($decompilerType -eq "ilspy") {
	        Write-Host "Decompiling with ILSpy..." -ForegroundColor Cyan
	        & $decompiler ../Samples/SourceGenerator1/bin/$configuration/netstandard2.0/SourceGenerator1.dll -t MyFirstClass 2>&1 | Write-Output
	        & $decompiler ../Samples/SourceGenerator1/bin/$configuration/netstandard2.0/SourceGenerator1.dll -t AnotherSampleClass 2>&1 | Write-Output
	    }
	} else {
		Write-Host "WARNING: Decompiler not available. Install ilspycmd with: dotnet tool install -g ilspycmd" -ForegroundColor Yellow
	}

} finally {
	Pop-Location
}