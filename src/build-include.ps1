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

# Offer to install 7-Zip if not found
if (-not $script:7z) {
    if ($script:isWindowsPlatform) {
        # On Windows, offer to install via Chocolatey
        $installed = Install-ChocoPackage -PackageName "7zip" -Description "7-Zip archive utility for extracting symbol packages"
        if ($installed) {
            # Re-check for 7z after installation
            if (Get-Command 7z -ErrorAction SilentlyContinue) {
                $script:7z = (Get-Command 7z).Source
            } elseif (Test-Path "C:\Program Files\7-Zip\7z.exe") {
                $script:7z = "C:\Program Files\7-Zip\7z.exe"
            }
        }
    } else {
        # On Linux/macOS, provide installation instructions
        Write-Warning "7z not found. Install with:"
        Write-Warning "  Ubuntu/Debian: sudo apt-get install p7zip-full"
        Write-Warning "  macOS: brew install p7zip"
    }
}

# Detect NuGet Package Explorer (Windows-only GUI tool)
$script:nugetPE = $null
if ($script:isWindowsPlatform -and (Test-Path "C:\ProgramData\chocolatey\bin\NuGetPackageExplorer.exe")) {
    $script:nugetPE = "C:\ProgramData\chocolatey\bin\NuGetPackageExplorer.exe"
}

# ===================================================================
# AUTOMATIC TOOL INSTALLATION HELPERS
# ===================================================================

function Install-DotnetTool {
    param(
        [string]$ToolName,
        [string]$PackageId,
        [string]$Description
    )
    
    Write-Host ""
    Write-Host "Tool '$ToolName' is required but not found." -ForegroundColor Yellow
    Write-Host "Description: $Description" -ForegroundColor Gray
    Write-Host ""
    $response = Read-Host "Install $ToolName locally? [Y/n] (default: Y)"
    
    if ([string]::IsNullOrWhiteSpace($response) -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Installing $ToolName locally to workspace..." -ForegroundColor Cyan
        
        # Create tool manifest if it doesn't exist
        if (-not (Test-Path ".config/dotnet-tools.json")) {
            Write-Host "Creating dotnet tool manifest..." -ForegroundColor Cyan
            & dotnet new tool-manifest
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to create tool manifest" -ForegroundColor Red
                return $false
            }
        }
        
        # Install tool locally
        & dotnet tool install --local $PackageId
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$ToolName installed successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to install $ToolName" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "Skipping $ToolName installation. Build may fail." -ForegroundColor Yellow
        return $false
    }
}

function Install-ChocoPackage {
    param(
        [string]$PackageName,
        [string]$Description
    )
    
    Write-Host ""
    Write-Host "Tool '$PackageName' is required but not found." -ForegroundColor Yellow
    Write-Host "Description: $Description" -ForegroundColor Gray
    Write-Host ""
    
    # Check if Chocolatey is installed
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Chocolatey is not installed." -ForegroundColor Yellow
        Write-Host "Would you like to install Chocolatey first? This requires administrator privileges." -ForegroundColor Cyan
        $chocoResponse = Read-Host "Install Chocolatey? [Y/n] (default: Y)"
        
        if ([string]::IsNullOrWhiteSpace($chocoResponse) -or $chocoResponse -eq 'Y' -or $chocoResponse -eq 'y') {
            Write-Host "Installing Chocolatey..." -ForegroundColor Cyan
            Write-Host "This requires running as Administrator. You may see a UAC prompt." -ForegroundColor Yellow
            
            try {
                # Check if running as admin
                $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                
                if (-not $isAdmin) {
                    Write-Host "Please run this script as Administrator to install Chocolatey." -ForegroundColor Red
                    Write-Host "Alternatively, install 7-Zip manually from: https://www.7-zip.org/download.html" -ForegroundColor Yellow
                    return $false
                }
                
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                
                if ($LASTEXITCODE -ne 0 -and -not (Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Host "Failed to install Chocolatey" -ForegroundColor Red
                    return $false
                }
                
                Write-Host "Chocolatey installed successfully!" -ForegroundColor Green
                # Refresh environment
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } catch {
                Write-Host "Failed to install Chocolatey: $_" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "Skipping Chocolatey installation." -ForegroundColor Yellow
            return $false
        }
    }
    
    # Now install the package via Chocolatey
    $response = Read-Host "Install $PackageName via Chocolatey? [Y/n] (default: Y)"
    
    if ([string]::IsNullOrWhiteSpace($response) -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Installing $PackageName via Chocolatey..." -ForegroundColor Cyan
        Write-Host "This may require administrator privileges." -ForegroundColor Yellow
        
        & choco install $PackageName -y
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$PackageName installed successfully!" -ForegroundColor Green
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return $true
        } else {
            Write-Host "Failed to install $PackageName via Chocolatey" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "Skipping $PackageName installation. Build may fail." -ForegroundColor Yellow
        return $false
    }
}

# ===================================================================
# DOTNET TOOL DETECTION (local tools via manifest preferred)
# ===================================================================

function Test-DotnetTool {
    param([string]$ToolName)
    
    # Check if tool is available via 'dotnet <tool>' (local or global)
    try {
        $null = & dotnet $ToolName --version 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# Detect decompiler tools (cross-platform: ilspycmd only)
$script:decompiler = $null
$script:decompilerType = $null
if (Test-DotnetTool "ilspycmd") {
    $script:decompiler = "ilspycmd"
    $script:decompilerType = "ilspy"
}

# Detect NuGet package version from nbgv
$script:nugetPackageVersion = $null
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    # Check if nbgv is available (local or global)
    if (Test-DotnetTool "nbgv") {
        try {
            $script:nugetPackageVersion = (& dotnet nbgv get-version -v NuGetPackageVersion 2>$null)
            if ($LASTEXITCODE -ne 0) {
                $script:nugetPackageVersion = $null
            }
        } catch {
            $script:nugetPackageVersion = $null
        }
    }
    
    # If nbgv not available, offer to install it locally
    if (-not $script:nugetPackageVersion) {
        $installed = Install-DotnetTool -ToolName "nbgv" -PackageId "nbgv" -Description "Nerdbank.GitVersioning tool for version management"
        
        if ($installed) {
            Write-Host "Retrying version detection..." -ForegroundColor Cyan
            try {
                $script:nugetPackageVersion = (& dotnet nbgv get-version -v NuGetPackageVersion 2>$null)
                if ($LASTEXITCODE -ne 0) {
                    $script:nugetPackageVersion = $null
                    Write-Warning "nbgv was installed but version detection failed. Check version.json configuration."
                }
            } catch {
                Write-Warning "nbgv was installed but version detection failed. Check version.json configuration."
            }
        } else {
            Write-Warning "nbgv not installed. Version detection will fail."
        }
    }
}

# ===================================================================
# Display exported variables to calling script
# ===================================================================
Write-Host "Variables exported to the calling script:" -ForegroundColor Cyan
Write-Host "  `$script:PSScriptRoot          = $script:PSScriptRoot" -ForegroundColor Gray
Write-Host "  `$script:isWindowsPlatform     = $script:isWindowsPlatform" -ForegroundColor Gray
Write-Host "  `$script:msbuild               = $script:msbuild" -ForegroundColor Gray
Write-Host "  `$script:7z                    = $script:7z" -ForegroundColor Gray
Write-Host "  `$script:nugetPE               = $script:nugetPE" -ForegroundColor Gray
Write-Host "  `$script:decompiler            = $script:decompiler" -ForegroundColor Gray
Write-Host "  `$script:decompilerType        = $script:decompilerType" -ForegroundColor Gray
Write-Host "  `$script:nugetPackageVersion   = $script:nugetPackageVersion" -ForegroundColor Gray

