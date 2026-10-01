# Cross-platform build include.
# Provides OS detection, an MSBuild invocation helper and a NuGet helper that work on
# both Windows and Linux. Sourced by all other build-*.ps1 scripts.

# PowerShell (Windows PowerShell 5.x) does not define $IsWindows/$IsLinux, so define them.
if ($null -eq (Get-Variable -Name IsWindows -ErrorAction Ignore)) {
    $global:IsWindows = $true
    $global:IsLinux = $false
    $global:IsMacOS = $false
}

# Resolve MSBuild:
# - On Windows we prefer a full Visual Studio msbuild.exe (needed for VSIX / non-SDK projects),
#   falling back to "dotnet msbuild" when none is found.
# - On Linux/macOS there is no msbuild.exe, so we always use "dotnet msbuild".
$global:msbuildExe = $null
if ($IsWindows) {
    $global:msbuildExe = (
        "$Env:programfiles\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\msbuild.exe",
        "$Env:programfiles\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin\msbuild.exe",
        "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -first 1
}

# Invoke-MSBuild: single entry-point used by every script.
# Uses full msbuild.exe when available, otherwise "dotnet msbuild".
function Invoke-MSBuild {
    param([Parameter(ValueFromRemainingArguments=$true)] [string[]] $Arguments)
    if ($global:msbuildExe) {
        & $global:msbuildExe @Arguments
    } else {
        & dotnet msbuild @Arguments
    }
    if ($LASTEXITCODE -ne 0) { throw "msbuild failed (exit code $LASTEXITCODE)" }
}

# Path to the user's global nuget package cache, cross-platform.
function Get-NuGetGlobalPackagesFolder {
    if ($env:NUGET_PACKAGES) { return $env:NUGET_PACKAGES }
    $userProfilePath = if ($IsWindows) { "$env:USERPROFILE" } else { "$env:HOME" }
    return (Join-Path $userProfilePath ".nuget/packages")
}

# On Windows the CLI global tool is dotnet-codegencs.exe; on Linux/macOS there is no extension.
function Get-DotnetToolsPath {
    $userProfilePath = if ($IsWindows) { "$env:USERPROFILE" } else { "$env:HOME" }
    $exe = if ($IsWindows) { "dotnet-codegencs.exe" } else { "dotnet-codegencs" }
    return (Join-Path (Join-Path $userProfilePath ".dotnet/tools") $exe)
}
