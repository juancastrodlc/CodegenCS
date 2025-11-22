#!/usr/bin/env pwsh
# Detect if running on Windows
$script:isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsWindows
} else {
    # PowerShell 5.1 (Windows only)
    $true
}

if ($script:isWindowsPlatform) {
    # Windows: Use Visual Studio MSBuild
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

# Cross-platform NuGet handling
if ($script:isWindowsPlatform) {
    # Windows: Download nuget.exe
    $targetNugetExe = Join-Path $PSScriptRoot "nuget.exe"
    if (-not (Test-Path $targetNugetExe)) {
        $sourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        Invoke-WebRequest $sourceNugetExe -OutFile $targetNugetExe
        Set-Alias nuget $targetNugetExe -Scope Global -Verbose
    }
} else {
    # Linux/macOS: Use dotnet commands as NuGet equivalent
    $nugetCommand = Get-Command nuget -CommandType Application -ErrorAction SilentlyContinue
    if ($nugetCommand) {
        Set-Alias nuget $nugetCommand.Source -Scope Global -Verbose
    } else {
        # Only define the function if it doesn't already exist
        if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
            Write-Warning "NuGet command not found. Using 'dotnet' commands as fallback."
            # Fallback function that maps nuget.exe commands to dotnet equivalents
            function nuget {
                param([Parameter(ValueFromRemainingArguments=$true)][string[]]$arguments)

            $command = $arguments[0]
            $restArgs = $arguments[1..($arguments.Length-1)]

            switch ($command) {
                "restore" {
                    # nuget restore -PackagesDirectory ./packages project.csproj
                    # -> dotnet restore project.csproj --packages ./packages
                    $packagesDirIndex = [array]::IndexOf($restArgs, "-PackagesDirectory")
                    if ($packagesDirIndex -ge 0 -and $packagesDirIndex + 1 -lt $restArgs.Length) {
                        $packagesDir = $restArgs[$packagesDirIndex + 1]
                        $projectFile = $restArgs | Where-Object { $_ -notmatch "^-" -and $_ -ne $packagesDir } | Select-Object -First 1
                        dotnet restore $projectFile --packages $packagesDir
                    } else {
                        dotnet restore $restArgs
                    }
                }
                "push" {
                    # nuget push package.nupkg -> dotnet nuget push package.nupkg
                    dotnet nuget push $restArgs
                }
                "pack" {
                    # nuget pack -> dotnet pack
                    dotnet pack $restArgs
                }
                default {
                    Write-Error "NuGet command '$command' not mapped. Supported: restore, push, pack. For other operations, install nuget: dotnet tool install --global nuget.commandline"
                    exit 1
                }
            }
        }
        }
    }
}
