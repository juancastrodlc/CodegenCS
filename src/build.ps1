#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)]
    [ValidateSet('Release','Debug')]
    [string]$configuration="Debug",
    [switch] $RunTests = $false
)

# How to run: .\build.ps1

. $script:PSScriptRoot\build-include.ps1

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path "Release.snk") { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

$ErrorActionPreference="Stop"

$dotnetSdk = (& dotnet --list-sdks | %{ $_.Substring(0, $_.IndexOf(".")) } | Sort-Object Descending | Select-Object -First 1)

# .NET Framework detection (Windows only)
$hasNet472 = $false
if ($script:isWindowsPlatform) {
    $hasNet472 = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction SilentlyContinue |
        Get-ItemProperty -name Version, Release -EA 0 |
        Where-Object { $_.PSChildName -match '^(?!S)\p{L}'} |
        Select-Object @{name = "NETFramework"; expression = {$_.PSChildName}}, Version, Release |
        Where-Object { $_.NETFramework -eq "Full" -and $_.Release -gt 461814 }
}

if ($configuration -eq "Release") {
    # dotnet-codegencs is released for multiple targets.
    # other projects are all single-target
    if ($script:isWindowsPlatform) {
        $dotnetcodegencsTargetFrameworks="net6.0;net7.0;net8.0"
        if (-not $dotnetSdk -or -not $hasNet472) { throw "Can't find .NET or .NET Framework'" }
    } else {
        # Linux: Skip .NET Framework
        $dotnetcodegencsTargetFrameworks="net6.0;net7.0;net8.0"
        if (-not $dotnetSdk) { throw "Can't find .NET SDK" }
        Write-Host "Building for Linux - Skipping .NET Framework targets" -ForegroundColor Yellow
    }
} else {
    # For debug use latest dotnet SDK or (if not found) use net472
    if ($dotnetSdk) {
        $dotnetcodegencsTargetFrameworks = "net" + $dotnetSdk
    } elseif ($script:isWindowsPlatform -and $hasNet472) {
        $dotnetcodegencsTargetFrameworks = "net472"
    } else {
        if ($script:isWindowsPlatform) {
            throw "Can't find .NET SDK or .NET Framework"
        } else {
            throw "Can't find .NET SDK"
        }
    }
}

. $script:PSScriptRoot\build-clean.ps1

New-Item -ItemType Directory -Force -Path ".\packages-local"

$commandLinePkg1 = Join-Path $script:PSScriptRoot "External\command-line-api\artifacts\packages\$configuration\Shipping\System.CommandLine.2.0.0-codegencs.nupkg"
$commandLinePkg2 = Join-Path $script:PSScriptRoot "External\command-line-api\artifacts\packages\$configuration\Shipping\System.CommandLine.2.0.0-codegencs.snupkg"
$commandLinePkg3 = Join-Path $script:PSScriptRoot "External\command-line-api\artifacts\packages\$configuration\Shipping\System.CommandLine.NamingConventionBinder.2.0.0-codegencs.nupkg"
$commandLinePkg4 = Join-Path $script:PSScriptRoot "External\command-line-api\artifacts\packages\$configuration\Shipping\System.CommandLine.NamingConventionBinder.2.0.0-codegencs.snupkg"

if ((Test-Path $commandLinePkg1) -and (Test-Path $commandLinePkg2) -and (Test-Path $commandLinePkg3) -and (Test-Path $commandLinePkg4))
{
    # no need to rebuild this huge package every time, unless you modify it
    Copy-Item $commandLinePkg1 ".\packages-local\"
    Copy-Item $commandLinePkg2 ".\packages-local\"
    Copy-Item $commandLinePkg3 ".\packages-local\"
    Copy-Item $commandLinePkg4 ".\packages-local\"
} else {
    . $script:PSScriptRoot\build-external.ps1 -Configuration $configuration
}

. $script:PSScriptRoot\build-core.ps1 -Configuration $configuration

. $script:PSScriptRoot\build-models.ps1 -Configuration $configuration

if ($configuration -eq "Release")
{
	# For release builds we clear bin/obj again to ensure that all further builds will use the locally published nugets
    Get-ChildItem .\Core\ -Recurse | Where-Object { $_.Name -eq "bin" -and $_.PSIsContainer } | Remove-Item -Recurse -Force -ErrorAction Ignore
    Get-ChildItem .\Core\ -Recurse | Where-Object { $_.Name -eq "obj" -and $_.PSIsContainer } | Remove-Item -Recurse -Force -ErrorAction Ignore
    Get-ChildItem .\Models\ -Recurse | Where-Object { $_.Name -eq "bin" -and $_.PSIsContainer } | Remove-Item -Recurse -Force -ErrorAction Ignore
    Get-ChildItem .\Models\ -Recurse | Where-Object { $_.Name -eq "obj" -and $_.PSIsContainer } | Remove-Item -Recurse -Force -ErrorAction Ignore
}

. $script:PSScriptRoot\build-tools.ps1 -Configuration $configuration -dotnetcodegencsTargetFrameworks $dotnetcodegencsTargetFrameworks

if ($configuration -eq "Release") {
  . $script:PSScriptRoot\build-sourcegenerator.ps1
}

# Skip MSBuild sample tests on Linux due to path resolution issues
if ($script:isWindowsPlatform) {
    . $script:PSScriptRoot\build-msbuild.ps1
} else {
    Write-Host "Skipping MSBuild sample tests on Linux" -ForegroundColor Yellow
}

# Unit tests # TODO: break this into CORE tests, MODEL tests, CLITESTS
if ($RunTests) {
    $coreTestsProj = Join-Path $script:PSScriptRoot "Core\CodegenCS.Tests\CodegenCS.Tests.csproj"
    dotnet restore $coreTestsProj
    dotnet build --configuration $configuration $coreTestsProj
    dotnet test --configuration $configuration $coreTestsProj

    $toolsTestsProj = Join-Path $script:PSScriptRoot "Tools\Tests\CodegenCS.Tools.Tests.csproj"
    dotnet restore $toolsTestsProj
    #dotnet build --configuration $configuration --runtime net8 $toolsTestsProj # TODO: $dotnetcodegencsTargetFrameworks
    $build_args = @()
    if ($msbuild -eq "dotnet") { $build_args += "msbuild" }
    $build_args += $toolsTestsProj, "/t:Restore", "/t:Build"
    $build_args += "/p:Configuration=$configuration", "/p:targetFrameworks=net8"
    & $msbuild @build_args
    dotnet test --configuration $configuration /p:targetFrameworks=net8 $toolsTestsProj
}

if ($script:isWindowsPlatform -and $hasNet472) {
    $env:VSToolsPath="C:\Program Files\Microsoft Visual Studio\2022\Professional\Msbuild\Microsoft\VisualStudio\v17.0"
    . $script:PSScriptRoot\build-visualstudio.ps1 -Configuration $configuration
}


