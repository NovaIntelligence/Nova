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
    if ($color) {
        Write-Host "[$timestamp] $Message" -ForegroundColor $color
    } else {
        Write-Host "[$timestamp] $Message"
    }
}

function Test-CodeOrganization {
    Write-ScorecardLog "Analyzing Code Organization..." -Level "Info"
    
    $projectRoot = $script:Scorecard.Metadata.ProjectRoot
    $score = 0
    $maxScore = 10
    $details = @()
    
    # Check directory structure (3 points)
    $expectedDirs = @("tools", "tests", "scripts", "docs")
    $existingDirs = $expectedDirs | Where-Object { Test-Path (Join-Path $projectRoot $_) }
    $dirScore = ($existingDirs.Count / $expectedDirs.Count) * 3
    $score += $dirScore
    $details += "Directory Structure: $([math]::Round($dirScore, 1))/3.0 ($(($existingDirs | Measure-Object).Count)/$($expectedDirs.Count) standard dirs)"
    
    # Check PowerShell module structure (3 points)
    $moduleFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.psm1"
    $manifestFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.psd1"
    $moduleScore = [math]::Min(($moduleFiles.Count + $manifestFiles.Count) * 0.5, 3)
    $score += $moduleScore
    $details += "Module Organization: $([math]::Round($moduleScore, 1))/3.0 ($($moduleFiles.Count) modules, $($manifestFiles.Count) manifests)"
    
    # Check file naming conventions (2 points) 
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps1" | Where-Object { -not $_.FullName.Contains("Archive") }
    $properlyNamed = $psFiles | Where-Object { $_.BaseName -cmatch "^[A-Z][a-zA-Z0-9-]*$" }
    $namingScore = ($properlyNamed.Count / [math]::Max($psFiles.Count, 1)) * 2
    $score += $namingScore
    $details += "Naming Conventions: $([math]::Round($namingScore, 1))/2.0 ($($properlyNamed.Count)/$($psFiles.Count) files follow PascalCase)"
    
    # Check for oversized files (2 points)
    $oversizedFiles = $psFiles | Where-Object { (Get-Item $_.FullName).Length -gt 5KB }
    $sizeScore = [math]::Max(2 - ($oversizedFiles.Count * 0.5), 0)
    $score += $sizeScore  
    $details += "File Sizes: $([math]::Round($sizeScore, 1))/2.0 ($($oversizedFiles.Count) oversized files > 5KB)"
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @(
            if ($dirScore -lt 2) { "Create missing standard directories: $($expectedDirs -join ', ')" }
            if ($moduleScore -lt 2) { "Organize code into reusable PowerShell modules" }
            if ($namingScore -lt 1.5) { "Improve file naming conventions (PascalCase)" }
            if ($oversizedFiles.Count -gt 0) { "Consider breaking down large files: $($oversizedFiles[0..2] | ForEach-Object { $_.Name } | Join-String ', ')" }
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
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps1" | Where-Object { -not $_.FullName.Contains("Archive") }
    $documentedFiles = 0
    
    foreach ($file in $psFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "\.SYNOPSIS|\.DESCRIPTION|<#") {
            $documentedFiles++
        }
    }
    
    $inlineScore = ($documentedFiles / [math]::Max($psFiles.Count, 1)) * 3
    $score += $inlineScore
    $details += "Inline Documentation: $([math]::Round($inlineScore, 1))/3.0 ($documentedFiles/$($psFiles.Count) documented files)"
    
    # Check API documentation (2 points)
    $apiDocs = @("docs", "API.md", "CONTRIBUTING.md") | ForEach-Object { 
        Test-Path (Join-Path $projectRoot $_) 
    }
    $apiScore = ($apiDocs | Where-Object { $_ } | Measure-Object).Count / $apiDocs.Count * 2
    $score += $apiScore
    $details += "API Documentation: $([math]::Round($apiScore, 1))/2.0"
    
    # Check examples and tutorials (2 points)
    $exampleDirs = @("examples", "samples", "demos") | ForEach-Object {
        Test-Path (Join-Path $projectRoot $_)
    }
    $tutorialScore = ($exampleDirs | Where-Object { $_ } | Measure-Object).Count / $exampleDirs.Count * 2
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
    
    # Check test directory structure (3 points)
    $testPath = Join-Path $projectRoot "tests"
    if (Test-Path $testPath) {
        $testFiles = Get-ChildItem -Path $testPath -Filter "*.Tests.ps1"
        $testScore = [math]::Min($testFiles.Count * 0.5, 3)
        $score += $testScore
        $details += "Test Files: $([math]::Round($testScore, 1))/3.0 ($($testFiles.Count) test files)"
    } else {
        $details += "Test Files: 0/3.0 (no test directory)"
    }
    
    return @{
        Score = [math]::Min($score, $maxScore)
        MaxScore = $maxScore
        Details = $details
        Recommendations = @()
    }
}

# Main execution
try {
    Write-ScorecardLog "=== Nova Bot Quality Scorecard ===" -Level "Header"
    Write-ScorecardLog "Starting quality assessment..." -Level "Info"
    
    # Run all assessments
    $script:Scorecard.Dimensions.CodeOrganization = Test-CodeOrganization
    $script:Scorecard.Dimensions.Documentation = Test-DocumentationCoverage  
    $script:Scorecard.Dimensions.TestCoverage = Test-TestCoverage
    
    # Calculate overall score
    $totalScore = 0
    $totalMaxScore = 0
    
    foreach ($dimension in $script:Scorecard.Dimensions.Values) {
        $totalScore += $dimension.Score
        $totalMaxScore += $dimension.MaxScore
    }
    
    $overallScore = if ($totalMaxScore -gt 0) { ($totalScore / $totalMaxScore) * 10 } else { 0 }
    
    $script:Scorecard.Summary.OverallScore = [math]::Round($overallScore, 1)
    $script:Scorecard.Summary.TotalPoints = $totalScore  
    $script:Scorecard.Summary.MaxPoints = $totalMaxScore
    
    # Determine grade
    $script:Scorecard.Summary.Grade = switch ($overallScore) {
        { $_ -ge 9 } { "A+" }
        { $_ -ge 8.5 } { "A" }
        { $_ -ge 8 } { "A-" }
        { $_ -ge 7.5 } { "B+" }
        { $_ -ge 7 } { "B" }
        { $_ -ge 6.5 } { "B-" }
        { $_ -ge 6 } { "C+" }
        default { "C" }
    }
    
    # Display results
    Write-Host "`n=== QUALITY SCORECARD RESULTS ===" -ForegroundColor $script:Colors.Header
    Write-Host "Overall Score: $($script:Scorecard.Summary.OverallScore)/10.0 (Grade: $($script:Scorecard.Summary.Grade))" -ForegroundColor $script:Colors.Excellent
    
    foreach ($dimensionName in $script:Scorecard.Dimensions.Keys) {
        $dimension = $script:Scorecard.Dimensions[$dimensionName]
        Write-Host "`n$dimensionName`: $([math]::Round($dimension.Score, 1))/$($dimension.MaxScore)" -ForegroundColor $script:Colors.Good
        foreach ($detail in $dimension.Details) {
            Write-Host "  $detail" -ForegroundColor $script:Colors.Info
        }
    }
    
    Write-Host "`nQuality assessment completed successfully." -ForegroundColor $script:Colors.Excellent
    
} catch {
    Write-Error "Quality assessment failed: $($_.Exception.Message)"
    exit 1
}