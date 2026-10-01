#!/usr/bin/env pwsh
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

. (Join-Path $dir "build-include.ps1")

try {

	$packagesLocal = Join-Path $dir "packages-local"
	$nugetGlobal = Get-NuGetGlobalPackagesFolder

	# Note: we do NOT delete packages-local here anymore because on Linux it contains the
	# pre-restored offline packages (including System.CommandLine) required to build.
	# We only clear the locally-built CodegenCS.* packages from the global nuget cache.
	Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $nugetGlobal "codegencs")
	Get-ChildItem -Path $nugetGlobal -Filter "codegencs.*" -Directory -ErrorAction Ignore | Remove-Item -Recurse -Force -ErrorAction Ignore

	# when target frameworks are added/modified dotnet clean might fail and we may need to cleanup the old dependency tree
	Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $dir ".vs")

	# Remove bin/obj folders (cross-platform, skip the External submodule we are migrating away from)
	Get-ChildItem -Path $dir -Recurse -Directory -ErrorAction Ignore |
		Where-Object { ($_.Name -eq "bin" -or $_.Name -eq "obj") -and $_.FullName -notmatch "[\\/]External[\\/]" } |
		Remove-Item -Recurse -Force -ErrorAction Ignore

	New-Item -ItemType Directory -Force -Path $packagesLocal | Out-Null

} finally {
    Pop-Location
}
