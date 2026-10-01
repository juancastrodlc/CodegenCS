#!/usr/bin/env pwsh
$expectedVersion="3.5.0"

$ErrorActionPreference = "Stop"

# Cross-platform: on Windows PowerShell 5.x $IsWindows is undefined.
if ($null -eq (Get-Variable -Name IsWindows -ErrorAction Ignore)) { $global:IsWindows = $true }

# How to install tool globally:
# dotnet tool install --global dotnet-codegencs --version $expectedVersion

# Resolve the dotnet global tools path cross-platform (dotnet-codegencs.exe on Windows).
$toolsDir = Join-Path ($(if ($IsWindows) { $env:USERPROFILE } else { $env:HOME })) ".dotnet/tools"
$toolExe = if ($IsWindows) { "dotnet-codegencs.exe" } else { "dotnet-codegencs" }
$codegencs = Join-Path $toolsDir $toolExe
$codegencsPrefix = @()

Push-Location $PSScriptRoot
try {
    # If not there install globally
    if (-not (Test-Path $codegencs)) {
        & dotnet tool install --global dotnet-codegencs --version $expectedVersion
        if ($LASTEXITCODE -eq 0) {
            $codegencs = Join-Path $toolsDir $toolExe
        }
    }

    # If global installation failed, install locally in a manifest.
    if (-not (Test-Path $codegencs)) {
        $manifestPath = Join-Path $PSScriptRoot ".config/dotnet-tools.json"
        if (-not (Test-Path $manifestPath)) {
            & dotnet new tool-manifest
            if ($LASTEXITCODE -ne 0) { throw "Could not create a local dotnet tool manifest." }
        }

        & dotnet tool install dotnet-codegencs --version $expectedVersion
        if ($LASTEXITCODE -ne 0) { throw "Could not install dotnet-codegencs globally or locally." }
        $codegencs = "dotnet"
        $codegencsPrefix = @("tool", "run", "dotnet-codegencs")
    }

    # Download template if not there
    if (-not (Test-Path "DapperExtensionPocos.cs")) {
        & $codegencs @codegencsPrefix template clone https://raw.githubusercontent.com/CodegenCS/Templates/main/DatabaseSchema/DapperExtensionPocos/DapperExtensionPocos.cs
        if ($LASTEXITCODE -ne 0) { throw "Could not clone DapperExtensionPocos.cs." }
        # equivalent of & $codegencs template clone DapperExtensionPocos
    }

    Write-Host "Refreshing DB SCHEMA..." -ForegroundColor Yellow
    #& $codegencs model dbschema extract mssql 'Server=MYSERVER; Database=AdventureWorks; User Id=myUsername;Password=myPassword' ./AdventureWorksSchema.json

    Write-Host "Running DapperExtensionPocos.cs template..." -ForegroundColor Yellow
    & $codegencs @codegencsPrefix template run DapperExtensionPocos.cs ./AdventureWorksSchema.json "SampleProject.Core.Entities" -o ./GeneratedEntities/ -p:CrudNamespace="SampleProject.Core.Database" -p:CrudFile="./DapperCrudExtensions.cs" -p:CrudClass="DapperCrudExtensions" -p:TrackPropertiesChange=true
    if ($LASTEXITCODE -ne 0) { throw "Template execution failed." }
} finally {
    Pop-Location
}
