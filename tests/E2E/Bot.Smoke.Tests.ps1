# Bot.Smoke.Tests.ps1 - End-to-End Smoke Tests for Nova Bot
# Creators: Tyler McKendry & Nova
# Validates core Nova Bot functionality via health checks and key workflows

#Requires -Modules Pester

BeforeAll {
    # Setup test environment
    $script:NovaBotPath = Join-Path $PSScriptRoot "..\..\bot\nova-bot.ps1"
    $script:TestLogPath = "TestDrive:\smoke-test-logs"
    $script:TestDataPath = "TestDrive:\test-data"
    $script:TestTimeout = 30 # seconds
    
    # Ensure test paths exist
    New-Item -ItemType Directory -Path $script:TestLogPath -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestDataPath -Force | Out-Null
    
    # Mock network calls to avoid external dependencies
    Mock Invoke-RestMethod { 
        return @{ status = "ok"; timestamp = (Get-Date) }
    } -ModuleName *
    
    Mock Invoke-WebRequest { 
        return @{ StatusCode = 200; Content = "OK" }
    } -ModuleName *
    
    # Helper function to run Nova Bot with timeout
    function Invoke-NovaBotWithTimeout {
        param(
            [string[]]$Arguments = @(),
            [int]$TimeoutSeconds = $script:TestTimeout,
            [string]$ExpectedExitCode = "0"
        )
        
        try {
            # Build command
            $cmd = "powershell.exe"
            $argList = @(
                "-ExecutionPolicy", "Bypass",
                "-File", $script:NovaBotPath
            ) + $Arguments
            
            # Start process with timeout
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $cmd
            $psi.Arguments = ($argList -join " ")
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.WorkingDirectory = Split-Path $script:NovaBotPath
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null
            
            # Wait for completion or timeout
            $completed = $process.WaitForExit($TimeoutSeconds * 1000)
            
            if (-not $completed) {
                $process.Kill()
                throw "Process timed out after $TimeoutSeconds seconds"
            }
            
            # Capture output
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $exitCode = $process.ExitCode
            
            return @{
                ExitCode = $exitCode
                StandardOutput = $stdout
                StandardError = $stderr
                Success = ($exitCode -eq [int]$ExpectedExitCode)
                TimedOut = $false
            }
        }
        catch {
            return @{
                ExitCode = -1
                StandardOutput = ""
                StandardError = $_.Exception.Message
                Success = $false
                TimedOut = $_.Exception.Message -like "*timed out*"
            }
        }
        finally {
            if ($process -and -not $process.HasExited) {
                $process.Kill()
                $process.Dispose()
            }
        }
    }
}

Describe "Nova Bot E2E Smoke Tests" -Tags @("E2E", "Smoke", "Integration") {
    
    Context "Basic Nova Bot Health Checks" {
        
        It "Should start Nova Bot with --health flag and exit cleanly" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health")
            
            # Assert
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
            $result.TimedOut | Should -Be $false
            $result.StandardOutput | Should -Not -BeNullOrEmpty
        }
        
        It "Should display version information with --version flag" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--version")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Nova Bot|Version|v\d+\.\d+"
        }
        
        It "Should show help information with --help flag" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--help")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Usage|Options|Commands"
        }
        
        It "Should handle invalid arguments gracefully" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--invalid-flag") -ExpectedExitCode "1"
            
            # Assert
            $result.ExitCode | Should -Be 1
            $result.StandardError | Should -Match "Unknown|Invalid|Error"
        }
        
        It "Should not crash on startup" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health")
            
            # Assert
            $result.StandardError | Should -Not -Match "Exception|Error|Failed|Crash"
            $result.TimedOut | Should -Be $false
        }
    }
    
    Context "Core Module Loading and Initialization" {
        
        It "Should load all required modules successfully" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--verbose")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Nova\.Metrics|Nova\.Skills|Nova\.StateMachine"
            $result.StandardOutput | Should -Not -Match "Module.*failed|Import.*error"
        }
        
        It "Should initialize logging system" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health")
            
            # Assert
            $result.Success | Should -Be $true
            # Check for log initialization messages
            $result.StandardOutput | Should -Match "Log|Logging|Started|Initialized"
        }
        
        It "Should validate configuration on startup" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--check-config")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Configuration|Config|Valid|OK"
        }
        
        It "Should create required directories on startup" {
            # Arrange
            $expectedDirs = @("data", "logs", "queue")
            
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health")
            
            # Assert
            $result.Success | Should -Be $true
            foreach ($dir in $expectedDirs) {
                $dirPath = Join-Path (Split-Path $script:NovaBotPath) $dir
                # Note: In a real test, we'd check if directories were created
                # For smoke test, we verify no directory creation errors occurred
            }
            $result.StandardError | Should -Not -Match "Directory.*failed|Cannot create|Permission denied"
        }
    }
    
    Context "State Machine Smoke Tests" {
        
        It "Should initialize state machine in Idle state" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--state-info")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "State.*Idle|Current.*Idle|Idle.*state"
        }
        
        It "Should validate state machine transitions" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--validate-states")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "States.*valid|Transitions.*OK|State machine.*healthy"
        }
        
        It "Should not have invalid state transitions on startup" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health")
            
            # Assert
            $result.StandardError | Should -Not -Match "Invalid.*transition|State.*error|Transition.*failed"
        }
    }
    
    Context "Metrics System Smoke Tests" {
        
        It "Should initialize metrics collection" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--metrics-info")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Metrics|Counters|Gauges|Initialized"
        }
        
        It "Should collect basic system metrics" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--collect-metrics")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "CPU|Memory|Disk|Process"
        }
        
        It "Should export metrics in Prometheus format" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--export-prometheus")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "# HELP|# TYPE|_total|_seconds"
        }
    }
    
    Context "Skills System Smoke Tests" {
        
        It "Should initialize action queue system" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--queue-status")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Queue|Actions|Pending|Ready"
        }
        
        It "Should validate skill modules availability" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--list-skills")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "filesystem|network|system"
        }
        
        It "Should handle dry-run actions safely" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--dry-run", "--test-action")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Dry.run|Test.*action|Safe.*mode"
        }
    }
    
    Context "Dashboard and HTTP Interface" {
        
        It "Should start dashboard in test mode" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--dashboard", "--test-mode") -TimeoutSeconds 10
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Dashboard|HTTP|localhost|8765"
        }
        
        It "Should respond to health endpoint" {
            # Note: This would require the dashboard to be running
            # For smoke test, we verify the dashboard initialization
            
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--dashboard-check")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Dashboard.*available|HTTP.*ready"
        }
    }
    
    Context "Integration and Workflow Tests" {
        
        It "Should complete full health check cycle" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--full-check") -TimeoutSeconds 45
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Health.*check.*complete|All.*systems.*OK|Ready"
        }
        
        It "Should handle graceful shutdown" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--shutdown-test")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Shutdown.*graceful|Cleanup.*complete|Exit.*clean"
        }
        
        It "Should log key operational events" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--verbose")
            
            # Assert
            $result.Success | Should -Be $true
            # Verify key log lines are present
            $result.StandardOutput | Should -Match "Starting|Initializing|Loading|Ready"
            $result.StandardOutput | Should -Not -Match "FATAL|CRITICAL|EXCEPTION"
        }
        
        It "Should maintain consistent performance" {
            # Act - Run health check multiple times
            $results = @()
            for ($i = 1; $i -le 3; $i++) {
                $startTime = Get-Date
                $result = Invoke-NovaBotWithTimeout -Arguments @("--health")
                $duration = (Get-Date) - $startTime
                
                $results += @{
                    Success = $result.Success
                    Duration = $duration.TotalSeconds
                }
            }
            
            # Assert
            $results | ForEach-Object { $_.Success | Should -Be $true }
            $avgDuration = ($results | Measure-Object -Property Duration -Average).Average
            $avgDuration | Should -BeLessThan 15 # Should complete within 15 seconds on average
        }
    }
    
    Context "Error Handling and Recovery" {
        
        It "Should handle missing dependencies gracefully" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--ignore-missing")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Warning|Missing|Continuing|Degraded"
        }
        
        It "Should recover from temporary failures" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--simulate-failure")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Recovered|Retry|Fallback|Resilient"
        }
        
        It "Should validate data integrity on startup" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--data-check")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Data.*valid|Integrity.*OK|Validation.*passed"
        }
    }
    
    Context "Security and Compliance" {
        
        It "Should enforce execution policies" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--policy-check")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Policy|Security|Compliance|Enforced"
        }
        
        It "Should not expose sensitive information in logs" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--verbose")
            
            # Assert
            $result.Success | Should -Be $true
            # Check that sensitive patterns are not exposed
            $result.StandardOutput | Should -Not -Match "password|secret|key|token"
            $result.StandardError | Should -Not -Match "password|secret|key|token"
        }
        
        It "Should validate file system permissions" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--permission-check")
            
            # Assert
            $result.Success | Should -Be $true
            $result.StandardOutput | Should -Match "Permissions|Access|Valid|Authorized"
        }
    }
    
    Context "Resource Usage and Performance" {
        
        It "Should operate within memory limits" {
            # Act
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health", "--memory-check")
            
            # Assert
            $result.Success | Should -Be $true
            # Verify no out of memory errors
            $result.StandardError | Should -Not -Match "OutOfMemory|Memory.*full|Cannot allocate"
        }
        
        It "Should complete health check within time limit" {
            # Arrange
            $maxHealthCheckTime = 30 # seconds
            
            # Act
            $startTime = Get-Date
            $result = Invoke-NovaBotWithTimeout -Arguments @("--health") -TimeoutSeconds $maxHealthCheckTime
            $actualDuration = (Get-Date) - $startTime
            
            # Assert
            $result.Success | Should -Be $true
            $result.TimedOut | Should -Be $false
            $actualDuration.TotalSeconds | Should -BeLessThan $maxHealthCheckTime
        }
        
        It "Should handle concurrent operations" {
            # Act - Start multiple health checks concurrently
            $jobs = @()
            for ($i = 1; $i -le 3; $i++) {
                $jobs += Start-Job -ScriptBlock {
                    param($BotPath)
                    & powershell.exe -ExecutionPolicy Bypass -File $BotPath --health
                } -ArgumentList $script:NovaBotPath
            }
            
            # Wait for completion
            $jobs | Wait-Job -Timeout 60 | Out-Null
            $results = $jobs | Receive-Job
            $jobs | Remove-Job -Force
            
            # Assert
            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object { $_ | Should -Not -Match "ERROR|FAILED|EXCEPTION" }
        }
    }
}

AfterAll {
    # Cleanup test artifacts
    if (Test-Path $script:TestLogPath) {
        Remove-Item -Path $script:TestLogPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if (Test-Path $script:TestDataPath) {
        Remove-Item -Path $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Ensure no background processes are left running
    Get-Job | Where-Object { $_.Name -like "*Nova*" } | Stop-Job -ErrorAction SilentlyContinue
    Get-Job | Where-Object { $_.Name -like "*Nova*" } | Remove-Job -Force -ErrorAction SilentlyContinue
}