#!/usr/bin/env pwsh
# ===================================================================
# BUILD INCLUDE - Common Configuration for All Build Scripts
# ===================================================================
# WARNING: This script is meant to be DOT-SOURCED by other scripts,
#          not executed directly. It provides shared configuration,
#          platform detection, and tool paths for all build-*.ps1 scripts.
#
# Usage: . $PSScriptRoot\build-include.ps1
# ===================================================================

# Detect if being run standalone (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.InvocationName -notlike '*\build-include.ps1') {
    Write-Warning "=========================================="
    Write-Warning "This script should be DOT-SOURCED, not run directly!"
    Write-Warning "Usage: . .\build-include.ps1"
    Write-Warning "=========================================="
    exit 1
}

# ===================================================================
# PATH CONFIGURATION: Use actual script location, support symlinks
# ===================================================================
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    # On Linux, check if we're in a symlinked directory and prefer the symlink path
    $realPath = (Get-Item $PSScriptRoot).Target
    if ($realPath) {
        Write-Host "Running from symlink: $PSScriptRoot -> $realPath" -ForegroundColor Yellow
    }
}

# Use PSScriptRoot as-is (the directory containing this script)
if (-not $script:PSScriptRoot) {
    $script:PSScriptRoot = $PSScriptRoot
}

# Platform detection - export to caller's scope
$script:isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $true }

# MSBuild selection
if ($isWindowsPlatform) {
    $msbuild = (
        "$Env:programfiles\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin\msbuild.exe",
        "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\MSBuild\14.0\Bin\MSBuild.exe",
        "${Env:ProgramFiles(x86)}\MSBuild\13.0\Bin\MSBuild.exe",
        "${Env:ProgramFiles(x86)}\MSBuild\12.0\Bin\MSBuild.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -first 1

    if (-not $msbuild) {
        Write-Warning "Visual Studio MSBuild not found, falling back to 'dotnet msbuild'"
        $msbuild = "dotnet"
    }
} else {
    # Linux/macOS: Use dotnet msbuild
    $msbuild = "dotnet"
}

# Use the overridden PSScriptRoot if available (Linux symlink case)
if (-not $script:PSScriptRoot) {
    $script:PSScriptRoot = $PSScriptRoot
}

$targetNugetExe = Join-Path $script:PSScriptRoot "nuget.exe"
if (-not (Test-Path $targetNugetExe)) {
	$sourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
	Invoke-WebRequest $sourceNugetExe -OutFile $targetNugetExe
	Set-Alias nuget $targetNugetExe -Scope Global -Verbose
}

# ===================================================================
# EXTERNAL TOOL DETECTION: 7z, NuGet Package Explorer, Decompilers
# ===================================================================

# Detect 7z (cross-platform archive tool)
$script:7z = $null
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    $script:7z = (Get-Command 7z).Source
} elseif (Get-Command 7za -ErrorAction SilentlyContinue) {
    $script:7z = (Get-Command 7za).Source
} elseif (Get-Command 7zr -ErrorAction SilentlyContinue) {
    $script:7z = (Get-Command 7zr).Source
} elseif (Test-Path "C:\Program Files\7-Zip\7z.exe") {
    $script:7z = "C:\Program Files\7-Zip\7z.exe"
}
if (-not $script:7z -and -not $script:isWindowsPlatform) {
    Write-Warning "7z not found. Install with: sudo apt-get install p7zip-full"
}

# Detect NuGet Package Explorer (Windows-only GUI tool)
$script:nugetPE = $null
if ($script:isWindowsPlatform -and (Test-Path "C:\ProgramData\chocolatey\bin\NuGetPackageExplorer.exe")) {
    $script:nugetPE = "C:\ProgramData\chocolatey\bin\NuGetPackageExplorer.exe"
}

# Detect decompiler tools
$script:decompiler = $null
$script:decompilerType = $null
if ($script:isWindowsPlatform -and (Test-Path "C:\ProgramData\chocolatey\lib\dnspyex\tools\dnSpy.Console.exe")) {
    $script:decompiler = "C:\ProgramData\chocolatey\lib\dnspyex\tools\dnSpy.Console.exe"
    $script:decompilerType = "dnspy"
} elseif (Get-Command ilspycmd -ErrorAction SilentlyContinue) {
    $script:decompiler = (Get-Command ilspycmd).Source
    $script:decompilerType = "ilspy"
}

# ===================================================================
# Display exported variables to calling script
# ===================================================================
Write-Host "Variables exported to the calling script:" -ForegroundColor Cyan
Write-Host "  `$script:PSScriptRoot      = $script:PSScriptRoot" -ForegroundColor Gray
Write-Host "  `$script:isWindowsPlatform = $script:isWindowsPlatform" -ForegroundColor Gray
Write-Host "  `$script:msbuild           = $script:msbuild" -ForegroundColor Gray
Write-Host "  `$script:7z                = $script:7z" -ForegroundColor Gray
Write-Host "  `$script:nugetPE           = $script:nugetPE" -ForegroundColor Gray
Write-Host "  `$script:decompiler        = $script:decompiler" -ForegroundColor Gray
Write-Host "  `$script:decompilerType    = $script:decompilerType" -ForegroundColor Gray

