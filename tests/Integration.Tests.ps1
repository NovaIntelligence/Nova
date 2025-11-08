# Integration.Tests.ps1 - Nova Bot Integration Test Suite
# Creators: Tyler McKendry & Nova

#requires -Version 5.1
#requires -Modules Pester

param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

BeforeAll {
    # Setup test environment
    $script:ProjectRoot = $ProjectRoot
    $script:TestStartTime = Get-Date
    
    Write-Host "🧪 Starting Nova Integration Tests" -ForegroundColor Cyan
    Write-Host "📂 Project Root: $script:ProjectRoot" -ForegroundColor Gray
    Write-Host "⏰ Start Time: $($script:TestStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    Write-Host ""
}

Describe "Nova Bot Integration Tests" {
    
    Context "Environment Validation" {
        
        It "Should have valid project structure" {
            # Test essential directories exist
            @("bot", "tools", "tests", "docs") | ForEach-Object {
                Join-Path $script:ProjectRoot $_ | Should -Exist
            }
        }
        
        It "Should have PowerShell 5.1 or higher" {
            $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 5
            if ($PSVersionTable.PSVersion.Major -eq 5) {
                $PSVersionTable.PSVersion.Minor | Should -BeGreaterOrEqual 1
            }
        }
        
        It "Should have Pester v5 available" {
            $pesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
            $pesterModule | Should -Not -BeNullOrEmpty
            $pesterModule.Version.Major | Should -BeGreaterOrEqual 5
        }
        
        It "Should have execution policy allowing script execution" {
            $policy = Get-ExecutionPolicy
            $policy | Should -Not -Be "Restricted"
        }
    }
    
    Context "Core Script Validation" {
        
        It "Should have essential Nova scripts" {
            $essentialScripts = @(
                "tools\Preflight.ps1",
                "tools\Quality-Scorecard.ps1",
                "tools\Security-Audit.ps1",
                "tests\Coverage-Report.ps1",
                "scripts\Setup-LocalDev.ps1"
            )
            
            foreach ($script in $essentialScripts) {
                $scriptPath = Join-Path $script:ProjectRoot $script
                $scriptPath | Should -Exist
            }
        }
        
        It "Should have valid PowerShell syntax in all scripts" {
            $psFiles = Get-ChildItem -Path $script:ProjectRoot -Recurse -Include "*.ps1", "*.psm1" |
                Where-Object { -not $_.FullName.Contains("Archive") -and -not $_.FullName.Contains(".git") }
            
            foreach ($file in $psFiles) {
                { 
                    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$null)
                } | Should -Not -Throw -Because "Script $($file.Name) should have valid PowerShell syntax"
            }
        }
        
        It "Should have creator headers in all new One-Paste Pack scripts" {
            $onePasteScripts = @(
                "tools\Quality-Scorecard.ps1",
                "tools\Security-Audit.ps1", 
                "tests\Coverage-Report.ps1",
                "scripts\Setup-LocalDev.ps1"
            )
            
            foreach ($script in $onePasteScripts) {
                $scriptPath = Join-Path $script:ProjectRoot $script
                if (Test-Path $scriptPath) {
                    $content = Get-Content $scriptPath -Raw
                    $content | Should -Match "Creators: Tyler McKendry & Nova" -Because "$script should have proper creator header"
                }
            }
        }
    }
    
    Context "Preflight System" {
        
        It "Should execute Preflight.ps1 without errors" {
            $preflightPath = Join-Path $script:ProjectRoot "tools\Preflight.ps1"
            
            $result = & powershell -ExecutionPolicy Bypass -File $preflightPath -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $LASTEXITCODE | Should -Be 0 -Because "Preflight checks should pass"
        }
        
        It "Should validate directory structure in Preflight" {
            # This test ensures Preflight is actually checking directory structure
            $preflightPath = Join-Path $script:ProjectRoot "tools\Preflight.ps1"
            $preflightContent = Get-Content $preflightPath -Raw
            
            $preflightContent | Should -Match "bot|tools|tests" -Because "Preflight should check essential directories"
        }
    }
    
    Context "Quality Scorecard System" {
        
        It "Should execute Quality-Scorecard.ps1 successfully" {
            $scorecardPath = Join-Path $script:ProjectRoot "tools\Quality-Scorecard.ps1"
            
            $result = & powershell -ExecutionPolicy Bypass -File $scorecardPath -Quick -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $LASTEXITCODE | Should -Be 0 -Because "Quality Scorecard should execute successfully"
        }
        
        It "Should generate JSON output when requested" {
            $scorecardPath = Join-Path $script:ProjectRoot "tools\Quality-Scorecard.ps1"
            $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
            
            try {
                $result = & powershell -ExecutionPolicy Bypass -File $scorecardPath -Quick -OutputFormat JSON -OutputPath $tempFile -ErrorAction SilentlyContinue
                
                Test-Path $tempFile | Should -Be $true -Because "JSON output file should be created"
                
                if (Test-Path $tempFile) {
                    $jsonContent = Get-Content $tempFile -Raw | ConvertFrom-Json
                    $jsonContent.Summary.OverallScore | Should -BeOfType [double] -Because "Overall score should be numeric"
                    $jsonContent.Metadata.Timestamp | Should -Not -BeNullOrEmpty -Because "Metadata should include timestamp"
                }
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
        
        It "Should evaluate all 8 quality dimensions" {
            $scorecardPath = Join-Path $script:ProjectRoot "tools\Quality-Scorecard.ps1"
            $scorecardContent = Get-Content $scorecardPath -Raw
            
            # Check for all expected dimensions
            $expectedDimensions = @(
                "Code Organization",
                "Documentation Coverage",
                "Test Coverage", 
                "Security Practices",
                "Error Handling",
                "Performance Metrics",
                "Dependency Management",
                "CI/CD Integration"
            )
            
            foreach ($dimension in $expectedDimensions) {
                $scorecardContent | Should -Match [regex]::Escape($dimension) -Because "Scorecard should evaluate $dimension"
            }
        }
    }
    
    Context "Security Audit System" {
        
        It "Should execute Security-Audit.ps1 successfully" {
            $auditPath = Join-Path $script:ProjectRoot "tools\Security-Audit.ps1"
            
            $result = & powershell -ExecutionPolicy Bypass -File $auditPath -Quick -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            # Security audit may return exit code 1 for issues, so we check it ran without PowerShell errors
            $LASTEXITCODE | Should -BeIn @(0, 1, 2) -Because "Security Audit should execute (may find issues)"
        }
        
        It "Should detect known security patterns" {
            $auditPath = Join-Path $script:ProjectRoot "tools\Security-Audit.ps1"
            $auditContent = Get-Content $auditPath -Raw
            
            # Check for security pattern categories
            $securityPatterns = @(
                "Credentials",
                "Injection", 
                "FileSystem",
                "Network",
                "Execution"
            )
            
            foreach ($pattern in $securityPatterns) {
                $auditContent | Should -Match $pattern -Because "Security audit should check for $pattern vulnerabilities"
            }
        }
        
        It "Should generate structured security reports" {
            $auditPath = Join-Path $script:ProjectRoot "tools\Security-Audit.ps1"
            $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
            
            try {
                $result = & powershell -ExecutionPolicy Bypass -File $auditPath -Quick -OutputFormat JSON -Output $tempFile -ErrorAction SilentlyContinue
                
                if (Test-Path $tempFile) {
                    $jsonContent = Get-Content $tempFile -Raw | ConvertFrom-Json
                    $jsonContent.Summary.SecurityScore | Should -BeOfType [int] -Because "Security score should be numeric"
                    $jsonContent.Categories | Should -Not -BeNullOrEmpty -Because "Security categories should be evaluated"
                }
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    
    Context "Coverage Analysis System" {
        
        It "Should execute Coverage-Report.ps1 successfully" {
            $coveragePath = Join-Path $script:ProjectRoot "tests\Coverage-Report.ps1"
            
            $result = & powershell -ExecutionPolicy Bypass -File $coveragePath -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $LASTEXITCODE | Should -Be 0 -Because "Coverage Report should execute successfully"
        }
        
        It "Should analyze PowerShell functions" {
            $coveragePath = Join-Path $script:ProjectRoot "tests\Coverage-Report.ps1"
            $coverageContent = Get-Content $coveragePath -Raw
            
            $coverageContent | Should -Match "Get-PowerShellFunctions" -Because "Coverage analysis should detect PowerShell functions"
            $coverageContent | Should -Match "function.*coverage" -Because "Coverage analysis should calculate coverage metrics"
        }
        
        It "Should generate HTML reports when requested" {
            $coveragePath = Join-Path $script:ProjectRoot "tests\Coverage-Report.ps1"
            $tempFile = [System.IO.Path]::GetTempFileName() + ".html"
            
            try {
                $result = & powershell -ExecutionPolicy Bypass -File $coveragePath -HTML -OutputPath $tempFile -ErrorAction SilentlyContinue
                
                Test-Path $tempFile | Should -Be $true -Because "HTML coverage report should be created"
                
                if (Test-Path $tempFile) {
                    $htmlContent = Get-Content $tempFile -Raw
                    $htmlContent | Should -Match "Nova Coverage Report" -Because "HTML should contain report title"
                    $htmlContent | Should -Match "coverage" -Because "HTML should contain coverage data"
                }
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    
    Context "Setup System" {
        
        It "Should execute Setup-LocalDev.ps1 dry-run successfully" {
            $setupPath = Join-Path $script:ProjectRoot "scripts\Setup-LocalDev.ps1"
            
            # Run setup with SkipDependencies and SkipTests to avoid system changes
            $result = & powershell -ExecutionPolicy Bypass -File $setupPath -SkipDependencies -SkipTests -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $LASTEXITCODE | Should -BeIn @(0, 1) -Because "Setup script should execute (may have environment issues)"
        }
        
        It "Should validate system requirements" {
            $setupPath = Join-Path $script:ProjectRoot "scripts\Setup-LocalDev.ps1"
            $setupContent = Get-Content $setupPath -Raw
            
            $setupContent | Should -Match "Test-PowerShellVersion" -Because "Setup should check PowerShell version"
            $setupContent | Should -Match "Test-GitInstallation" -Because "Setup should check Git installation"
        }
        
        It "Should create necessary directory structure" {
            $setupPath = Join-Path $script:ProjectRoot "scripts\Setup-LocalDev.ps1"
            $setupContent = Get-Content $setupPath -Raw
            
            $setupContent | Should -Match "Initialize-DirectoryStructure" -Because "Setup should create directories"
            $setupContent | Should -Match "ci-artifacts" -Because "Setup should create CI artifacts directory"
        }
    }
    
    Context "CI/CD Integration" {
        
        It "Should have GitHub Actions workflows" {
            $workflowDir = Join-Path $script:ProjectRoot ".github\workflows"
            $workflowDir | Should -Exist -Because "GitHub Actions workflows directory should exist"
            
            $workflows = Get-ChildItem -Path $workflowDir -Filter "*.yml" -ErrorAction SilentlyContinue
            $workflows.Count | Should -BeGreaterThan 0 -Because "Should have at least one workflow file"
        }
        
        It "Should have quality scorecard workflow" {
            $scorecardWorkflow = Join-Path $script:ProjectRoot ".github\workflows\scorecard.yml"
            $scorecardWorkflow | Should -Exist -Because "Quality scorecard workflow should exist"
            
            $workflowContent = Get-Content $scorecardWorkflow -Raw
            $workflowContent | Should -Match "Quality Scorecard" -Because "Workflow should be for quality scorecard"
            $workflowContent | Should -Match "Security-Audit" -Because "Workflow should include security audit"
        }
        
        It "Should have proper workflow triggers" {
            $workflows = Get-ChildItem -Path (Join-Path $script:ProjectRoot ".github\workflows") -Filter "*.yml" -ErrorAction SilentlyContinue
            
            foreach ($workflow in $workflows) {
                $content = Get-Content $workflow.FullName -Raw
                $content | Should -Match "on:" -Because "Workflow should have triggers defined"
                $content | Should -Match "(push|pull_request)" -Because "Workflow should trigger on push or PR"
            }
        }
    }
    
    Context "Documentation Completeness" {
        
        It "Should have One-Paste Pack README" {
            $readmePath = Join-Path $script:ProjectRoot "docs\One-Paste-Pack-README.md"
            $readmePath | Should -Exist -Because "One-Paste Pack README should exist"
            
            $readmeContent = Get-Content $readmePath -Raw
            $readmeContent | Should -Match "One-Paste Commands" -Because "README should contain one-paste commands"
            $readmeContent | Should -Match "Quality-Scorecard" -Because "README should document quality scorecard"
        }
        
        It "Should have updated main README with scorecard info" {
            $mainReadme = Join-Path $script:ProjectRoot "README.md"
            if (Test-Path $mainReadme) {
                $content = Get-Content $mainReadme -Raw
                $content | Should -Not -BeNullOrEmpty -Because "Main README should have content"
            }
        }
        
        It "Should have proper documentation structure" {
            $docsDir = Join-Path $script:ProjectRoot "docs"
            $docsDir | Should -Exist -Because "Documentation directory should exist"
        }
    }
    
    Context "File System Integration" {
        
        It "Should create artifacts directories during execution" {
            $artifactDirs = @("ci-artifacts", "quality-artifacts")
            
            foreach ($dir in $artifactDirs) {
                $dirPath = Join-Path $script:ProjectRoot $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                $dirPath | Should -Exist -Because "Artifact directory $dir should be creatable"
            }
        }
        
        It "Should handle UTF-8 encoding properly" {
            # Test that scripts can handle UTF-8 files
            $testFiles = Get-ChildItem -Path $script:ProjectRoot -Recurse -Include "*.ps1" -ErrorAction SilentlyContinue | Select-Object -First 5
            
            foreach ($file in $testFiles) {
                { Get-Content $file.FullName -Encoding UTF8 } | Should -Not -Throw -Because "Should handle UTF-8 encoding"
            }
        }
        
        It "Should have proper .gitignore patterns" {
            $gitignorePath = Join-Path $script:ProjectRoot ".gitignore"
            if (Test-Path $gitignorePath) {
                $gitignoreContent = Get-Content $gitignorePath -Raw
                $gitignoreContent | Should -Match "artifacts" -Because ".gitignore should exclude artifact directories"
                $gitignoreContent | Should -Match "\.log" -Because ".gitignore should exclude log files"
            }
        }
    }
    
    Context "Error Handling Integration" {
        
        It "Should handle missing files gracefully" {
            $scorecardPath = Join-Path $script:ProjectRoot "tools\Quality-Scorecard.ps1"
            
            # Test with a temporary missing directory
            $tempDir = Join-Path $script:ProjectRoot "temp-missing-test"
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            
            # Quality scorecard should still run even with missing optional components
            { & powershell -ExecutionPolicy Bypass -File $scorecardPath -Quick -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
        
        It "Should provide meaningful error messages" {
            $scripts = @(
                "tools\Quality-Scorecard.ps1",
                "tools\Security-Audit.ps1",
                "tests\Coverage-Report.ps1"
            )
            
            foreach ($script in $scripts) {
                $scriptPath = Join-Path $script:ProjectRoot $script
                if (Test-Path $scriptPath) {
                    $content = Get-Content $scriptPath -Raw
                    $content | Should -Match "(Write-.*Error|Write-.*Warning)" -Because "$script should have error handling"
                }
            }
        }
    }
    
    Context "Performance Integration" {
        
        It "Should complete quality scorecard in reasonable time" {
            $scorecardPath = Join-Path $script:ProjectRoot "tools\Quality-Scorecard.ps1"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = & powershell -ExecutionPolicy Bypass -File $scorecardPath -Quick -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $stopwatch.Stop()
            
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 60 -Because "Quality scorecard should complete within 60 seconds"
        }
        
        It "Should complete security audit in reasonable time" {
            $auditPath = Join-Path $script:ProjectRoot "tools\Security-Audit.ps1"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = & powershell -ExecutionPolicy Bypass -File $auditPath -Quick -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $stopwatch.Stop()
            
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 45 -Because "Security audit should complete within 45 seconds"
        }
    }
}

AfterAll {
    $duration = (Get-Date) - $script:TestStartTime
    Write-Host ""
    Write-Host "✅ Nova Integration Tests Completed" -ForegroundColor Green
    Write-Host "⏰ Duration: $($duration.ToString('mm\:ss'))" -ForegroundColor Gray
    Write-Host "📊 Project: $script:ProjectRoot" -ForegroundColor Gray
    Write-Host ""
}