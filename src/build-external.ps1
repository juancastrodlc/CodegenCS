#!/usr/bin/env pwsh
[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)][ValidateSet('Release','Debug')][string]$configuration
)

# DEPRECATED: This script used to build the customized System.CommandLine "2.0.0-codegencs"
# fork from the .\External\command-line-api git submodule and copy the resulting packages
# into .\packages-local.
#
# The migration removed the dependency on that fork - the public System.CommandLine packages
# are now referenced directly and are already present in .\packages-local. There is nothing
# to build here anymore, so this script is a no-op kept only for backwards compatibility.

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
. (Join-Path $dir "build-include.ps1")

Write-Host "build-external.ps1 is deprecated: the System.CommandLine 2.0.0-codegencs fork is no longer built." -ForegroundColor Yellow
Write-Host "The public System.CommandLine packages in .\packages-local are used instead. Nothing to do." -ForegroundColor DarkGray
