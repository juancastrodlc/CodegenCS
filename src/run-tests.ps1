#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$artifactsDirectory = Join-Path $PSScriptRoot 'artifacts'
$resultsDirectory = Join-Path $artifactsDirectory 'test-results'
$summaryPath = Join-Path $artifactsDirectory 'test-summary.md'

if ($IsLinux) {
    $solutionFile = 'CodegenCS.slnf'
} elseif ($IsWindows) {
    $solutionFile = 'CodegenCS.sln'
} else {
    throw 'Tests can only be run in a Linux or Windows environment.'
}

$solutionPath = Join-Path $PSScriptRoot $solutionFile

New-Item -ItemType Directory -Force -Path $artifactsDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
Get-ChildItem -Path $resultsDirectory -Filter '*.trx' -File -Recurse |
    Remove-Item -Force

$failures = [System.Collections.Generic.List[string]]::new()
$executionError = $null
$exitCode = 1

Push-Location $PSScriptRoot
try {
    Write-Host "Running tests from $solutionFile..." -ForegroundColor Cyan
    try {
        & dotnet test $solutionPath `
            --configuration $Configuration `
            --logger trx `
            --results-directory $resultsDirectory
        $exitCode = $LASTEXITCODE
    } catch {
        $executionError = $_.Exception.Message
        Write-Warning $executionError
    }
} finally {
    Pop-Location
}

$reports = @(Get-ChildItem -Path $resultsDirectory -Filter '*.trx' -File -Recurse)
$results = [System.Collections.Generic.List[object]]::new()
foreach ($report in $reports) {
    $passed = 0
    $failed = 0
    $skipped = 0
    $total = 0
    $reportPath = $report.FullName
    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($report.Name)
    try {
        [xml]$trx = Get-Content -Path $report.FullName -Raw
        $counters = $trx.SelectSingleNode("//*[local-name()='ResultSummary']/*[local-name()='Counters']")
        if (-not $counters) {
            throw 'TRX report does not contain test counters.'
        }
        $total = [int]$counters.GetAttribute('total')
        $passed = [int]$counters.GetAttribute('passed')
        $failed = [int]$counters.GetAttribute('failed')
        $skipped = [int]$counters.GetAttribute('notExecuted') +
            [int]$counters.GetAttribute('notRunnable') +
            [int]$counters.GetAttribute('inconclusive')

        $runOutput = ($trx.GetElementsByTagName('StdOut') | ForEach-Object InnerText) -join "`n"
        $assemblyMatch = [regex]::Match($runOutput, 'Running all tests in (?<assembly>.+?\.dll)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($assemblyMatch.Success) {
            $assemblyPath = $assemblyMatch.Groups['assembly'].Value.Trim()
            $displayName = [System.IO.Path]::GetFileNameWithoutExtension($assemblyPath)
            $frameworkMatch = [regex]::Match($assemblyPath, '[/\\]bin[/\\][^/\\]+[/\\](?<framework>[^/\\]+)[/\\][^/\\]+\.dll$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $reportBaseName = if ($frameworkMatch.Success) {
                "$($displayName)_$($frameworkMatch.Groups['framework'].Value)"
            } else {
                $displayName
            }
            $renamedReportPath = Join-Path $report.DirectoryName "$reportBaseName.trx"
            if ($renamedReportPath -ne $report.FullName -and -not (Test-Path $renamedReportPath)) {
                Move-Item -LiteralPath $report.FullName -Destination $renamedReportPath
                $reportPath = $renamedReportPath
            }
        }

        foreach ($failedTest in $trx.SelectNodes("//*[local-name()='UnitTestResult' and @outcome='Failed']")) {
            $testName = $failedTest.GetAttribute('testName')
            $messageNode = $failedTest.SelectSingleNode("./*[local-name()='Output']/*[local-name()='ErrorInfo']/*[local-name()='Message']")
            $message = if ($messageNode) { $messageNode.InnerText -replace '\s+', ' ' } else { 'No failure message in TRX.' }
            $failures.Add("$testName`: $message")
        }
    } catch {
        $executionError = "Could not parse TRX report $($report.Name): $($_.Exception.Message)"
    }

    $relativeReportPath = [System.IO.Path]::GetRelativePath($artifactsDirectory, $reportPath) -replace '\\', '/'
    $results.Add([pscustomobject]@{
        Name = $displayName
        Report = $relativeReportPath
        Passed = $passed
        Failed = $failed
        Skipped = $skipped
        Total = $total
    })
}

if ($reports.Count -eq 0 -and -not $executionError) {
    $executionError = 'No TRX report was produced.'
}
if ($exitCode -ne 0 -and ($results | Measure-Object -Property Failed -Sum).Sum -eq 0 -and -not $executionError) {
    $executionError = "dotnet test exited with code $exitCode without failed test cases."
}
if ($executionError) {
    $failures.Insert(0, $executionError)
}

$totalPassed = ($results | Measure-Object -Property Passed -Sum).Sum
$totalFailed = ($results | Measure-Object -Property Failed -Sum).Sum
$totalSkipped = ($results | Measure-Object -Property Skipped -Sum).Sum
$totalTests = ($results | Measure-Object -Property Total -Sum).Sum
if ($null -eq $totalPassed) { $totalPassed = 0 }
if ($null -eq $totalFailed) { $totalFailed = 0 }
if ($null -eq $totalSkipped) { $totalSkipped = 0 }
if ($null -eq $totalTests) { $totalTests = 0 }

$overallStatus = if ($exitCode -eq 0 -and -not $executionError -and $totalFailed -eq 0) { 'Passed' } else { 'Failed' }
$runTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add('# Test Run Summary')
$summaryLines.Add('')
$summaryLines.Add("- **Result:** $overallStatus")
$summaryLines.Add("- **Configuration:** $Configuration")
$summaryLines.Add("- **Solution:** $solutionFile")
$summaryLines.Add("- **Completed:** $runTime")
$summaryLines.Add("- **Totals:** $totalPassed passed, $totalFailed failed, $totalSkipped skipped, $totalTests total")
$summaryLines.Add('')
$summaryLines.Add('| Test report | Passed | Failed | Skipped | Total | TRX report |')
$summaryLines.Add('| --- | ---: | ---: | ---: | ---: | --- |')
foreach ($result in $results) {
    $summaryLines.Add("| $($result.Name) | $($result.Passed) | $($result.Failed) | $($result.Skipped) | $($result.Total) | [$($result.Name).trx]($($result.Report)) |")
}
$summaryLines.Add("| **Total** | **$totalPassed** | **$totalFailed** | **$totalSkipped** | **$totalTests** | |")

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
    throw "One or more tests failed. See $summaryPath"
}
