# Coverage-Report.ps1 - Nova Bot Test Coverage Analysis Tool
# Creators: Tyler McKendry & Nova

param(
    [switch]$RunTests,
    [switch]$HTML,
    [switch]$Detailed,
    [string]$OutputPath,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# Initialize coverage report structure
$script:CoverageReport = @{
    Metadata = @{
        Timestamp = Get-Date
        Version = "1.0.0"
        ProjectRoot = Split-Path -Parent $PSScriptRoot
    }
    Summary = @{
        TotalFiles = 0
        TestedFiles = 0
        CoveragePercentage = 0
        TotalFunctions = 0
        TestedFunctions = 0
        FunctionCoverage = 0
        TestFiles = 0
        TestCases = 0
        PassedTests = 0
        FailedTests = 0
        Grade = ""
    }
    Files = @{}
    TestResults = @{}
    Recommendations = @()
}

# Color scheme
$script:Colors = @{
    Excellent = "Green"
    Good = "Cyan"
    Fair = "Yellow"
    Poor = "Red"
    Info = "White"
    Header = "Magenta"
}

function Write-CoverageLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = $script:Colors[$Level]
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
    Write-Verbose $Message
}

function Get-CoverageGrade {
    param([double]$Percentage)
    
    switch ($Percentage) {
        { $_ -ge 90 } { return "A+" }
        { $_ -ge 85 } { return "A" }
        { $_ -ge 80 } { return "A-" }
        { $_ -ge 75 } { return "B+" }
        { $_ -ge 70 } { return "B" }
        { $_ -ge 65 } { return "B-" }
        { $_ -ge 60 } { return "C+" }
        { $_ -ge 55 } { return "C" }
        { $_ -ge 50 } { return "C-" }
        default { return "D" }
    }
}

function Get-CoverageColor {
    param([double]$Percentage)
    
    switch ($Percentage) {
        { $_ -ge 80 } { return "Excellent" }
        { $_ -ge 70 } { return "Good" }
        { $_ -ge 60 } { return "Fair" }
        default { return "Poor" }
    }
}

function Get-PowerShellFunctions {
    param([string]$FilePath)
    
    $functions = @()
    
    try {
        $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content)) { return $functions }
        
        # Match function definitions
        $functionPattern = '(?m)^\s*function\s+([A-Za-z][\w-]*)'
        $matches = [regex]::Matches($content, $functionPattern)
        
        foreach ($match in $matches) {
            $functions += @{
                Name = $match.Groups[1].Value
                Line = ($content.Substring(0, $match.Index) -split "`n").Count
                Tested = $false
            }
        }
        
        # Also match advanced functions (functions with [CmdletBinding()])
        $advancedFunctionPattern = '(?ms)\[CmdletBinding\(\)\]\s*param\s*\([^)]*\)\s*(?:begin\s*{[^}]*})?\s*(?:process\s*{[^}]*})?\s*(?:end\s*{[^}]*})?'
        $advMatches = [regex]::Matches($content, $advancedFunctionPattern)
        
        # Look for function names before these advanced function blocks
        foreach ($match in $advMatches) {
            $precedingText = $content.Substring([Math]::Max(0, $match.Index - 200), [Math]::Min(200, $match.Index))
            if ($precedingText -match 'function\s+([A-Za-z][\w-]*)') {
                $functionName = $matches[0].Groups[1].Value
                if (-not ($functions | Where-Object { $_.Name -eq $functionName })) {
                    $functions += @{
                        Name = $functionName
                        Line = ($content.Substring(0, $match.Index) -split "`n").Count
                        Tested = $false
                    }
                }
            }
        }
        
    } catch {
        Write-CoverageLog "Error analyzing functions in $FilePath: $($_.Exception.Message)" -Level "Poor"
    }
    
    return $functions
}

function Test-FunctionCoverage {
    param([string]$FunctionName, [array]$TestFiles)
    
    foreach ($testFile in $TestFiles) {
        try {
            $testContent = Get-Content $testFile -Raw -ErrorAction SilentlyContinue
            if ($testContent -match [regex]::Escape($FunctionName)) {
                return $true
            }
        } catch {
            # Continue to next test file
        }
    }
    
    return $false
}

function Invoke-TestSuite {
    if (-not $RunTests) {
        Write-CoverageLog "Skipping test execution (use -RunTests to run)" -Level "Info"
        return @{
            TestFiles = 0
            TestCases = 0
            Passed = 0
            Failed = 0
            Results = @()
        }
    }
    
    Write-CoverageLog "Running test suite with Pester..." -Level "Info"
    
    $projectRoot = $script:CoverageReport.Metadata.ProjectRoot
    $testDir = Join-Path $projectRoot "tests"
    
    if (-not (Test-Path $testDir)) {
        Write-CoverageLog "No tests directory found at $testDir" -Level "Fair"
        return @{
            TestFiles = 0
            TestCases = 0
            Passed = 0
            Failed = 0
            Results = @()
        }
    }
    
    # Check for Pester
    try {
        Import-Module Pester -MinimumVersion 5.0 -Force -ErrorAction Stop
        Write-CoverageLog "Pester v$($(Get-Module Pester).Version) loaded successfully" -Level "Good"
    } catch {
        Write-CoverageLog "Pester v5+ not available. Installing..." -Level "Fair"
        try {
            Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
            Import-Module Pester -MinimumVersion 5.0 -Force
        } catch {
            Write-CoverageLog "Failed to install Pester: $($_.Exception.Message)" -Level "Poor"
            return @{
                TestFiles = 0
                TestCases = 0
                Passed = 0
                Failed = 0
                Results = @()
                Error = "Pester installation failed"
            }
        }
    }
    
    # Run tests
    try {
        $testFiles = Get-ChildItem -Path $testDir -Filter "*.Tests.ps1"
        
        if ($testFiles.Count -eq 0) {
            Write-CoverageLog "No test files found in $testDir" -Level "Fair"
            return @{
                TestFiles = 0
                TestCases = 0
                Passed = 0
                Failed = 0
                Results = @()
            }
        }
        
        Write-CoverageLog "Running $($testFiles.Count) test file(s)..." -Level "Info"
        
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = $testDir
        $pesterConfig.Output.Verbosity = if ($Verbose) { "Detailed" } else { "Normal" }
        $pesterConfig.TestResult.Enabled = $true
        $pesterConfig.TestResult.OutputPath = Join-Path $projectRoot "test-results.xml"
        
        $result = Invoke-Pester -Configuration $pesterConfig
        
        return @{
            TestFiles = $testFiles.Count
            TestCases = $result.TotalCount
            Passed = $result.PassedCount
            Failed = $result.FailedCount
            Results = $result.Tests
            Duration = $result.Duration
        }
        
    } catch {
        Write-CoverageLog "Error running tests: $($_.Exception.Message)" -Level "Poor"
        return @{
            TestFiles = 0
            TestCases = 0
            Passed = 0
            Failed = 0
            Results = @()
            Error = $_.Exception.Message
        }
    }
}

function Analyze-CodeCoverage {
    Write-CoverageLog "Analyzing code coverage..." -Level "Info"
    
    $projectRoot = $script:CoverageReport.Metadata.ProjectRoot
    
    # Get all PowerShell files
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1" |
        Where-Object { 
            -not $_.FullName.Contains("Archive") -and 
            -not $_.FullName.Contains(".git") -and
            -not $_.FullName.Contains("tests") -and
            -not $_.Name.EndsWith(".Tests.ps1")
        }
    
    # Get test files
    $testDir = Join-Path $projectRoot "tests"
    $testFiles = @()
    if (Test-Path $testDir) {
        $testFiles = Get-ChildItem -Path $testDir -Filter "*.Tests.ps1" | ForEach-Object { $_.FullName }
    }
    
    Write-CoverageLog "Analyzing $($psFiles.Count) source files against $($testFiles.Count) test files" -Level "Info"
    
    $totalFunctions = 0
    $testedFunctions = 0
    $testedFiles = 0
    
    foreach ($file in $psFiles) {
        $relativePath = $file.FullName.Replace($projectRoot, "").TrimStart("\")
        $functions = Get-PowerShellFunctions -FilePath $file.FullName
        
        $fileCoverage = @{
            Path = $relativePath
            FullPath = $file.FullName
            Functions = $functions
            TotalFunctions = $functions.Count
            TestedFunctions = 0
            CoveragePercentage = 0
            HasTests = $false
        }
        
        # Check if file has corresponding test file
        $expectedTestFile = $file.BaseName + ".Tests.ps1"
        $hasDirectTest = $testFiles | Where-Object { 
            (Split-Path $_ -Leaf) -eq $expectedTestFile 
        }
        
        if ($hasDirectTest) {
            $fileCoverage.HasTests = $true
            $testedFiles++
        }
        
        # Check function coverage
        foreach ($function in $functions) {
            $totalFunctions++
            
            if (Test-FunctionCoverage -FunctionName $function.Name -TestFiles $testFiles) {
                $function.Tested = $true
                $fileCoverage.TestedFunctions++
                $testedFunctions++
            }
        }
        
        # Calculate file coverage percentage
        if ($functions.Count -gt 0) {
            $fileCoverage.CoveragePercentage = [Math]::Round(($fileCoverage.TestedFunctions / $functions.Count) * 100, 1)
        }
        
        $script:CoverageReport.Files[$relativePath] = $fileCoverage
    }
    
    # Update summary
    $script:CoverageReport.Summary.TotalFiles = $psFiles.Count
    $script:CoverageReport.Summary.TestedFiles = $testedFiles
    $script:CoverageReport.Summary.TotalFunctions = $totalFunctions
    $script:CoverageReport.Summary.TestedFunctions = $testedFunctions
    $script:CoverageReport.Summary.TestFiles = $testFiles.Count
    
    # Calculate coverage percentages
    if ($psFiles.Count -gt 0) {
        $script:CoverageReport.Summary.CoveragePercentage = [Math]::Round(($testedFiles / $psFiles.Count) * 100, 1)
    }
    
    if ($totalFunctions -gt 0) {
        $script:CoverageReport.Summary.FunctionCoverage = [Math]::Round(($testedFunctions / $totalFunctions) * 100, 1)
    }
    
    $script:CoverageReport.Summary.Grade = Get-CoverageGrade $script:CoverageReport.Summary.FunctionCoverage
    
    Write-CoverageLog "Coverage analysis complete" -Level "Good"
}

function Generate-Recommendations {
    $recommendations = @()
    $summary = $script:CoverageReport.Summary
    
    if ($summary.TestFiles -eq 0) {
        $recommendations += "Create test files using Pester framework"
    }
    
    if ($summary.CoveragePercentage -lt 50) {
        $recommendations += "Increase file test coverage to at least 50%"
    }
    
    if ($summary.FunctionCoverage -lt 70) {
        $recommendations += "Add tests for more functions to reach 70% function coverage"
    }
    
    if ($summary.FailedTests -gt 0) {
        $recommendations += "Fix $($summary.FailedTests) failing test(s)"
    }
    
    # Find files with no coverage
    $uncoveredFiles = $script:CoverageReport.Files.GetEnumerator() | 
        Where-Object { $_.Value.CoveragePercentage -eq 0 -and $_.Value.TotalFunctions -gt 0 } |
        Select-Object -First 5
    
    if ($uncoveredFiles.Count -gt 0) {
        $fileList = ($uncoveredFiles | ForEach-Object { $_.Key }) -join ", "
        $recommendations += "Add tests for uncovered files: $fileList"
    }
    
    # Find functions with no coverage
    $uncoveredFunctions = @()
    foreach ($file in $script:CoverageReport.Files.Values) {
        $uncoveredFunctions += $file.Functions | Where-Object { -not $_.Tested } | Select-Object -First 3
    }
    
    if ($uncoveredFunctions.Count -gt 0) {
        $functionList = ($uncoveredFunctions | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ", "
        $recommendations += "Add tests for uncovered functions: $functionList"
    }
    
    if ($summary.CoveragePercentage -ge 80 -and $summary.FunctionCoverage -ge 80) {
        $recommendations += "Excellent coverage! Consider adding integration tests"
    }
    
    $script:CoverageReport.Recommendations = $recommendations
}

function Format-ConsoleOutput {
    $report = $script:CoverageReport
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $script:Colors.Header
    Write-Host "║                    NOVA COVERAGE REPORT                      ║" -ForegroundColor $script:Colors.Header  
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $script:Colors.Header
    Write-Host ""
    
    # Summary
    $coverageColor = Get-CoverageColor $report.Summary.FunctionCoverage
    Write-Host "📊 FUNCTION COVERAGE: " -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($report.Summary.FunctionCoverage)%" -NoNewline -ForegroundColor $script:Colors[$coverageColor]
    Write-Host " (" -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($report.Summary.Grade)" -NoNewline -ForegroundColor $script:Colors[$coverageColor]
    Write-Host ")" -ForegroundColor $script:Colors.Info
    
    $fileCoverageColor = Get-CoverageColor $report.Summary.CoveragePercentage
    Write-Host "📄 FILE COVERAGE: " -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($report.Summary.CoveragePercentage)%" -NoNewline -ForegroundColor $script:Colors[$fileCoverageColor]
    Write-Host " ($($report.Summary.TestedFiles)/$($report.Summary.TotalFiles) files)" -ForegroundColor $script:Colors.Info
    
    Write-Host "🔧 FUNCTIONS: $($report.Summary.TestedFunctions)/$($report.Summary.TotalFunctions) tested" -ForegroundColor $script:Colors.Info
    Write-Host "🧪 TEST FILES: $($report.Summary.TestFiles)" -ForegroundColor $script:Colors.Info
    
    if ($report.Summary.TestCases -gt 0) {
        Write-Host "✅ TEST RESULTS: $($report.Summary.PassedTests)/$($report.Summary.TestCases) passed" -ForegroundColor $script:Colors.Info
        if ($report.Summary.FailedTests -gt 0) {
            Write-Host "❌ FAILED TESTS: $($report.Summary.FailedTests)" -ForegroundColor $script:Colors.Poor
        }
    }
    
    Write-Host "📅 GENERATED: $($report.Metadata.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor $script:Colors.Info
    Write-Host ""
    
    # File Coverage (top 10 best and worst)
    if ($report.Files.Count -gt 0) {
        Write-Host "📈 TOP COVERED FILES:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        $topFiles = $report.Files.GetEnumerator() | 
            Where-Object { $_.Value.TotalFunctions -gt 0 } |
            Sort-Object { $_.Value.CoveragePercentage } -Descending |
            Select-Object -First 5
        
        foreach ($file in $topFiles) {
            $coverageColor = Get-CoverageColor $file.Value.CoveragePercentage
            $fileName = $file.Key.Split('\')[-1].PadRight(30)
            Write-Host "  $fileName" -NoNewline -ForegroundColor $script:Colors.Info
            Write-Host "$($file.Value.CoveragePercentage)% " -NoNewline -ForegroundColor $script:Colors[$coverageColor]
            Write-Host "($($file.Value.TestedFunctions)/$($file.Value.TotalFunctions))" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "📉 FILES NEEDING COVERAGE:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        $worstFiles = $report.Files.GetEnumerator() | 
            Where-Object { $_.Value.TotalFunctions -gt 0 -and $_.Value.CoveragePercentage -lt 50 } |
            Sort-Object { $_.Value.CoveragePercentage } |
            Select-Object -First 5
        
        if ($worstFiles.Count -eq 0) {
            Write-Host "  🎉 All files with functions have good coverage!" -ForegroundColor $script:Colors.Excellent
        } else {
            foreach ($file in $worstFiles) {
                $coverageColor = Get-CoverageColor $file.Value.CoveragePercentage
                $fileName = $file.Key.Split('\')[-1].PadRight(30)
                Write-Host "  $fileName" -NoNewline -ForegroundColor $script:Colors.Info
                Write-Host "$($file.Value.CoveragePercentage)% " -NoNewline -ForegroundColor $script:Colors[$coverageColor]
                Write-Host "($($file.Value.TestedFunctions)/$($file.Value.TotalFunctions))" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    # Detailed function coverage
    if ($Detailed -and $report.Files.Count -gt 0) {
        Write-Host "🔍 DETAILED FUNCTION COVERAGE:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        foreach ($file in $report.Files.GetEnumerator() | Where-Object { $_.Value.TotalFunctions -gt 0 }) {
            Write-Host ""
            Write-Host "📂 $($file.Key)" -ForegroundColor $script:Colors.Header
            
            foreach ($function in $file.Value.Functions) {
                $status = if ($function.Tested) { "✅" } else { "❌" }
                $color = if ($function.Tested) { $script:Colors.Good } else { $script:Colors.Poor }
                Write-Host "   $status $($function.Name) (Line $($function.Line))" -ForegroundColor $color
            }
        }
        Write-Host ""
    }
    
    # Recommendations
    if ($report.Recommendations.Count -gt 0) {
        Write-Host "💡 RECOMMENDATIONS:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        for ($i = 0; $i -lt $report.Recommendations.Count; $i++) {
            Write-Host "  $($i + 1). $($report.Recommendations[$i])" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}

function Export-CoverageHtml {
    param([string]$Path)
    
    $report = $script:CoverageReport
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Nova Coverage Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 20px; margin-bottom: 30px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .metric { background: #ecf0f1; padding: 15px; border-radius: 6px; text-align: center; }
        .metric .value { font-size: 2em; font-weight: bold; }
        .metric .label { font-size: 0.9em; color: #666; margin-top: 5px; }
        .coverage-high { color: #27ae60; }
        .coverage-medium { color: #f39c12; }
        .coverage-low { color: #e74c3c; }
        .file-list { margin: 20px 0; }
        .file-item { display: flex; justify-content: space-between; padding: 8px; margin: 2px 0; background: #f8f9fa; border-radius: 4px; }
        .function-list { margin-left: 20px; font-size: 0.9em; }
        .tested { color: #27ae60; }
        .untested { color: #e74c3c; }
        .recommendations { background: #fff3cd; padding: 15px; border-radius: 6px; border-left: 4px solid #ffc107; margin-top: 20px; }
        ul { padding-left: 20px; }
        li { margin: 5px 0; }
        .progress-bar { width: 100%; height: 20px; background: #ecf0f1; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #e74c3c 0%, #f39c12 50%, #27ae60 100%); transition: width 0.3s ease; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Nova Coverage Report</h1>
            <p>Generated: $($report.Metadata.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        </div>
        
        <div class="summary">
            <div class="metric">
                <div class="value coverage-$(if($report.Summary.FunctionCoverage -ge 80){'high'}elseif($report.Summary.FunctionCoverage -ge 60){'medium'}else{'low'})">
                    $($report.Summary.FunctionCoverage)%
                </div>
                <div class="label">Function Coverage</div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: $($report.Summary.FunctionCoverage)%"></div>
                </div>
            </div>
            
            <div class="metric">
                <div class="value coverage-$(if($report.Summary.CoveragePercentage -ge 80){'high'}elseif($report.Summary.CoveragePercentage -ge 60){'medium'}else{'low'})">
                    $($report.Summary.CoveragePercentage)%
                </div>
                <div class="label">File Coverage</div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: $($report.Summary.CoveragePercentage)%"></div>
                </div>
            </div>
            
            <div class="metric">
                <div class="value">$($report.Summary.TestedFunctions)/$($report.Summary.TotalFunctions)</div>
                <div class="label">Functions Tested</div>
            </div>
            
            <div class="metric">
                <div class="value">$($report.Summary.TestFiles)</div>
                <div class="label">Test Files</div>
            </div>
        </div>
"@

    if ($report.Summary.TestCases -gt 0) {
        $html += @"
        <div class="summary">
            <div class="metric">
                <div class="value coverage-$(if($report.Summary.FailedTests -eq 0){'high'}else{'low'})">
                    $($report.Summary.PassedTests)/$($report.Summary.TestCases)
                </div>
                <div class="label">Tests Passed</div>
            </div>
        </div>
"@
    }

    $html += @"
        <h3>📄 File Coverage Details</h3>
        <div class="file-list">
"@

    foreach ($file in $report.Files.GetEnumerator() | Sort-Object { $_.Value.CoveragePercentage } -Descending) {
        $coverageClass = if ($file.Value.CoveragePercentage -ge 80) { "coverage-high" } 
                        elseif ($file.Value.CoveragePercentage -ge 60) { "coverage-medium" } 
                        else { "coverage-low" }
        
        $html += @"
            <div class="file-item">
                <span>$($file.Key)</span>
                <span class="$coverageClass">$($file.Value.CoveragePercentage)% ($($file.Value.TestedFunctions)/$($file.Value.TotalFunctions))</span>
            </div>
"@

        if ($Detailed -and $file.Value.Functions.Count -gt 0) {
            $html += "<div class='function-list'>"
            foreach ($function in $file.Value.Functions) {
                $functionClass = if ($function.Tested) { "tested" } else { "untested" }
                $symbol = if ($function.Tested) { "✅" } else { "❌" }
                $html += "<div class='$functionClass'>$symbol $($function.Name) (Line $($function.Line))</div>"
            }
            $html += "</div>"
        }
    }

    $html += @"
        </div>
        
        <div class="recommendations">
            <h3>💡 Recommendations</h3>
            <ul>
$(($report.Recommendations | ForEach-Object { "                <li>$_</li>" }) -join "`n")
            </ul>
        </div>
    </div>
</body>
</html>
"@

    if ($Path) {
        Set-Content -Path $Path -Value $html -Encoding UTF8
        Write-CoverageLog "HTML coverage report exported to: $Path" -Level "Good"
    } else {
        return $html
    }
}

# Main execution
try {
    Write-CoverageLog "Starting Nova Coverage Analysis..." -Level "Header"
    
    # Run tests if requested
    if ($RunTests) {
        $testResults = Invoke-TestSuite
        $script:CoverageReport.Summary.TestFiles = $testResults.TestFiles
        $script:CoverageReport.Summary.TestCases = $testResults.TestCases
        $script:CoverageReport.Summary.PassedTests = $testResults.Passed
        $script:CoverageReport.Summary.FailedTests = $testResults.Failed
        $script:CoverageReport.TestResults = $testResults
    }
    
    # Analyze coverage
    Analyze-CodeCoverage
    
    # Generate recommendations
    Generate-Recommendations
    
    # Output results
    if ($HTML) {
        if ($OutputPath) {
            Export-CoverageHtml -Path $OutputPath
        } else {
            $htmlFile = Join-Path $script:CoverageReport.Metadata.ProjectRoot "coverage-report.html"
            Export-CoverageHtml -Path $htmlFile
            Write-CoverageLog "Opening HTML report..." -Level "Good"
            Start-Process $htmlFile
        }
    } else {
        Format-ConsoleOutput
    }
    
    Write-CoverageLog "Coverage Analysis Complete! Function Coverage: $($script:CoverageReport.Summary.FunctionCoverage)% ($($script:CoverageReport.Summary.Grade))" -Level $(Get-CoverageColor $script:CoverageReport.Summary.FunctionCoverage)
    
} catch {
    Write-Error "Coverage analysis failed: $($_.Exception.Message)"
    exit 1
}