# Quality-Scorecard.ps1 - Nova Bot Quality Assessment Tool
# Creators: Tyler McKendry & Nova

param(
    [switch]$Detailed,
    [switch]$Quick,
    [ValidateSet("Console", "JSON", "HTML")]$OutputFormat = "Console",
    [string]$OutputPath,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# Initialize scorecard structure
$script:Scorecard = @{
    Metadata = @{
        Timestamp = Get-Date
        Version = "1.0.0"
        ProjectRoot = Split-Path -Parent $PSScriptRoot
        TotalDimensions = 8
    }
    Dimensions = @{}
    Summary = @{
        OverallScore = 0.0
        Grade = ""
        TotalPoints = 0
        MaxPoints = 0
        Recommendations = @()
    }
}

# Color scheme for console output
$script:Colors = @{
    Excellent = "Green"
    Good = "Cyan" 
    Fair = "Yellow"
    Poor = "Red"
    Info = "White"
    Header = "Magenta"
}

function Write-ScorecardLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = $script:Colors[$Level]
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
    Write-Verbose $Message
}

function Get-ScoreGrade {
    param([double]$Score)
    
    switch ($Score) {
        { $_ -ge 9.0 } { return "A+" }
        { $_ -ge 8.5 } { return "A" }
        { $_ -ge 8.0 } { return "A-" }
        { $_ -ge 7.5 } { return "B+" }
        { $_ -ge 7.0 } { return "B" }
        { $_ -ge 6.5 } { return "B-" }
        { $_ -ge 6.0 } { return "C+" }
        { $_ -ge 5.5 } { return "C" }
        { $_ -ge 5.0 } { return "C-" }
        default { return "D" }
    }
}

function Get-ScoreColor {
    param([double]$Score)
    
    switch ($Score) {
        { $_ -ge 8.0 } { return "Excellent" }
        { $_ -ge 7.0 } { return "Good" }
        { $_ -ge 6.0 } { return "Fair" }
        default { return "Poor" }
    }
}

function Test-CodeOrganization {
    Write-ScorecardLog "Analyzing Code Organization..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check directory structure (2 points)
    $expectedDirs = @("bot", "tools", "tests", "docs", ".github")
    $foundDirs = Get-ChildItem -Path $projectRoot -Directory | Select-Object -ExpandProperty Name
    $dirScore = ($expectedDirs | Where-Object { $_ -in $foundDirs }).Count / $expectedDirs.Count * 2
    $score += $dirScore
    $details += "Directory Structure: $([math]::Round($dirScore, 1))/2.0"
    
    # Check module organization (3 points)
    $moduleDir = Join-Path $projectRoot "bot\modules"
    if (Test-Path $moduleDir) {
        $modules = Get-ChildItem -Path $moduleDir -Filter "*.psm1"
        $moduleScore = [math]::Min($modules.Count / 5 * 3, 3)
        $score += $moduleScore
        $details += "Module Organization: $([math]::Round($moduleScore, 1))/3.0 ($($modules.Count) modules)"
    } else {
        $details += "Module Organization: 0.0/3.0 (no modules directory)"
    }
    
    # Check naming conventions (2 points)
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps*" | Where-Object { -not $_.FullName.Contains("Archive") }
    $properNaming = $psFiles | Where-Object { $_.BaseName -match "^[A-Z][a-zA-Z0-9-]*$" }
    $namingScore = ($properNaming.Count / $psFiles.Count) * 2
    $score += $namingScore
    $details += "Naming Conventions: $([math]::Round($namingScore, 1))/2.0"
    
    # Check file size distribution (2 points)
    $oversizedFiles = $psFiles | Where-Object { $_.Length -gt 100KB }
    $sizeScore = [math]::Max(0, 2 - ($oversizedFiles.Count / [math]::Max($psFiles.Count / 10, 1)))
    $score += $sizeScore
    $details += "File Size Distribution: $([math]::Round($sizeScore, 1))/2.0"
    
    # Check separation of concerns (1 point)
    $separationScore = if ((Test-Path (Join-Path $projectRoot "bot")) -and 
                          (Test-Path (Join-Path $projectRoot "tools")) -and 
                          (Test-Path (Join-Path $projectRoot "tests"))) { 1 } else { 0 }
    $score += $separationScore
    $details += "Separation of Concerns: $separationScore/1.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($dirScore -lt 2) { "Create missing standard directories: $($expectedDirs -join ', ')" }
            if ($moduleScore -lt 2) { "Organize code into reusable PowerShell modules" }
            if ($namingScore -lt 1.5) { "Improve file naming conventions (PascalCase)" }
            if ($oversizedFiles.Count -gt 0) { "Consider breaking down large files: $($oversizedFiles[0..2] | ForEach-Object { $_.Name })" }
        )
    }
}

function Test-DocumentationCoverage {
    Write-ScorecardLog "Analyzing Documentation Coverage..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check README quality (3 points)
    $readmePath = Join-Path $projectRoot "README.md"
    if (Test-Path $readmePath) {
        $readmeContent = Get-Content $readmePath -Raw
        $readmeScore = 0
        
        if ($readmeContent.Length -gt 1000) { $readmeScore += 1 }
        if ($readmeContent -match "## Features|## Installation|## Usage") { $readmeScore += 1 }
        if ($readmeContent -match "```") { $readmeScore += 1 }
        
        $score += $readmeScore
        $details += "README Quality: $readmeScore/3.0"
    } else {
        $details += "README Quality: 0/3.0 (missing)"
    }
    
    # Check inline documentation (3 points)
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps*" | Where-Object { -not $_.FullName.Contains("Archive") }
    $documentedFiles = 0
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "\.SYNOPSIS|\.DESCRIPTION|\<#") {
            $documentedFiles++
        }
    }
    
    $inlineScore = ($documentedFiles / [math]::Max($psFiles.Count, 1)) * 3
    $score += $inlineScore
    $details += "Inline Documentation: $([math]::Round($inlineScore, 1))/3.0 ($documentedFiles/$($psFiles.Count) files)"
    
    # Check API documentation (2 points)
    $apiDocs = @("docs", "API.md", "CONTRIBUTING.md") | ForEach-Object { 
        Test-Path (Join-Path $projectRoot $_) 
    }
    $apiScore = ($apiDocs | Where-Object { $_ }).Count / $apiDocs.Count * 2
    $score += $apiScore
    $details += "API Documentation: $([math]::Round($apiScore, 1))/2.0"
    
    # Check examples and tutorials (2 points)
    $exampleDirs = @("examples", "samples", "demos") | ForEach-Object {
        Test-Path (Join-Path $projectRoot $_)
    }
    $tutorialScore = ($exampleDirs | Where-Object { $_ }).Count / $exampleDirs.Count * 2
    $score += $tutorialScore
    $details += "Examples/Tutorials: $([math]::Round($tutorialScore, 1))/2.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($readmeScore -lt 2) { "Enhance README with features, installation, and usage sections" }
            if ($inlineScore -lt 2) { "Add inline documentation to more PowerShell functions" }
            if ($apiScore -lt 1.5) { "Create API documentation and contribution guidelines" }
            if ($tutorialScore -lt 1) { "Add examples and tutorials for common use cases" }
        )
    }
}

function Test-TestCoverage {
    Write-ScorecardLog "Analyzing Test Coverage..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check test existence (3 points)
    $testDir = Join-Path $projectRoot "tests"
    if (Test-Path $testDir) {
        $testFiles = Get-ChildItem -Path $testDir -Filter "*.Tests.ps1"
        $testScore = [math]::Min($testFiles.Count / 3 * 3, 3)
        $score += $testScore
        $details += "Test Files: $([math]::Round($testScore, 1))/3.0 ($($testFiles.Count) files)"
    } else {
        $details += "Test Files: 0/3.0 (no test directory)"
    }
    
    # Check test framework setup (2 points)
    $pesterScore = 0
    try {
        $pesterModule = Get-Module -Name Pester -ListAvailable | Select-Object -First 1
        if ($pesterModule -and $pesterModule.Version -ge [version]"5.0") {
            $pesterScore = 2
        } elseif ($pesterModule) {
            $pesterScore = 1
        }
    } catch {}
    
    $score += $pesterScore
    $details += "Test Framework: $pesterScore/2.0 (Pester v$($pesterModule.Version))"
    
    # Check CI integration (3 points)
    $ciFiles = @(".github\workflows\*.yml", ".github\workflows\*.yaml") | ForEach-Object {
        Get-ChildItem -Path (Join-Path $projectRoot $_) -ErrorAction SilentlyContinue
    } | Where-Object { $_ }
    
    $ciScore = if ($ciFiles) { 3 } else { 0 }
    $score += $ciScore
    $details += "CI Integration: $ciScore/3.0"
    
    # Check test quality (2 points)
    $qualityScore = 0
    if (Test-Path $testDir) {
        $testContent = Get-ChildItem -Path $testDir -Filter "*.ps1" | ForEach-Object {
            Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        }
        
        if ($testContent -match "Describe|Context|It") { $qualityScore += 1 }
        if ($testContent -match "BeforeAll|AfterAll|Mock") { $qualityScore += 1 }
    }
    
    $score += $qualityScore
    $details += "Test Quality: $qualityScore/2.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($testScore -lt 2) { "Create more comprehensive test files using Pester framework" }
            if ($pesterScore -lt 2) { "Upgrade to Pester v5+ for better testing capabilities" }
            if ($ciScore -eq 0) { "Set up CI/CD pipeline with automated testing" }
            if ($qualityScore -lt 1.5) { "Improve test quality with mocking and better structure" }
        )
    }
}

function Test-SecurityPractices {
    Write-ScorecardLog "Analyzing Security Practices..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check for hardcoded credentials (3 points - penalty system)
    $credentialPatterns = @(
        "password\s*=\s*['\"].*['\"]",
        "apikey\s*=\s*['\"].*['\"]",
        "secret\s*=\s*['\"].*['\"]",
        "token\s*=\s*['\"].*['\"]"
    )
    
    $credentialIssues = 0
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps*" | Where-Object { -not $_.FullName.Contains("Archive") }
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $credentialPatterns) {
            if ($content -match $pattern) {
                $credentialIssues++
                break
            }
        }
    }
    
    $credentialScore = [math]::Max(0, 3 - $credentialIssues)
    $score += $credentialScore
    $details += "Credential Security: $credentialScore/3.0 ($credentialIssues issues found)"
    
    # Check input validation (2 points)
    $validationScore = 0
    $validationPatterns = @("param\(.*\[ValidateSet", "param\(.*\[ValidateNotNull", "\[Parameter\(.*Mandatory")
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $validationPatterns) {
            if ($content -match $pattern) {
                $validationScore = [math]::Min($validationScore + 0.5, 2)
            }
        }
    }
    
    $score += $validationScore
    $details += "Input Validation: $([math]::Round($validationScore, 1))/2.0"
    
    # Check error handling (3 points)
    $errorHandlingScore = 0
    $errorPatterns = @("try\s*{", "catch\s*{", "\$ErrorActionPreference", "trap\s*{")
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $errorPatterns) {
            if ($content -match $pattern) {
                $errorHandlingScore = [math]::Min($errorHandlingScore + 0.75, 3)
            }
        }
    }
    
    $score += $errorHandlingScore
    $details += "Error Handling: $([math]::Round($errorHandlingScore, 1))/3.0"
    
    # Check execution policy awareness (2 points)
    $policyScore = 0
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "ExecutionPolicy|Set-ExecutionPolicy") {
            $policyScore = 2
            break
        }
    }
    
    $score += $policyScore
    $details += "Execution Policy Awareness: $policyScore/2.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($credentialScore -lt 3) { "Remove hardcoded credentials and use secure storage" }
            if ($validationScore -lt 1.5) { "Add parameter validation to PowerShell functions" }
            if ($errorHandlingScore -lt 2) { "Implement comprehensive error handling with try-catch blocks" }
            if ($policyScore -eq 0) { "Add execution policy awareness to scripts" }
        )
    }
}

function Test-ErrorHandling {
    Write-ScorecardLog "Analyzing Error Handling..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check try-catch usage (4 points)
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps*" | Where-Object { -not $_.FullName.Contains("Archive") }
    $filesWithTryCatch = 0
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "try\s*{.*catch\s*{") {
            $filesWithTryCatch++
        }
    }
    
    $tryCatchScore = ($filesWithTryCatch / [math]::Max($psFiles.Count, 1)) * 4
    $score += $tryCatchScore
    $details += "Try-Catch Usage: $([math]::Round($tryCatchScore, 1))/4.0 ($filesWithTryCatch/$($psFiles.Count) files)"
    
    # Check logging implementation (3 points)
    $loggingScore = 0
    $loggingPatterns = @("Write-Log", "Write-Host.*Error", "Write-Error", "Add-Content.*log")
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $loggingPatterns) {
            if ($content -match $pattern) {
                $loggingScore = [math]::Min($loggingScore + 0.75, 3)
            }
        }
    }
    
    $score += $loggingScore
    $details += "Logging Implementation: $([math]::Round($loggingScore, 1))/3.0"
    
    # Check graceful degradation (2 points)
    $degradationScore = 0
    $degradationPatterns = @("SilentlyContinue", "Continue", "Ignore")
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $degradationPatterns) {
            if ($content -match $pattern) {
                $degradationScore = [math]::Min($degradationScore + 0.5, 2)
            }
        }
    }
    
    $score += $degradationScore
    $details += "Graceful Degradation: $([math]::Round($degradationScore, 1))/2.0"
    
    # Check validation patterns (1 point)
    $validationScore = 0
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "Test-Path|ValidateNotNull|ValidateSet") {
            $validationScore = 1
            break
        }
    }
    
    $score += $validationScore
    $details += "Input Validation: $validationScore/1.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($tryCatchScore -lt 3) { "Add try-catch blocks to more functions for error handling" }
            if ($loggingScore -lt 2) { "Implement comprehensive logging for error tracking" }
            if ($degradationScore -lt 1.5) { "Add graceful degradation with proper ErrorAction settings" }
            if ($validationScore -eq 0) { "Add input validation to prevent errors" }
        )
    }
}

function Test-PerformanceMetrics {
    Write-ScorecardLog "Analyzing Performance Metrics..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check for metrics collection (4 points)
    $metricsFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*metric*" -ErrorAction SilentlyContinue
    $metricsScore = [math]::Min($metricsFiles.Count / 2 * 4, 4)
    $score += $metricsScore
    $details += "Metrics Collection: $([math]::Round($metricsScore, 1))/4.0 ($($metricsFiles.Count) files)"
    
    # Check monitoring capabilities (3 points)
    $monitoringScore = 0
    $monitoringPatterns = @("Measure-Command", "Get-Counter", "dashboard", "prometheus")
    
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps*" | Where-Object { -not $_.FullName.Contains("Archive") }
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $monitoringPatterns) {
            if ($content -match $pattern) {
                $monitoringScore = [math]::Min($monitoringScore + 0.75, 3)
            }
        }
    }
    
    $score += $monitoringScore
    $details += "Monitoring Capabilities: $([math]::Round($monitoringScore, 1))/3.0"
    
    # Check optimization patterns (2 points)
    $optimizationScore = 0
    $optimizationPatterns = @("Where-Object.*-Property", "Select-Object.*-First", "\[void\]", "-Parallel")
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $optimizationPatterns) {
            if ($content -match $pattern) {
                $optimizationScore = [math]::Min($optimizationScore + 0.5, 2)
            }
        }
    }
    
    $score += $optimizationScore
    $details += "Optimization Patterns: $([math]::Round($optimizationScore, 1))/2.0"
    
    # Check resource management (1 point)
    $resourceScore = 0
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "Dispose\(\)|using.*{|Remove-Variable") {
            $resourceScore = 1
            break
        }
    }
    
    $score += $resourceScore
    $details += "Resource Management: $resourceScore/1.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($metricsScore -lt 3) { "Implement comprehensive metrics collection system" }
            if ($monitoringScore -lt 2) { "Add monitoring and dashboard capabilities" }
            if ($optimizationScore -lt 1.5) { "Apply PowerShell performance optimization patterns" }
            if ($resourceScore -eq 0) { "Implement proper resource management and cleanup" }
        )
    }
}

function Test-DependencyManagement {
    Write-ScorecardLog "Analyzing Dependency Management..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check requirements documentation (3 points)
    $requirementsScore = 0
    $reqFiles = @("README.md", "requirements.txt", "Modules.txt") | ForEach-Object {
        Test-Path (Join-Path $projectRoot $_)
    }
    $requirementsScore = ($reqFiles | Where-Object { $_ }).Count / $reqFiles.Count * 3
    $score += $requirementsScore
    $details += "Requirements Documentation: $([math]::Round($requirementsScore, 1))/3.0"
    
    # Check module imports (3 points)
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps*" | Where-Object { -not $_.FullName.Contains("Archive") }
    $filesWithImports = 0
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "Import-Module|#requires") {
            $filesWithImports++
        }
    }
    
    $importsScore = ($filesWithImports / [math]::Max($psFiles.Count, 1)) * 3
    $score += $importsScore
    $details += "Module Imports: $([math]::Round($importsScore, 1))/3.0 ($filesWithImports/$($psFiles.Count) files)"
    
    # Check version pinning (2 points)
    $versionScore = 0
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "MinimumVersion|RequiredVersion|Version\s*[0-9]") {
            $versionScore = 2
            break
        }
    }
    
    $score += $versionScore
    $details += "Version Pinning: $versionScore/2.0"
    
    # Check dependency isolation (2 points)
    $isolationScore = 0
    $isolationPatterns = @("Import-Module.*-Force", "Remove-Module", "Get-Module.*-ListAvailable")
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $isolationPatterns) {
            if ($content -match $pattern) {
                $isolationScore = [math]::Min($isolationScore + 0.67, 2)
            }
        }
    }
    
    $score += $isolationScore
    $details += "Dependency Isolation: $([math]::Round($isolationScore, 1))/2.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($requirementsScore -lt 2) { "Document all dependencies and requirements clearly" }
            if ($importsScore -lt 2) { "Add proper module imports with #requires statements" }
            if ($versionScore -eq 0) { "Pin dependency versions for reproducible builds" }
            if ($isolationScore -lt 1.5) { "Implement proper module loading and cleanup" }
        )
    }
}

function Test-CICDIntegration {
    Write-ScorecardLog "Analyzing CI/CD Integration..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check GitHub Actions setup (4 points)
    $workflowDir = Join-Path $projectRoot ".github\workflows"
    if (Test-Path $workflowDir) {
        $workflows = Get-ChildItem -Path $workflowDir -Filter "*.yml"
        $workflowScore = [math]::Min($workflows.Count / 2 * 4, 4)
        $score += $workflowScore
        $details += "GitHub Actions: $([math]::Round($workflowScore, 1))/4.0 ($($workflows.Count) workflows)"
    } else {
        $details += "GitHub Actions: 0/4.0 (no workflows directory)"
    }
    
    # Check automated testing (3 points)
    $testingScore = 0
    if (Test-Path $workflowDir) {
        $workflows = Get-ChildItem -Path $workflowDir -Filter "*.yml"
        foreach ($workflow in $workflows) {
            $content = Get-Content $workflow.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match "Pester|test|Test") {
                $testingScore = 3
                break
            }
        }
    }
    
    $score += $testingScore
    $details += "Automated Testing: $testingScore/3.0"
    
    # Check deployment automation (2 points)
    $deploymentScore = 0
    if (Test-Path $workflowDir) {
        $workflows = Get-ChildItem -Path $workflowDir -Filter "*.yml"
        foreach ($workflow in $workflows) {
            $content = Get-Content $workflow.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match "deploy|release|publish") {
                $deploymentScore = 2
                break
            }
        }
    }
    
    $score += $deploymentScore
    $details += "Deployment Automation: $deploymentScore/2.0"
    
    # Check quality gates (1 point)
    $qualityScore = 0
    if (Test-Path $workflowDir) {
        $workflows = Get-ChildItem -Path $workflowDir -Filter "*.yml"
        foreach ($workflow in $workflows) {
            $content = Get-Content $workflow.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match "security|lint|quality|coverage") {
                $qualityScore = 1
                break
            }
        }
    }
    
    $score += $qualityScore
    $details += "Quality Gates: $qualityScore/1.0"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($workflowScore -lt 3) { "Set up comprehensive GitHub Actions workflows" }
            if ($testingScore -eq 0) { "Add automated testing to CI pipeline" }
            if ($deploymentScore -eq 0) { "Implement automated deployment processes" }
            if ($qualityScore -eq 0) { "Add quality gates and security scanning" }
        )
    }
}

function Invoke-QualityAssessment {
    Write-ScorecardLog "Starting Nova Quality Assessment..." -Level "Header"
    
    # Run all dimension tests
    $dimensions = @(
        @{ Name = "Code Organization"; Test = { Test-CodeOrganization } },
        @{ Name = "Documentation Coverage"; Test = { Test-DocumentationCoverage } },
        @{ Name = "Test Coverage"; Test = { Test-TestCoverage } },
        @{ Name = "Security Practices"; Test = { Test-SecurityPractices } },
        @{ Name = "Error Handling"; Test = { Test-ErrorHandling } },
        @{ Name = "Performance Metrics"; Test = { Test-PerformanceMetrics } },
        @{ Name = "Dependency Management"; Test = { Test-DependencyManagement } },
        @{ Name = "CI/CD Integration"; Test = { Test-CICDIntegration } }
    )
    
    $totalScore = 0
    $totalMaxScore = 0
    $allRecommendations = @()
    
    foreach ($dimension in $dimensions) {
        Write-ScorecardLog "Running $($dimension.Name) assessment..." -Level "Info"
        
        try {
            $result = & $dimension.Test
            
            $script:Scorecard.Dimensions[$dimension.Name] = @{
                Score = $result.Score
                MaxScore = $result.MaxScore
                Percentage = [math]::Round(($result.Score / $result.MaxScore) * 100, 1)
                Grade = Get-ScoreGrade ($result.Score / $result.MaxScore * 10)
                Details = $result.Details
                Recommendations = $result.Recommendations
            }
            
            $totalScore += $result.Score
            $totalMaxScore += $result.MaxScore
            $allRecommendations += $result.Recommendations
            
        } catch {
            Write-ScorecardLog "Error in $($dimension.Name): $($_.Exception.Message)" -Level "Poor"
            
            $script:Scorecard.Dimensions[$dimension.Name] = @{
                Score = 0
                MaxScore = 10
                Percentage = 0
                Grade = "F"
                Details = @("Error during assessment: $($_.Exception.Message)")
                Recommendations = @("Fix assessment errors and retry")
            }
        }
    }
    
    # Calculate overall score
    $overallScore = ($totalScore / $totalMaxScore) * 10
    $script:Scorecard.Summary.OverallScore = [math]::Round($overallScore, 2)
    $script:Scorecard.Summary.Grade = Get-ScoreGrade $overallScore
    $script:Scorecard.Summary.TotalPoints = $totalScore
    $script:Scorecard.Summary.MaxPoints = $totalMaxScore
    $script:Scorecard.Summary.Recommendations = $allRecommendations | Where-Object { $_ } | Select-Object -Unique
    
    Write-ScorecardLog "Quality Assessment Complete!" -Level "Header"
}

function Format-ConsoleOutput {
    $scorecard = $script:Scorecard
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $script:Colors.Header
    Write-Host "║                    NOVA QUALITY SCORECARD                    ║" -ForegroundColor $script:Colors.Header  
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $script:Colors.Header
    Write-Host ""
    
    # Overall Score
    $overallColor = Get-ScoreColor $scorecard.Summary.OverallScore
    Write-Host "🎯 OVERALL SCORE: " -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($scorecard.Summary.OverallScore)/10.0" -NoNewline -ForegroundColor $script:Colors[$overallColor]
    Write-Host " (" -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($scorecard.Summary.Grade)" -NoNewline -ForegroundColor $script:Colors[$overallColor]
    Write-Host ")" -ForegroundColor $script:Colors.Info
    
    Write-Host "📊 TOTAL POINTS: $($scorecard.Summary.TotalPoints)/$($scorecard.Summary.MaxPoints)" -ForegroundColor $script:Colors.Info
    Write-Host "📅 ASSESSED: $($scorecard.Metadata.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor $script:Colors.Info
    Write-Host ""
    
    # Dimension Breakdown
    Write-Host "📈 DIMENSION BREAKDOWN:" -ForegroundColor $script:Colors.Header
    Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
    
    foreach ($dimension in $scorecard.Dimensions.GetEnumerator() | Sort-Object { $_.Value.Score } -Descending) {
        $name = $dimension.Key
        $data = $dimension.Value
        $color = Get-ScoreColor ($data.Score / $data.MaxScore * 10)
        
        $nameFormatted = $name.PadRight(25)
        $scoreFormatted = "$($data.Score)/$($data.MaxScore)".PadLeft(8)
        $percentFormatted = "$($data.Percentage)%".PadLeft(6)
        $gradeFormatted = $data.Grade.PadLeft(3)
        
        Write-Host "  $nameFormatted" -NoNewline -ForegroundColor $script:Colors.Info
        Write-Host "$scoreFormatted" -NoNewline -ForegroundColor $script:Colors[$color]
        Write-Host " ($percentFormatted)" -NoNewline -ForegroundColor $script:Colors[$color]
        Write-Host " [$gradeFormatted]" -ForegroundColor $script:Colors[$color]
        
        if ($Detailed) {
            foreach ($detail in $data.Details) {
                Write-Host "    • $detail" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host ""
    
    # Recommendations
    if ($scorecard.Summary.Recommendations.Count -gt 0) {
        Write-Host "💡 TOP RECOMMENDATIONS:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        $topRecommendations = $scorecard.Summary.Recommendations | Select-Object -First 5
        for ($i = 0; $i -lt $topRecommendations.Count; $i++) {
            Write-Host "  $($i + 1). $($topRecommendations[$i])" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Quick Assessment
    if ($Quick) {
        return
    }
    
    # Detailed Breakdown
    if ($Detailed) {
        Write-Host "📋 DETAILED ANALYSIS:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        foreach ($dimension in $scorecard.Dimensions.GetEnumerator()) {
            Write-Host ""
            Write-Host "🔍 $($dimension.Key)" -ForegroundColor $script:Colors.Header
            
            foreach ($detail in $dimension.Value.Details) {
                Write-Host "   • $detail" -ForegroundColor $script:Colors.Info
            }
            
            if ($dimension.Value.Recommendations.Count -gt 0) {
                Write-Host "   Recommendations:" -ForegroundColor Yellow
                foreach ($rec in $dimension.Value.Recommendations) {
                    Write-Host "     → $rec" -ForegroundColor Yellow
                }
            }
        }
    }
}

function Export-ScorecardJson {
    param([string]$Path)
    
    $jsonOutput = $script:Scorecard | ConvertTo-Json -Depth 10
    
    if ($Path) {
        Set-Content -Path $Path -Value $jsonOutput -Encoding UTF8
        Write-ScorecardLog "Scorecard exported to: $Path" -Level "Good"
    } else {
        return $jsonOutput
    }
}

function Export-ScorecardHtml {
    param([string]$Path)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Nova Quality Scorecard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 20px; margin-bottom: 30px; }
        .score-card { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin: 20px 0; }
        .dimension { background: #ecf0f1; padding: 15px; border-radius: 6px; border-left: 4px solid #3498db; }
        .score { font-size: 1.5em; font-weight: bold; }
        .grade-A { color: #27ae60; }
        .grade-B { color: #f39c12; }
        .grade-C { color: #e67e22; }
        .grade-D { color: #e74c3c; }
        .recommendations { background: #fff3cd; padding: 15px; border-radius: 6px; border-left: 4px solid #ffc107; margin-top: 20px; }
        .details { margin-top: 10px; font-size: 0.9em; color: #666; }
        ul { padding-left: 20px; }
        li { margin: 5px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏆 Nova Quality Scorecard</h1>
            <div class="score grade-$($script:Scorecard.Summary.Grade[0])">
                Overall Score: $($script:Scorecard.Summary.OverallScore)/10.0 ($($script:Scorecard.Summary.Grade))
            </div>
            <p>Generated: $($script:Scorecard.Metadata.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        </div>
        
        <div class="score-card">
"@

    foreach ($dimension in $script:Scorecard.Dimensions.GetEnumerator()) {
        $gradeClass = "grade-$($dimension.Value.Grade[0])"
        
        $html += @"
            <div class="dimension">
                <h3>$($dimension.Key)</h3>
                <div class="score $gradeClass">$($dimension.Value.Score)/$($dimension.Value.MaxScore) ($($dimension.Value.Grade))</div>
                <div class="details">
                    <ul>
$(($dimension.Value.Details | ForEach-Object { "                        <li>$_</li>" }) -join "`n")
                    </ul>
                </div>
            </div>
"@
    }

    $html += @"
        </div>
        
        <div class="recommendations">
            <h3>💡 Recommendations</h3>
            <ul>
$(($script:Scorecard.Summary.Recommendations | Select-Object -First 10 | ForEach-Object { "                <li>$_</li>" }) -join "`n")
            </ul>
        </div>
    </div>
</body>
</html>
"@

    if ($Path) {
        Set-Content -Path $Path -Value $html -Encoding UTF8
        Write-ScorecardLog "HTML scorecard exported to: $Path" -Level "Good"
    } else {
        return $html
    }
}

# Main execution
try {
    Invoke-QualityAssessment
    
    switch ($OutputFormat) {
        "Console" { 
            Format-ConsoleOutput 
        }
        "JSON" { 
            if ($OutputPath) {
                Export-ScorecardJson -Path $OutputPath
            } else {
                Export-ScorecardJson
            }
        }
        "HTML" { 
            if ($OutputPath) {
                Export-ScorecardHtml -Path $OutputPath
            } else {
                $htmlFile = Join-Path $script:Scorecard.Metadata.ProjectRoot "quality-scorecard.html"
                Export-ScorecardHtml -Path $htmlFile
                Write-ScorecardLog "Opening HTML report..." -Level "Good"
                Start-Process $htmlFile
            }
        }
    }
    
    Write-ScorecardLog "Quality Scorecard Complete! Overall Score: $($script:Scorecard.Summary.OverallScore)/10.0 ($($script:Scorecard.Summary.Grade))" -Level $(Get-ScoreColor $script:Scorecard.Summary.OverallScore)
    
} catch {
    Write-Error "Quality Scorecard failed: $($_.Exception.Message)"
    exit 1
}