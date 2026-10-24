#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration,
    [Parameter(Mandatory=$False)][string]$dotnetcodegencsTargetFrameworks="net8",
    [string]$Source = './packages-local'
)

# CLI tool (dotnet-codegencs)
# How to run: .\build-tools.ps1   or   .\build-tools.ps1 -configuration Debug

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1") -Source $Source

if (-not $PSBoundParameters.ContainsKey('configuration'))
{
	if (Test-Path (Join-Path $dir "Release.snk")) { $configuration = "Release"; } else { $configuration = "Debug"; }
}
Write-Host "Using configuration $configuration..." -ForegroundColor Yellow

try {

	$packOutput = Join-Path $dir "packages-local"
	$nugetConfig = $null

	$buildOnly = @(
		"Tools/TemplateBuilder/CodegenCS.Tools.TemplateBuilder.csproj",
		"Tools/TemplateLauncher/CodegenCS.Tools.TemplateLauncher.csproj",
		"Tools/TemplateDownloader/CodegenCS.Tools.TemplateDownloader.csproj"
	)
	foreach ($project in $buildOnly) {
		$p = Join-Path $dir $project
		dotnet restore $p --source $global:nugetSourcePath
		Invoke-MSBuild $p `
			/t:Restore /t:Build `
			/p:Configuration=$configuration `
			/p:IncludeSymbols=true `
			/verbosity:minimal `
			/p:ContinuousIntegrationBuild=true
	}

	# dotnet-codegencs (DotnetTool nupkg/snupkg)
	$cli = Join-Path $dir "Tools/dotnet-codegencs/dotnet-codegencs.csproj"
	if ($dotnetcodegencsTargetFrameworks.IndexOf(";") -eq -1) {
		# single target
		$maxVer = $dotnetcodegencsTargetFrameworks -replace '^net', ''
		Invoke-MSBuild $cli `
			/t:Restore /t:Build /t:Pack `
			/p:PackageOutputPath=$packOutput `
			/p:Configuration=$configuration `
			/p:NETCoreAppMaximumVersion=$maxVer `
			/p:IncludeSymbols=true `
			/verbosity:minimal `
			/p:ContinuousIntegrationBuild=true
	} else {
		# release is multitarget: net6.0;net7.0;net8.0
		Invoke-MSBuild $cli `
			/t:Restore /t:Build /t:Pack `
			/p:PackageOutputPath=$packOutput `
			/p:Configuration=$configuration `
			/p:IncludeSymbols=true `
			/verbosity:minimal `
			/p:ContinuousIntegrationBuild=true
	}

	# uninstall/reinstall global tool from local dotnet-codegencs.*.nupkg:
	dotnet tool uninstall -g dotnet-codegencs 2>$null
	$nugetConfig = Join-Path ([System.IO.Path]::GetTempPath()) ("CodegenCS-NuGet-{0}.config" -f [Guid]::NewGuid())
	$sourceForConfig = [System.Security.SecurityElement]::Escape($global:nugetSourcePath)
	$packOutputForConfig = [System.Security.SecurityElement]::Escape([System.IO.Path]::GetFullPath($packOutput))
	@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="packages-local" value="$sourceForConfig" />
    <add key="build-output" value="$packOutputForConfig" />
  </packageSources>
</configuration>
"@ | Set-Content -Path $nugetConfig -Encoding utf8
	dotnet tool install --global --configfile $nugetConfig --no-cache dotnet-codegencs
	if ($LASTEXITCODE -ne 0) { throw "dotnet tool install failed (exit code $LASTEXITCODE)" }
	$codegencs = Get-DotnetToolsPath
	if (Test-Path $codegencs) {
		& $codegencs --version
	} else {
		# Fall back to PATH lookup (dotnet global tools are normally on PATH)
		& dotnet-codegencs --version
	}

} finally {
	if ($nugetConfig -and (Test-Path $nugetConfig)) {
		Remove-Item $nugetConfig -Force
	}
	Pop-Location
}
