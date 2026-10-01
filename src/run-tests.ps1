#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$artifactsDirectory = Join-Path $PSScriptRoot 'artifacts'
$summaryPath = Join-Path $artifactsDirectory 'test-summary.md'

$sdkMajor = & dotnet --list-sdks |
    ForEach-Object { [int]($_.Substring(0, $_.IndexOf('.'))) } |
    Sort-Object -Descending |
    Select-Object -First 1
if (-not $sdkMajor) {
    throw "Can't find a .NET SDK"
}
$netCoreAppMaximumVersion = "$sdkMajor.0"

$testProjects = @(
    [pscustomobject]@{
        Name = 'CodegenCS.Tests'
        Path = 'Core/CodegenCS.Tests/CodegenCS.Tests.csproj'
        Report = 'CodegenCS.Tests.trx'
    },
    [pscustomobject]@{
        Name = 'CodegenCS.Tools.Tests'
        Path = 'Tools/Tests/CodegenCS.Tools.Tests.csproj'
        Report = 'CodegenCS.Tools.Tests.trx'
    },
    [pscustomobject]@{
        Name = 'CodegenCS.Tools.CliTool.Tests'
        Path = 'Tools/CodegenCS.Tools.CliTool.Tests/CodegenCS.Tools.CliTool.Tests.csproj'
        Report = 'CodegenCS.Tools.CliTool.Tests.trx'
    }
)

New-Item -ItemType Directory -Force -Path $artifactsDirectory | Out-Null
$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

Push-Location $PSScriptRoot
try {
    foreach ($testProject in $testProjects) {
        $reportPath = Join-Path $artifactsDirectory $testProject.Report
        Remove-Item -Force -ErrorAction Ignore $reportPath

        $projectPath = Join-Path $PSScriptRoot $testProject.Path
        Write-Host "Running $($testProject.Name)..." -ForegroundColor Cyan
        $testArguments = @(
            'test',
            $projectPath,
            '--configuration', $Configuration,
            '--logger', "trx;LogFileName=$($testProject.Report)",
            '--results-directory', $artifactsDirectory,
            "-p:NETCoreAppMaximumVersion=$netCoreAppMaximumVersion"
        )

        $exitCode = 1
        $executionError = $null
        try {
            & dotnet @testArguments
            $exitCode = $LASTEXITCODE
        } catch {
            $executionError = $_.Exception.Message
            Write-Warning $executionError
        }

        $passed = 0
        $failed = 0
        $skipped = 0
        $total = 0
        $projectFailures = [System.Collections.Generic.List[string]]::new()
        if (Test-Path $reportPath) {
            try {
                [xml]$trx = Get-Content -Path $reportPath -Raw
                $counters = $trx.TestRun.ResultSummary.Counters
                $total = [int]$counters.GetAttribute('total')
                $passed = [int]$counters.GetAttribute('passed')
                $failed = [int]$counters.GetAttribute('failed')
                $skipped = [int]$counters.GetAttribute('notExecuted') +
                    [int]$counters.GetAttribute('notRunnable') +
                    [int]$counters.GetAttribute('inconclusive')

                foreach ($failedTest in $trx.SelectNodes("//*[local-name()='UnitTestResult' and @outcome='Failed']")) {
                    $testName = $failedTest.GetAttribute('testName')
                    $messageNode = $failedTest.SelectSingleNode("./*[local-name()='Output']/*[local-name()='ErrorInfo']/*[local-name()='Message']")
                    $message = if ($messageNode) { $messageNode.InnerText -replace '\s+', ' ' } else { 'No failure message in TRX.' }
                    $projectFailures.Add("$testName`: $message")
                }
            } catch {
                $executionError = "Could not parse TRX report: $($_.Exception.Message)"
            }
        } else {
            $executionError = 'No TRX report was produced.'
        }
        if ($exitCode -ne 0 -and $failed -eq 0 -and -not $executionError) {
            $executionError = "dotnet test exited with code $exitCode without failed test cases."
        }

        $status = if ($exitCode -eq 0 -and -not $executionError -and $failed -eq 0) { 'Passed' } else { 'Failed' }
        if ($executionError) {
            $failures.Add("$($testProject.Name): $executionError")
        }
        foreach ($failure in $projectFailures) {
            $failures.Add("$($testProject.Name): $failure")
        }

        $results.Add([pscustomobject]@{
            Name = $testProject.Name
            Report = $testProject.Report
            Status = $status
            Passed = $passed
            Failed = $failed
            Skipped = $skipped
            Total = $total
            Failures = $projectFailures.ToArray()
            ExecutionError = $executionError
        })
    }
} finally {
    Pop-Location
}

$overallStatus = if (@($results | Where-Object Status -eq 'Failed').Count -eq 0) { 'Passed' } else { 'Failed' }
$totalPassed = ($results | Measure-Object -Property Passed -Sum).Sum
$totalFailed = ($results | Measure-Object -Property Failed -Sum).Sum
$totalSkipped = ($results | Measure-Object -Property Skipped -Sum).Sum
$totalTests = ($results | Measure-Object -Property Total -Sum).Sum
$runTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add('# Test Run Summary')
$summaryLines.Add('')
$summaryLines.Add("- **Result:** $overallStatus")
$summaryLines.Add("- **Configuration:** $Configuration")
$summaryLines.Add("- **Target framework:** net$netCoreAppMaximumVersion")
$summaryLines.Add("- **Completed:** $runTime")
$summaryLines.Add("- **Totals:** $totalPassed passed, $totalFailed failed, $totalSkipped skipped, $totalTests total")
$summaryLines.Add('')
$summaryLines.Add('| Test project | Result | Passed | Failed | Skipped | Total | TRX report |')
$summaryLines.Add('| --- | --- | ---: | ---: | ---: | ---: | --- |')
foreach ($result in $results) {
    $summaryLines.Add("| $($result.Name) | $($result.Status) | $($result.Passed) | $($result.Failed) | $($result.Skipped) | $($result.Total) | [$($result.Report)]($($result.Report)) |")
}
$summaryLines.Add("| **Total** | **$overallStatus** | **$totalPassed** | **$totalFailed** | **$totalSkipped** | **$totalTests** | |")

if ($failures.Count -gt 0) {
    $summaryLines.Add('')
    $summaryLines.Add('## Failures')
    foreach ($failure in $failures) {
        $summaryLines.Add("- $($failure -replace '\|', '\|' -replace '[\r\n]+', ' ')")
    }
}

Set-Content -Path $summaryPath -Value $summaryLines -Encoding utf8
Write-Host "Test summary: $summaryPath"
if ($overallStatus -eq 'Failed') {
    throw "One or more test projects failed. See $summaryPath"
}
