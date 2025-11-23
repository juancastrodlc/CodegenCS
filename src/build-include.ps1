# ===================================================================
# FORCED PATH CONFIGURATION: Work exclusively in ~/source/repos/CodegenCS
# ===================================================================
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    # Force all build operations to occur in the symlink directory if it exists
    $FORCED_SRC_DIR = "$HOME/source/repos/CodegenCS/src"
    if (Test-Path $FORCED_SRC_DIR) {
        Set-Location $FORCED_SRC_DIR
        Write-Host "Running from $FORCED_SRC_DIR" -ForegroundColor Yellow
        # Override PSScriptRoot to use forced directory instead of resolved real path
        $script:PSScriptRoot = $FORCED_SRC_DIR
    }
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
