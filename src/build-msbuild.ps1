#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

$ErrorActionPreference="Stop"

$version = "3.5.2"

# Cross-platform tool paths
if ($script:isWindowsPlatform) {
    $nugetPE = "C:\ProgramData\chocolatey\bin\NuGetPackageExplorer.exe"
    $7z = "C:\Program Files\7-Zip\7z.exe"
    $decompiler = "C:\ProgramData\chocolatey\lib\dnspyex\tools\dnSpy.Console.exe"
    $decompilerType = "dnspy"
} else {
    # On Linux, check for 7z variants (7z, 7za, 7zr) - NOT unzip (different syntax)
    $7z = (Get-Command 7z -ErrorAction SilentlyContinue).Source
    if (-not $7z) { $7z = (Get-Command 7za -ErrorAction SilentlyContinue).Source }
    if (-not $7z) { $7z = (Get-Command 7zr -ErrorAction SilentlyContinue).Source }
    if (-not $7z) {
        Write-Warning "7z not found. Install with: sudo apt-get install p7zip-full"
    }
    $nugetPE = $null
    # Check for ilspycmd (cross-platform .NET decompiler)
    if (Get-Command ilspycmd -ErrorAction SilentlyContinue) {
        $decompiler = (Get-Command ilspycmd).Source
        $decompilerType = "ilspy"
    } else {
        $decompiler = $null
        $decompilerType = $null
    }
}

# MSBuild Task (CodegenCS.MSBuild)
# How to run: .\build-msbuildtask.ps1

. $script:PSScriptRoot\build-include.ps1

# Use the symlink-aware path from build-include.ps1
Push-Location $script:PSScriptRoot

# Cross-platform NuGet packages cleanup
if ($script:isWindowsPlatform) {
    Remove-Item -Recurse -Force -ErrorAction Ignore "$env:USERPROFILE\.nuget\packages\codegencs.msbuild"
} else {
    Remove-Item -Recurse -Force -ErrorAction Ignore "$env:HOME/.nuget/packages/codegencs.msbuild"
}
gci $env:TEMP -r -filter CodegenCS.MSBuild.dll -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore
#gci "$($env:TEMP)\VBCSCompiler\AnalyzerAssemblyLoader" -r -ErrorAction Ignore | Remove-Item -Force -Recurse -ErrorAction Ignore
if (Test-Path .\packages\) { gci .\packages\ -filter CodegenCS.MSBuild.* | Remove-Item -Force -Recurse -ErrorAction Ignore }

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path Release.snk) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

# Create workspace temp directory for cross-platform compatibility
$workspaceTempPath = Join-Path $script:PSScriptRoot ".tmp"
New-Item -ItemType Directory -Force -Path $workspaceTempPath -ErrorAction Ignore | Out-Null
# Set TMPDIR (standard Unix environment variable for temp directory) which .NET Core/5+ respects
if (-not $script:isWindowsPlatform) {
    $env:TMPDIR = $workspaceTempPath
    Write-Host "Using workspace temp directory: $workspaceTempPath" -ForegroundColor Cyan
}

# Unfortunately Roslyn Analyzers, Source Generators, and MS Build Tasks they all have terrible support for referencing other assemblies without having those added (and conflicting) to the client project
# To get a Nupkg with SourceLink/Deterministic PDB we have to embed the extract the PDBs from their symbol packages so we can embed them into our published package

New-Item -ItemType Directory -Force -Path .\ExternalSymbolsToEmbed -ErrorAction Ignore | Out-Null
$snupkgs = @(
    "interpolatedcolorconsole.1.0.3.snupkg",
    "newtonsoft.json.13.0.3.snupkg",
    "nswag.core.14.0.7.snupkg",
    "nswag.core.yaml.14.0.7.snupkg",
    "njsonschema.11.0.0.snupkg",
    "njsonschema.annotations.11.0.0.snupkg"
)

foreach ($snupkg in $snupkgs){
    if (-not (Test-Path ".\ExternalSymbolsToEmbed\$snupkg")) {
        Write-Host "Downloading $snupkg..." -ForegroundColor Yellow
        Invoke-WebRequest "https://globalcdn.nuget.org/symbol-packages/$snupkg" -OutFile ".\ExternalSymbolsToEmbed\$snupkg"
    } else {
        Write-Host "$snupkg already downloaded" -ForegroundColor Green
    }
}
Write-Host "Copying custom System.CommandLine packages..." -ForegroundColor Cyan
Copy-Item .\packages-local\System.CommandLine.2.0.0-codegencs.snupkg .\ExternalSymbolsToEmbed\
Copy-Item .\packages-local\System.CommandLine.NamingConventionBinder.2.0.0-codegencs.snupkg .\ExternalSymbolsToEmbed\
$snupkgs = gci .\ExternalSymbolsToEmbed\*.snupkg

Write-Host "Extracting PDB files from symbol packages..." -ForegroundColor Yellow
if ($7z) {
    foreach ($snupkg in $snupkgs){
        $name = $snupkg.Name
        $name = $name.Substring(0, $name.Length-7)

        if ($script:isWindowsPlatform) {
            $zipContents = (& $7z l -ba -slt "ExternalSymbolsToEmbed\$name.snupkg" | Out-String) -split"`r`n"
            $zipContents | Select-String "Path = "
            New-Item -ItemType Directory -Force -Path "ExternalSymbolsToEmbed\$name\" -ErrorAction Ignore | Out-Null
            & $7z x "ExternalSymbolsToEmbed\$name.snupkg" "-oExternalSymbolsToEmbed\$name\" *.pdb -r -aoa
        } else {
            # NuGet packages are already lowercase from CDN, use original name
            New-Item -ItemType Directory -Force -Path "ExternalSymbolsToEmbed/$name/" -ErrorAction Ignore | Out-Null
            Write-Host "Extracting PDBs from $name.snupkg..." -ForegroundColor Cyan
            $zipContents = (& $7z l "ExternalSymbolsToEmbed/$name.snupkg" | Out-String) -split"`n"
            $zipContents | Select-String ".pdb"
            & $7z x "ExternalSymbolsToEmbed/$name.snupkg" "-oExternalSymbolsToEmbed/$name/" "*.pdb" -r -y | Out-Null
        }
    }
} else {
    Write-Warning "Archive tool (7z) not found. Skipping PDB extraction."
}

Write-Host "`nBuilding CodegenCS.MSBuild..." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

dotnet restore .\MSBuild\CodegenCS.MSBuild\CodegenCS.MSBuild.csproj
$packagesPath = Join-Path $script:PSScriptRoot "packages-local"
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += ".\MSBuild\CodegenCS.MSBuild\CodegenCS.MSBuild.csproj", "/t:Restore", "/t:Build", "/t:Pack"
$build_args += "/p:PackageOutputPath=$packagesPath", "/p:Configuration=$configuration"
$build_args += "/verbosity:minimal", "/p:IncludeSymbols=true", "/p:ContinuousIntegrationBuild=true"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

#if (Test-Path $nugetPE) { & $nugetPE ".\packages-local\CodegenCS.MSBuild.$version.nupkg" }
if ($7z -and (Test-Path $7z)) {
    if ($script:isWindowsPlatform) {
        $zipContents = (& $7z l -ba -slt .\packages-local\CodegenCS.MSBuild.$version.nupkg | Out-String) -split"`r`n"
        Write-Host "------------" -ForegroundColor Yellow
        $zipContents|Select-String "Path ="
        Start-Sleep 2
        # sanity check: nupkg should have debug-build dlls, pdb files, source files, etc.
        if (-not ($zipContents|Select-String "Path = "|Select-String "CodegenCS.Core.dll")) { throw "msbuild failed" }
        if (-not ($zipContents|Select-String "Path = "|Select-String "CodegenCS.Core.pdb") -and $configuration -eq "Debug") { throw "msbuild failed" }
    } else {
        $zipContents = (& $7z l ./packages-local/CodegenCS.MSBuild.$version.nupkg | Out-String) -split"`n"
        Write-Host "------------" -ForegroundColor Yellow
        $zipContents|Select-String "CodegenCS.Core"
        Start-Sleep 2
        # sanity check: nupkg should have debug-build dlls, pdb files, source files, etc.
        if (-not ($zipContents|Select-String "CodegenCS.Core.dll")) { throw "msbuild failed" }
        if (-not ($zipContents|Select-String "CodegenCS.Core.pdb") -and $configuration -eq "Debug") { throw "msbuild failed" }
    }
} else {
    Write-Warning "Archive tool not available. Skipping nupkg validation."
}

# Visual Studio Design-Time-Builds were keeping msbuild running and eventually building (and locking) our templates. I think this is gone, now that Design-Time-Builds were blocked in CodegenCS.MSBuild.targets
# handle codegencs.core.dll
#taskkill /f /im msbuild.exe


# If task fails due to missing dependencies then fusion++ might help to identify what's missing: C:\ProgramData\chocolatey\lib\fusionplusplus\tools\Fusion++.exe

# Test with SDK-Project using msbuild (.NET Framework)
# Ensure temp directory is set for test runs
if (-not $script:isWindowsPlatform) {
    $env:TMPDIR = $workspaceTempPath
}
Remove-Item ..\Samples\MSBuild1\*.g.cs -ErrorAction Ignore
Remove-Item ..\Samples\MSBuild1\*.generated.cs -ErrorAction Ignore
#dotnet clean ..\Samples\MSBuild1\MSBuild1.csproj
dotnet restore ..\Samples\MSBuild1\MSBuild1.csproj
$build_args = @()
if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
$build_args += "..\Samples\MSBuild1\MSBuild1.csproj", "/t:Restore", "/t:Rebuild"
$build_args += "/p:Configuration=$configuration", "/verbosity:normal"
& $msbuild @build_args
if (! $?) { throw "msbuild failed" }

Write-Host "------------" -ForegroundColor Yellow

if (-not (gci ..\Samples\MSBuild1\*.g.cs)){ throw "Template failed (classes were not added to the compilation)" }

if ($decompiler) {
    if ($decompilerType -eq "dnspy") {
        & $decompiler ..\Samples\MSBuild1\bin\$configuration\net8.0\MSBuild1.dll -t MyFirstClass
        if (! $?) { throw "Template failed (classes were not added to the compilation)" }
    } elseif ($decompilerType -eq "ilspy") {
        Write-Host "Decompiling with ILSpy..." -ForegroundColor Cyan
        & $decompiler ../Samples/MSBuild1/bin/$configuration/net8.0/MSBuild1.dll -t MyFirstClass 2>&1 | Write-Output
    }
} else {
    Write-Warning "Decompiler not available. Install ilspycmd with: dotnet tool install -g ilspycmd"
}

# Test with SDK-Project using dotnet build (.NET Core)
Remove-Item ..\Samples\MSBuild1\*.g.cs -ErrorAction Ignore
Remove-Item ..\Samples\MSBuild1\*.generated.cs -ErrorAction Ignore
#dotnet clean ..\Samples\MSBuild1\MSBuild1.csproj
dotnet restore ..\Samples\MSBuild1\MSBuild1.csproj
& dotnet build "..\Samples\MSBuild1\MSBuild1.csproj" `
           /t:Restore /t:Rebuild                                           `
           /p:Configuration=$configuration                                      `
           /verbosity:normal
if (! $?) { throw "msbuild failed" }

Write-Host "------------" -ForegroundColor Yellow

if (-not (gci ..\Samples\MSBuild1\*.g.cs)){ throw "Template failed (classes were not added to the compilation)" }

if ($decompiler) {
    if ($decompilerType -eq "dnspy") {
        & $decompiler ..\Samples\MSBuild1\bin\$configuration\net8.0\MSBuild1.dll -t MyFirstClass
        if (! $?) { throw "Template failed (classes were not added to the compilation)" }
    } elseif ($decompilerType -eq "ilspy") {
        Write-Host "Decompiling with ILSpy..." -ForegroundColor Cyan
        & $decompiler ../Samples/MSBuild1/bin/$configuration/net8.0/MSBuild1.dll -t MyFirstClass 2>&1 | Write-Output
    }
} else {
    Write-Warning "Decompiler not available. Install ilspycmd with: dotnet tool install -g ilspycmd"
}

# Test with non-SDK-Project (Microsoft Framework Web Application) using msbuild (.NET Framework)
# This test is Windows-only as it requires Visual Studio MSBuild targets
if ($script:isWindowsPlatform) {
    Remove-Item ..\Samples\MSBuild2\*.g.cs -ErrorAction Ignore
    Remove-Item ..\Samples\MSBuild2\*.generated.cs -ErrorAction Ignore
    #dotnet clean ..\Samples\MSBuild2\WebApplication.csproj
    #dotnet restore ..\Samples\MSBuild2\WebApplication.csproj
    nuget restore -PackagesDirectory .\packages ..\Samples\MSBuild2\WebApplication.csproj
    $build_args = @()
    if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
    $build_args += "..\Samples\MSBuild2\WebApplication.csproj", "/t:Restore", "/t:Rebuild"
    $build_args += "/p:Configuration=$configuration", "/verbosity:normal"
    & $msbuild @build_args
    if (! $?) { throw "msbuild failed" }

    Write-Host "------------" -ForegroundColor Yellow

    if (-not (gci ..\Samples\MSBuild2\*.g.cs)){ throw "Template failed (classes were not added to the compilation)" }

    if ($decompiler) {
        if ($decompilerType -eq "dnspy") {
            & $decompiler ..\Samples\MSBuild2\bin\WebApplication.dll -t MyFirstClass
            if (! $?) { throw "Template failed (classes were not added to the compilation)" }
        } elseif ($decompilerType -eq "ilspy") {
            Write-Host "Decompiling with ILSpy..." -ForegroundColor Cyan
            & $decompiler ../Samples/MSBuild2/bin/WebApplication.dll -t MyFirstClass 2>&1 | Write-Output
        }
    } else {
        Write-Warning "Decompiler not available. Install ilspycmd with: dotnet tool install -g ilspycmd"
    }

    # Test with non-SDK-Project (Microsoft Framework Web Application) using dotnet build (.NET Core) - doesnt work
} else {
    Write-Host "Skipping MSBuild2 tests (Windows-only .NET Framework web application)" -ForegroundColor Yellow
}


Pop-Location

