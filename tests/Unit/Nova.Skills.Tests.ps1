# Nova.Skills.Tests.ps1 - Comprehensive Unit Tests for Nova.Skills Module
# Creators: Tyler McKendry & Nova  
# Target Coverage: ≥55% function coverage (baseline), rising to 70%

#Requires -Modules Pester

BeforeAll {
    # Import required modules
    $ModulePath = Join-Path $PSScriptRoot "..\..\modules\Nova.Skills.psm1"
    
    # Mock external dependencies to avoid network calls and file system dependencies
    Mock Write-NovaLog { } -ModuleName Nova.Skills
    Mock Import-Module { } -ParameterFilter { $Name -like "*_nova_logshim*" }
    
    # Import the module under test
    Import-Module $ModulePath -Force
    
    # Test data setup
    $script:TestQueuePath = "TestDrive:\queue"
    $script:TestActionQueue = @()
    $script:TestApprovalQueue = @()
    
    # Mock file operations for isolated testing  
    Mock Get-QueuePath {
        return $script:TestQueuePath
    } -ModuleName Nova.Skills
    
    Mock Save-Action { 
        param($Action)
        $script:TestActionQueue += $Action
    } -ModuleName Nova.Skills
    
    Mock Load-PendingActions { 
        return $script:TestActionQueue | Where-Object { $_.Status -eq "pending" }
    } -ModuleName Nova.Skills
    
    Mock Remove-ActionFromQueue { 
        param($ActionId)
        $script:TestActionQueue = $script:TestActionQueue | Where-Object { $_.Id -ne $ActionId }
    } -ModuleName Nova.Skills
}

Describe "Nova.Skills Module Tests" -Tags @("Unit", "Nova.Skills") {
    
    BeforeEach {
        # Reset test state for each test
        $script:TestActionQueue = @()
        $script:TestApprovalQueue = @()
        
        # Ensure test queue directory exists
        if (-not (Test-Path $script:TestQueuePath)) {
            New-Item -ItemType Directory -Path $script:TestQueuePath -Force | Out-Null
        }
    }
    
    Context "NovaAction Class Tests" {
        
        It "Should create NovaAction with required properties" {
            # Arrange
            $skill = "filesystem"
            $command = "create_directory"
            $parameters = @{ Path = "C:\Test"; Permissions = "ReadWrite" }
            $mode = [ActionMode]::RequireApproval
            
            # Act
            $action = [NovaAction]::new($skill, $command, $parameters, $mode)
            
            # Assert
            $action.Skill | Should -Be $skill
            $action.Command | Should -Be $command
            $action.Parameters.Path | Should -Be "C:\Test"
            $action.Mode | Should -Be ([ActionMode]::RequireApproval)
            $action.Status | Should -Be "pending"
            $action.Id | Should -Not -BeNullOrEmpty
            $action.Timestamp | Should -BeOfType [DateTime]
            $action.RequestedBy | Should -Be $env:USERNAME
        }
        
        It "Should generate unique action IDs" {
            # Act
            $action1 = [NovaAction]::new("skill1", "cmd1", @{}, [ActionMode]::DryRun)
            $action2 = [NovaAction]::new("skill2", "cmd2", @{}, [ActionMode]::Execute)
            
            # Assert
            $action1.Id | Should -Not -Be $action2.Id
            $action1.Id.Length | Should -Be 8
            $action2.Id.Length | Should -Be 8
        }
        
        It "Should handle different ActionMode enums correctly" {
            # Act
            $dryRunAction = [NovaAction]::new("test", "test", @{}, [ActionMode]::DryRun)
            $approvalAction = [NovaAction]::new("test", "test", @{}, [ActionMode]::RequireApproval)  
            $executeAction = [NovaAction]::new("test", "test", @{}, [ActionMode]::Execute)
            
            # Assert
            $dryRunAction.Mode | Should -Be ([ActionMode]::DryRun)
            $approvalAction.Mode | Should -Be ([ActionMode]::RequireApproval)
            $executeAction.Mode | Should -Be ([ActionMode]::Execute)
        }
    }
    
    Context "Action Submission" {
        
        It "Should submit filesystem action successfully" {
            # Arrange
            $actionType = "filesystem"
            $action = "create_directory"
            $path = "D:\Nova\temp\test"
            
            # Act
            $result = Submit-Action -Type $actionType -Action $action -Path $path
            
            # Assert
            $result.Success | Should -Be $true
            $result.ActionId | Should -Not -BeNullOrEmpty
            Should -Invoke Save-Action -ModuleName Nova.Skills -Exactly 1
        }
        
        It "Should submit network action with proper parameters" {
            # Arrange
            $actionType = "network"
            $action = "http_request"
            $url = "https://api.example.com/data"
            $method = "GET"
            
            # Act
            $result = Submit-Action -Type $actionType -Action $action -Url $url -Method $method
            
            # Assert
            $result.Success | Should -Be $true
            $savedAction = $script:TestActionQueue[0]
            $savedAction.Skill | Should -Be "network"
            $savedAction.Command | Should -Be "http_request"
            $savedAction.Parameters.Url | Should -Be $url
            $savedAction.Parameters.Method | Should -Be $method
        }
        
        It "Should submit system action with mode specification" {
            # Act
            $result = Submit-Action -Type "system" -Action "restart_service" -ServiceName "NovaBot" -Mode DryRun
            
            # Assert
            $result.Success | Should -Be $true
            $savedAction = $script:TestActionQueue[0]
            $savedAction.Mode | Should -Be ([ActionMode]::DryRun)
            $savedAction.Parameters.ServiceName | Should -Be "NovaBot"
        }
        
        It "Should handle invalid action type gracefully" {
            # Act
            $result = Submit-Action -Type "invalid_type" -Action "some_action"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "Invalid action type"
        }
        
        It "Should validate required parameters for filesystem actions" {
            # Act
            $result = Submit-Action -Type "filesystem" -Action "create_directory" # Missing Path
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "Path parameter required"
        }
    }
    
    Context "Action Queue Management" {
        
        It "Should retrieve pending actions from queue" {
            # Arrange
            Submit-Action -Type "filesystem" -Action "create_file" -Path "test1.txt"
            Submit-Action -Type "system" -Action "check_status" -Service "test"
            Submit-Action -Type "network" -Action "ping" -Host "localhost"
            
            # Act
            $pendingActions = Get-PendingActions
            
            # Assert
            $pendingActions.Count | Should -Be 3
            $pendingActions[0].Status | Should -Be "pending"
            $pendingActions | Should -BeOfType [NovaAction]
        }
        
        It "Should filter actions by type" {
            # Arrange
            Submit-Action -Type "filesystem" -Action "create_file" -Path "test1.txt"
            Submit-Action -Type "network" -Action "ping" -Host "localhost"  
            Submit-Action -Type "filesystem" -Action "delete_file" -Path "test2.txt"
            
            # Act
            $filesystemActions = Get-PendingActions -FilterByType "filesystem"
            
            # Assert
            $filesystemActions.Count | Should -Be 2
            $filesystemActions | ForEach-Object { $_.Skill | Should -Be "filesystem" }
        }
        
        It "Should get specific action by ID" {
            # Arrange
            $submitResult = Submit-Action -Type "system" -Action "get_info" -Target "cpu"
            $actionId = $submitResult.ActionId
            
            # Act
            $action = Get-Action -ActionId $actionId
            
            # Assert
            $action | Should -Not -BeNull
            $action.Id | Should -Be $actionId
            $action.Command | Should -Be "get_info"
        }
        
        It "Should handle non-existent action ID gracefully" {
            # Act
            $action = Get-Action -ActionId "nonexistent"
            
            # Assert
            $action | Should -BeNull
        }
    }
    
    Context "Action Approval Workflow" {
        
        It "Should approve pending action" {
            # Arrange
            $submitResult = Submit-Action -Type "filesystem" -Action "create_directory" -Path "C:\Test" -Mode RequireApproval
            $actionId = $submitResult.ActionId
            
            # Act
            $approvalResult = Approve-Action -ActionId $actionId -ApprovedBy "TestUser"
            
            # Assert
            $approvalResult.Success | Should -Be $true
            $action = Get-Action -ActionId $actionId
            $action.Status | Should -Be "approved"
        }
        
        It "Should reject action with reason" {
            # Arrange
            $submitResult = Submit-Action -Type "network" -Action "external_api_call" -Url "https://example.com" -Mode RequireApproval
            $actionId = $submitResult.ActionId
            $rejectionReason = "Security policy violation"
            
            # Act
            $rejectionResult = Reject-Action -ActionId $actionId -Reason $rejectionReason -RejectedBy "SecurityTeam"
            
            # Assert
            $rejectionResult.Success | Should -Be $true
            $action = Get-Action -ActionId $actionId
            $action.Status | Should -Be "rejected"
            $action.Reason | Should -Be $rejectionReason
        }
        
        It "Should prevent approval of already processed action" {
            # Arrange
            $submitResult = Submit-Action -Type "system" -Action "restart" -Service "TestService" -Mode RequireApproval
            $actionId = $submitResult.ActionId
            Approve-Action -ActionId $actionId -ApprovedBy "TestUser"
            
            # Act
            $duplicateApproval = Approve-Action -ActionId $actionId -ApprovedBy "AnotherUser"
            
            # Assert
            $duplicateApproval.Success | Should -Be $false
            $duplicateApproval.Error | Should -Match "already processed"
        }
    }
    
    Context "Action Execution Engine" {
        
        BeforeEach {
            # Mock skill implementations
            Mock Invoke-FilesystemSkill { 
                param($Command, $Parameters)
                return @{
                    Success = $true
                    Result = "Filesystem operation: $Command completed"
                    Output = $Parameters
                }
            } -ModuleName Nova.Skills
            
            Mock Invoke-NetworkSkill { 
                param($Command, $Parameters)
                return @{
                    Success = $true
                    Result = "Network operation: $Command completed"
                    ResponseCode = 200
                }
            } -ModuleName Nova.Skills
            
            Mock Invoke-SystemSkill { 
                param($Command, $Parameters)
                return @{
                    Success = $true
                    Result = "System operation: $Command completed"
                    ExitCode = 0
                }
            } -ModuleName Nova.Skills
        }
        
        It "Should execute approved filesystem action" {
            # Arrange
            $submitResult = Submit-Action -Type "filesystem" -Action "create_directory" -Path "C:\TestDir" -Mode Execute
            $actionId = $submitResult.ActionId
            
            # Act
            $executionResult = Invoke-ActionExecution -ActionId $actionId
            
            # Assert
            $executionResult.Success | Should -Be $true
            Should -Invoke Invoke-FilesystemSkill -ModuleName Nova.Skills -Exactly 1
            $action = Get-Action -ActionId $actionId
            $action.Status | Should -Be "completed"
        }
        
        It "Should execute network action with proper parameters" {
            # Arrange
            $submitResult = Submit-Action -Type "network" -Action "http_get" -Url "https://api.test.com" -Mode Execute
            $actionId = $submitResult.ActionId
            
            # Act
            $executionResult = Invoke-ActionExecution -ActionId $actionId
            
            # Assert
            $executionResult.Success | Should -Be $true
            Should -Invoke Invoke-NetworkSkill -ModuleName Nova.Skills -Exactly 1
        }
        
        It "Should handle skill execution failure gracefully" {
            # Arrange
            Mock Invoke-SystemSkill { 
                throw "Service not found"
            } -ModuleName Nova.Skills
            
            $submitResult = Submit-Action -Type "system" -Action "stop_service" -ServiceName "NonExistent" -Mode Execute
            $actionId = $submitResult.ActionId
            
            # Act
            $executionResult = Invoke-ActionExecution -ActionId $actionId
            
            # Assert
            $executionResult.Success | Should -Be $false
            $executionResult.Error | Should -Match "Service not found"
            $action = Get-Action -ActionId $actionId
            $action.Status | Should -Be "failed"
        }
        
        It "Should perform dry run without actual execution" {
            # Arrange  
            $submitResult = Submit-Action -Type "filesystem" -Action "delete_file" -Path "important_file.txt" -Mode DryRun
            $actionId = $submitResult.ActionId
            
            # Act
            $dryRunResult = Invoke-ActionExecution -ActionId $actionId
            
            # Assert
            $dryRunResult.Success | Should -Be $true
            $dryRunResult.DryRun | Should -Be $true
            Should -Not -Invoke Invoke-FilesystemSkill -ModuleName Nova.Skills
            $action = Get-Action -ActionId $actionId
            $action.Status | Should -Be "dry_run_completed"
        }
        
        It "Should prevent execution of non-approved actions" {
            # Arrange
            $submitResult = Submit-Action -Type "system" -Action "format_drive" -Drive "C:" -Mode RequireApproval
            $actionId = $submitResult.ActionId
            # Note: Not approving the action
            
            # Act
            $executionResult = Invoke-ActionExecution -ActionId $actionId
            
            # Assert
            $executionResult.Success | Should -Be $false
            $executionResult.Error | Should -Match "not approved"
            Should -Not -Invoke Invoke-SystemSkill -ModuleName Nova.Skills
        }
    }
    
    Context "Skill Implementations" {
        
        It "Should validate filesystem skill operations" {
            # Act & Assert
            { Test-FilesystemOperation -Command "create_directory" -Parameters @{ Path = "C:\Valid\Path" } } | Should -Not -Throw
            { Test-FilesystemOperation -Command "invalid_operation" -Parameters @{} } | Should -Throw
        }
        
        It "Should validate network skill operations" {
            # Act & Assert
            { Test-NetworkOperation -Command "http_request" -Parameters @{ Url = "https://valid.com" } } | Should -Not -Throw
            { Test-NetworkOperation -Command "http_request" -Parameters @{ Url = "invalid-url" } } | Should -Throw
        }
        
        It "Should validate system skill operations" {
            # Act & Assert
            { Test-SystemOperation -Command "get_service_status" -Parameters @{ ServiceName = "ValidService" } } | Should -Not -Throw
            { Test-SystemOperation -Command "get_service_status" -Parameters @{} } | Should -Throw
        }
    }
    
    Context "Security and Sandboxing" {
        
        It "Should reject dangerous filesystem operations" {
            # Act
            $result = Submit-Action -Type "filesystem" -Action "delete_directory" -Path "C:\Windows\System32"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "blocked by security policy"
        }
        
        It "Should validate network destinations against allowlist" {
            # Act
            $result = Submit-Action -Type "network" -Action "http_request" -Url "http://malicious-site.com"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "not in allowed destinations"
        }
        
        It "Should restrict system operations to safe commands" {
            # Act
            $result = Submit-Action -Type "system" -Action "format_drive" -Drive "C:"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "dangerous system operation"
        }
        
        It "Should enforce execution time limits" {
            # Arrange
            Mock Invoke-FilesystemSkill { 
                Start-Sleep -Seconds 10 # Simulate long operation
                return @{ Success = $true }
            } -ModuleName Nova.Skills
            
            $submitResult = Submit-Action -Type "filesystem" -Action "long_operation" -Path "test" -Mode Execute
            $actionId = $submitResult.ActionId
            
            # Act
            $executionResult = Invoke-ActionExecution -ActionId $actionId -TimeoutSeconds 2
            
            # Assert
            $executionResult.Success | Should -Be $false
            $executionResult.Error | Should -Match "timeout"
        }
    }
    
    Context "Action History and Auditing" {
        
        It "Should maintain complete action history" {
            # Arrange
            Submit-Action -Type "filesystem" -Action "create_file" -Path "test1.txt" -Mode Execute
            Submit-Action -Type "system" -Action "get_status" -Service "TestService" -Mode DryRun
            Submit-Action -Type "network" -Action "ping" -Host "localhost" -Mode RequireApproval
            
            # Act
            $history = Get-ActionHistory
            
            # Assert
            $history.Count | Should -BeGreaterOrEqual 3
            $history | Should -BeOfType [NovaAction]
        }
        
        It "Should filter history by date range" {
            # Arrange
            $yesterday = (Get-Date).AddDays(-1)
            $tomorrow = (Get-Date).AddDays(1)
            
            # Act
            $recentHistory = Get-ActionHistory -From $yesterday -To $tomorrow
            
            # Assert
            $recentHistory | Should -Not -BeNull
            $recentHistory | ForEach-Object { 
                $_.Timestamp | Should -BeGreaterThan $yesterday
                $_.Timestamp | Should -BeLessThan $tomorrow
            }
        }
        
        It "Should export action history for compliance" {
            # Arrange
            Submit-Action -Type "filesystem" -Action "audit_test" -Path "audit.log" -Mode Execute
            
            # Act
            $exportPath = "TestDrive:\action_export.json"
            Export-ActionHistory -OutputPath $exportPath -Format JSON
            
            # Assert
            Test-Path $exportPath | Should -Be $true
            $exportedData = Get-Content $exportPath | ConvertFrom-Json
            $exportedData | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Error Handling and Resilience" {
        
        It "Should handle queue corruption gracefully" {
            # Arrange
            Mock Load-PendingActions { 
                throw "Queue file corrupted"
            } -ModuleName Nova.Skills
            
            # Act & Assert
            { Get-PendingActions } | Should -Not -Throw
            $actions = Get-PendingActions
            $actions | Should -BeNullOrEmpty
        }
        
        It "Should retry failed actions with exponential backoff" {
            # Arrange
            $retryCount = 0
            Mock Invoke-NetworkSkill { 
                $script:retryCount++
                if ($script:retryCount -lt 3) {
                    throw "Network timeout"
                }
                return @{ Success = $true; Result = "Success after retries" }
            } -ModuleName Nova.Skills
            
            $submitResult = Submit-Action -Type "network" -Action "retry_test" -Url "https://unreliable.com" -Mode Execute
            $actionId = $submitResult.ActionId
            
            # Act
            $executionResult = Invoke-ActionExecution -ActionId $actionId -EnableRetry
            
            # Assert
            $executionResult.Success | Should -Be $true
            Should -Invoke Invoke-NetworkSkill -ModuleName Nova.Skills -Exactly 3
        }
        
        It "Should handle skill module loading failures" {
            # Arrange
            Mock Import-Module { 
                throw "Skill module not found"
            } -ParameterFilter { $Name -like "*CustomSkill*" }
            
            # Act
            $result = Submit-Action -Type "custom_skill" -Action "test_action" -Parameter "value"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "skill module not available"
        }
    }
    
    Context "Performance and Resource Management" {
        
        It "Should limit concurrent action executions" {
            # Arrange
            $concurrentLimit = 3
            Set-ConcurrencyLimit -MaxConcurrentActions $concurrentLimit
            
            # Act - Submit more actions than the limit
            $jobs = @()
            for ($i = 1; $i -le 5; $i++) {
                $submitResult = Submit-Action -Type "system" -Action "sleep_test" -Duration $i -Mode Execute
                $jobs += Start-Job { Invoke-ActionExecution -ActionId $using:submitResult.ActionId }
            }
            
            Start-Sleep -Seconds 1 # Allow some processing
            $runningJobs = $jobs | Where-Object { $_.State -eq "Running" }
            
            # Assert
            $runningJobs.Count | Should -BeLessOrEqual $concurrentLimit
            
            # Cleanup
            $jobs | Stop-Job -ErrorAction SilentlyContinue
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
        }
        
        It "Should clean up old completed actions" {
            # Arrange
            # Create old actions (simulate by mocking timestamps)
            Mock Get-Date { return (Get-Date).AddDays(-8) } # 8 days ago
            Submit-Action -Type "filesystem" -Action "old_action" -Path "old.txt" -Mode Execute
            
            Mock Get-Date { return Get-Date } # Reset to current time
            
            # Act
            Invoke-ActionCleanup -RetentionDays 7
            
            # Assert
            $remainingActions = Get-ActionHistory
            $oldActions = $remainingActions | Where-Object { $_.Timestamp -lt (Get-Date).AddDays(-7) }
            $oldActions.Count | Should -Be 0
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module Nova.Skills -Force -ErrorAction SilentlyContinue
    
    # Clean up test artifacts
    if (Test-Path $script:TestQueuePath) {
        Remove-Item -Path $script:TestQueuePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $script:TestActionQueue = $null
    $script:TestApprovalQueue = $null
}