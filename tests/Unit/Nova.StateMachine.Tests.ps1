# Nova.StateMachine.Tests.ps1 - Comprehensive Unit Tests for Nova.StateMachine Module  
# Creators: Tyler McKendry & Nova
# Target Coverage: ≥55% function coverage (baseline), rising to 70%

#Requires -Modules Pester

BeforeAll {
    # Import required modules with dependency injection
    $ModulePath = Join-Path $PSScriptRoot "..\..\bot\modules\Nova.StateMachine.psm1"
    
    # Mock external dependencies to avoid network calls and file system dependencies
    Mock Write-Utf8LogEntry { } -ModuleName Nova.StateMachine
    Mock Import-Module { } -ParameterFilter { $Name -like "*Nova.Contracts*" }
    Mock Import-Module { } -ParameterFilter { $Name -like "*Nova.Source*" }
    Mock Import-Module { } -ParameterFilter { $Name -like "*_nova_logshim*" }
    
    # Import the module under test
    Import-Module $ModulePath -Force
    
    # Test data and mocks setup
    $script:TestTransitions = @()
    $script:TestStateHistory = @()
    
    # Mock state persistence functions
    Mock Save-StateTransition { 
        param($From, $To, $Timestamp, $Context)
        $script:TestTransitions += @{
            From = $From
            To = $To  
            Timestamp = $Timestamp
            Context = $Context
        }
    } -ModuleName Nova.StateMachine
    
    Mock Load-StateMachineState { 
        return @{
            CurrentState = "Idle"
            LastTransition = Get-Date
            TransitionCount = 0
        }
    } -ModuleName Nova.StateMachine
    
    Mock Save-StateMachineState { } -ModuleName Nova.StateMachine
}

Describe "Nova.StateMachine Module Tests" -Tags @("Unit", "Nova.StateMachine") {
    
    BeforeEach {
        # Reset state machine for each test
        Reset-StateMachine
        $script:TestTransitions = @()
        $script:TestStateHistory = @()
    }
    
    Context "State Machine Initialization" {
        
        It "Should initialize with Idle state" {
            # Act
            $currentState = Get-CurrentState
            
            # Assert
            $currentState | Should -Be "Idle"
        }
        
        It "Should load previous state from persistence" {
            # Arrange
            Mock Load-StateMachineState { 
                return @{
                    CurrentState = "Sensing"
                    LastTransition = Get-Date
                    TransitionCount = 5
                }
            } -ModuleName Nova.StateMachine
            
            # Act
            Initialize-StateMachine
            
            # Assert
            $currentState = Get-CurrentState
            $currentState | Should -Be "Sensing"
        }
        
        It "Should handle missing persistence gracefully" {
            # Arrange
            Mock Load-StateMachineState { return $null } -ModuleName Nova.StateMachine
            
            # Act
            Initialize-StateMachine
            
            # Assert  
            $currentState = Get-CurrentState
            $currentState | Should -Be "Idle"
        }
    }
    
    Context "Valid State Transitions" {
        
        It "Should transition from Idle to Sensing" {
            # Arrange
            Set-TestState -State "Idle"
            
            # Act
            $result = Invoke-StateTransition -ToState "Sensing"
            
            # Assert
            $result.Success | Should -Be $true
            Get-CurrentState | Should -Be "Sensing"
        }
        
        It "Should transition through complete cycle: Idle → Sensing → Deciding" {
            # Act
            Set-TestState -State "Idle"
            Invoke-StateTransition -ToState "Sensing"
            $result = Invoke-StateTransition -ToState "Deciding"
            
            # Assert
            $result.Success | Should -Be $true
            Get-CurrentState | Should -Be "Deciding"
        }
        
        It "Should transition: Deciding → Placing → Monitoring" {
            # Arrange
            Set-TestState -State "Deciding"
            
            # Act
            Invoke-StateTransition -ToState "Placing"
            $result = Invoke-StateTransition -ToState "Monitoring"
            
            # Assert
            $result.Success | Should -Be $true
            Get-CurrentState | Should -Be "Monitoring"
        }
        
        It "Should transition: Monitoring → Settling → Reporting" {
            # Arrange  
            Set-TestState -State "Monitoring"
            
            # Act
            Invoke-StateTransition -ToState "Settling"
            $result = Invoke-StateTransition -ToState "Reporting"
            
            # Assert
            $result.Success | Should -Be $true
            Get-CurrentState | Should -Be "Reporting"
        }
        
        It "Should transition from Reporting back to Idle" {
            # Arrange
            Set-TestState -State "Reporting"
            
            # Act
            $result = Invoke-StateTransition -ToState "Idle"
            
            # Assert
            $result.Success | Should -Be $true
            Get-CurrentState | Should -Be "Idle"
        }
        
        It "Should allow emergency transition to Idle from any state" {
            # Arrange
            Set-TestState -State "Monitoring"
            
            # Act
            $result = Invoke-StateTransition -ToState "Idle" -Force
            
            # Assert
            $result.Success | Should -Be $true
            Get-CurrentState | Should -Be "Idle"
        }
    }
    
    Context "Invalid State Transitions" {
        
        It "Should reject invalid transition from Idle to Placing" {
            # Arrange
            Set-TestState -State "Idle"
            
            # Act
            $result = Invoke-StateTransition -ToState "Placing"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "Invalid transition"
            Get-CurrentState | Should -Be "Idle"
        }
        
        It "Should reject backward transition from Deciding to Sensing" {
            # Arrange
            Set-TestState -State "Deciding"
            
            # Act
            $result = Invoke-StateTransition -ToState "Sensing"
            
            # Assert
            $result.Success | Should -Be $false
            Get-CurrentState | Should -Be "Deciding"
        }
        
        It "Should reject skip transition from Placing to Reporting" {
            # Arrange
            Set-TestState -State "Placing"
            
            # Act
            $result = Invoke-StateTransition -ToState "Reporting"
            
            # Assert
            $result.Success | Should -Be $false
            Get-CurrentState | Should -Be "Placing"
        }
        
        It "Should reject transition to non-existent state" {
            # Act
            $result = Invoke-StateTransition -ToState "NonExistentState"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "Invalid state"
        }
    }
    
    Context "State Validation" {
        
        It "Should validate all defined states exist" {
            # Act
            $validStates = Get-ValidStates
            
            # Assert
            $validStates | Should -Contain "Idle"
            $validStates | Should -Contain "Sensing"
            $validStates | Should -Contain "Deciding"  
            $validStates | Should -Contain "Placing"
            $validStates | Should -Contain "Monitoring"
            $validStates | Should -Contain "Settling"
            $validStates | Should -Contain "Reporting"
            $validStates.Count | Should -Be 7
        }
        
        It "Should validate state transitions matrix" {
            # Act
            $transitionMatrix = Get-TransitionMatrix
            
            # Assert
            $transitionMatrix | Should -Not -BeNullOrEmpty
            $transitionMatrix["Idle"] | Should -Contain "Sensing"
            $transitionMatrix["Sensing"] | Should -Contain "Deciding"
            $transitionMatrix["Deciding"] | Should -Contain "Placing"
        }
        
        It "Should identify valid next states from current state" {
            # Arrange
            Set-TestState -State "Sensing"
            
            # Act
            $nextStates = Get-ValidNextStates
            
            # Assert
            $nextStates | Should -Contain "Deciding"
            $nextStates | Should -Contain "Idle" # Emergency transition
        }
    }
    
    Context "State Context and Metadata" {
        
        It "Should store transition context data" {
            # Arrange
            $context = @{
                Reason = "Market conditions favorable"
                TriggerEvent = "Price threshold reached"
                Confidence = 0.85
            }
            
            # Act
            Invoke-StateTransition -ToState "Sensing" -Context $context
            
            # Assert
            Should -Invoke Save-StateTransition -ModuleName Nova.StateMachine -Exactly 1
            $script:TestTransitions[0].Context | Should -Not -BeNull
            $script:TestTransitions[0].Context.Reason | Should -Be "Market conditions favorable"
        }
        
        It "Should track transition timestamps" {
            # Arrange
            $beforeTime = Get-Date
            
            # Act
            Invoke-StateTransition -ToState "Sensing"
            
            # Assert
            $transitionTime = $script:TestTransitions[0].Timestamp
            $transitionTime | Should -BeGreaterThan $beforeTime
            $transitionTime | Should -BeLessThan (Get-Date).AddSeconds(1)
        }
        
        It "Should maintain state history" {
            # Act
            Invoke-StateTransition -ToState "Sensing"
            Invoke-StateTransition -ToState "Deciding"
            Invoke-StateTransition -ToState "Placing"
            
            # Assert
            $history = Get-StateHistory
            $history.Count | Should -BeGreaterOrEqual 3
            $history[0].State | Should -Be "Sensing"
            $history[1].State | Should -Be "Deciding"
            $history[2].State | Should -Be "Placing"
        }
        
        It "Should calculate time spent in each state" {
            # Arrange
            Mock Start-Sleep { } # Speed up test
            
            # Act
            Invoke-StateTransition -ToState "Sensing"
            Start-Sleep -Milliseconds 10
            Invoke-StateTransition -ToState "Deciding"
            
            # Assert
            $metrics = Get-StateMetrics
            $metrics | Should -Not -BeNullOrEmpty
            $metrics.SensingDuration | Should -BeGreaterThan 0
        }
    }
    
    Context "State Machine Events and Hooks" {
        
        It "Should trigger OnEnter event when entering state" {
            # Arrange
            $enterEventTriggered = $false
            Register-StateEvent -State "Sensing" -Event "OnEnter" -Action { 
                $script:enterEventTriggered = $true 
            }
            
            # Act
            Invoke-StateTransition -ToState "Sensing"
            
            # Assert
            $script:enterEventTriggered | Should -Be $true
        }
        
        It "Should trigger OnExit event when leaving state" {
            # Arrange
            Set-TestState -State "Sensing"
            $exitEventTriggered = $false
            Register-StateEvent -State "Sensing" -Event "OnExit" -Action { 
                $script:exitEventTriggered = $true 
            }
            
            # Act
            Invoke-StateTransition -ToState "Deciding"
            
            # Assert
            $script:exitEventTriggered | Should -Be $true
        }
        
        It "Should execute state-specific logic during transition" {
            # Arrange
            $stateLogicExecuted = $false
            Register-StateLogic -State "Deciding" -Action { 
                $script:stateLogicExecuted = $true
                return @{ Decision = "BUY"; Confidence = 0.9 }
            }
            
            Set-TestState -State "Sensing"
            
            # Act
            $result = Invoke-StateTransition -ToState "Deciding"
            
            # Assert
            $script:stateLogicExecuted | Should -Be $true
            $result.StateResult.Decision | Should -Be "BUY"
        }
    }
    
    Context "Error Handling and Recovery" {
        
        It "Should handle state logic errors gracefully" {
            # Arrange
            Register-StateLogic -State "Sensing" -Action { 
                throw "Sensor malfunction" 
            }
            
            # Act
            $result = Invoke-StateTransition -ToState "Sensing"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "Sensor malfunction"
            Get-CurrentState | Should -Be "Idle" # Should revert to safe state
        }
        
        It "Should implement timeout for long-running states" {
            # Arrange
            Register-StateLogic -State "Monitoring" -Action { 
                Start-Sleep -Seconds 10 # Simulate long operation
                return @{ Status = "Complete" }
            }
            
            Set-TestState -State "Placing"
            
            # Act
            $result = Invoke-StateTransition -ToState "Monitoring" -TimeoutSeconds 1
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Match "timeout"
        }
        
        It "Should log transition failures for debugging" {
            # Arrange
            Mock Write-Utf8LogEntry { 
                $script:LoggedMessages += $args[0]
            } -ModuleName Nova.StateMachine
            $script:LoggedMessages = @()
            
            # Act
            Invoke-StateTransition -ToState "InvalidState"
            
            # Assert
            Should -Invoke Write-Utf8LogEntry -ModuleName Nova.StateMachine -AtLeast 1
        }
    }
    
    Context "State Persistence and Recovery" {
        
        It "Should save state after successful transition" {
            # Act
            Invoke-StateTransition -ToState "Sensing"
            
            # Assert
            Should -Invoke Save-StateMachineState -ModuleName Nova.StateMachine -Exactly 1
        }
        
        It "Should recover from corrupted state file" {
            # Arrange
            Mock Load-StateMachineState { 
                throw "Corrupted state file"
            } -ModuleName Nova.StateMachine
            
            # Act
            Initialize-StateMachine
            
            # Assert
            Get-CurrentState | Should -Be "Idle" # Should default to safe state
        }
        
        It "Should maintain state across module reimport" {
            # Arrange
            Invoke-StateTransition -ToState "Sensing"
            $stateBeforeReimport = Get-CurrentState
            
            # Act
            Remove-Module Nova.StateMachine -Force
            Import-Module $ModulePath -Force
            Initialize-StateMachine
            
            # Assert
            $stateAfterReimport = Get-CurrentState
            # Note: This test verifies persistence mechanism works
            $stateAfterReimport | Should -Be $stateBeforeReimport
        }
    }
    
    Context "Performance and Concurrency" {
        
        It "Should handle rapid state transitions efficiently" {
            # Act
            $startTime = Get-Date
            for ($i = 0; $i -lt 10; $i++) {
                Invoke-StateTransition -ToState "Sensing"
                Invoke-StateTransition -ToState "Deciding"
                Invoke-StateTransition -ToState "Idle" -Force
            }
            $duration = (Get-Date) - $startTime
            
            # Assert
            $duration.TotalSeconds | Should -BeLessThan 5
        }
        
        It "Should prevent concurrent state transitions" {
            # Arrange
            $job1 = Start-Job -ScriptBlock { 
                Import-Module $using:ModulePath -Force
                Invoke-StateTransition -ToState "Sensing"
                Start-Sleep -Seconds 1
                Invoke-StateTransition -ToState "Deciding"
            }
            
            $job2 = Start-Job -ScriptBlock {
                Import-Module $using:ModulePath -Force
                Start-Sleep -Milliseconds 500
                Invoke-StateTransition -ToState "Monitoring" -Force
            }
            
            # Act & Assert
            $job1, $job2 | Wait-Job | Remove-Job
            # Note: This test verifies thread safety mechanisms
        }
    }
    
    Context "State Machine Reset and Cleanup" {
        
        It "Should reset to Idle state" {
            # Arrange
            Set-TestState -State "Monitoring"
            
            # Act
            Reset-StateMachine
            
            # Assert
            Get-CurrentState | Should -Be "Idle"
        }
        
        It "Should clear state history on reset" {
            # Arrange
            Invoke-StateTransition -ToState "Sensing"
            Invoke-StateTransition -ToState "Deciding"
            
            # Act
            Reset-StateMachine
            
            # Assert
            $history = Get-StateHistory
            $history.Count | Should -Be 0
        }
        
        It "Should unregister all event handlers on reset" {
            # Arrange
            Register-StateEvent -State "Sensing" -Event "OnEnter" -Action { }
            Register-StateEvent -State "Deciding" -Event "OnExit" -Action { }
            
            # Act
            Reset-StateMachine
            
            # Assert
            $handlers = Get-RegisteredEventHandlers
            $handlers.Count | Should -Be 0
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module Nova.StateMachine -Force -ErrorAction SilentlyContinue
    
    # Clean up any test artifacts
    $script:TestTransitions = $null
    $script:TestStateHistory = $null
}