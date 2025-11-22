#!/usr/bin/env pwsh
Push-Location $PSScriptRoot

# Detect home directory cross-platform
$homeDir = if ($IsWindows -or $env:OS -match "Windows") {
    "$env:HOMEDRIVE$env:HOMEPATH"
} else {
    $env:HOME
}

try {

	Remove-Item -Recurse -Force -ErrorAction Ignore ".\packages-local"
	Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $homeDir ".nuget\packages\codegencs")
	Remove-Item -Recurse -Force -ErrorAction Ignore (Join-Path $homeDir ".nuget\packages\codegencs.*")

	#Remove-Item -Recurse -Force -ErrorAction Ignore ".\External\command-line-api\artifacts\packages\Debug\Shipping\"
	#Remove-Item -Recurse -Force -ErrorAction Ignore ".\External\command-line-api\artifacts\packages\Release\Shipping\"


	# when target frameworks are added/modified dotnet clean might fail and we may need to cleanup the old dependency tree
	Remove-Item -Recurse -Force -ErrorAction Ignore ".\vs"
	Get-ChildItem .\ -Recurse | Where-Object { $_.Name -eq "bin" -and $_.PSIsContainer } | Remove-Item -Recurse -Force -ErrorAction Ignore
	Get-ChildItem .\ -Recurse | Where-Object { $_.Name -eq "obj" -and $_.PSIsContainer } | Remove-Item -Recurse -Force -ErrorAction Ignore
	Get-ChildItem .\ -Recurse | Where-Object { $_.Name -eq "project.assets.json" -and $_.Directory.Name -eq "obj" } | Remove-Item -Force -ErrorAction Ignore
	#Get-ChildItem .\ -Recurse | Where-Object { $_.Extension -eq ".csproj" -and $_.FullName -notmatch "VSExtensions" } | ForEach-Object { dotnet clean $_.FullName }
	#dotnet clean .\CodegenCS.sln
	New-Item -ItemType Directory -Force -Path ".\packages-local"

} finally {
    Pop-Location
}
