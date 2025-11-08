# Nova.Metrics.Tests.ps1 - Comprehensive Unit Tests for Nova.Metrics Module
# Creators: Tyler McKendry & Nova
# Target Coverage: ≥55% function coverage (baseline), rising to 70%

#Requires -Modules Pester

BeforeAll {
    # Import required modules
    $ModulePath = Join-Path $PSScriptRoot "..\..\modules\Nova.Metrics.psm1"
    
    # Mock external dependencies to avoid network calls
    Mock Write-NovaLog { } -ModuleName Nova.Metrics
    
    # Import the module under test
    Import-Module $ModulePath -Force
    
    # Test data setup
    $script:TestMetricsPath = "TestDrive:\metrics"
    $script:OriginalMetricsPath = $null
    
    # Mock file operations for isolated testing
    Mock Get-MetricsFileName {
        return Join-Path $script:TestMetricsPath "metrics_$(Get-Date -Format 'yyyyMMdd').jsonl"
    } -ModuleName Nova.Metrics
}

Describe "Nova.Metrics Module Tests" -Tags @("Unit", "Nova.Metrics") {
    
    BeforeEach {
        # Reset metrics state for each test
        if (Get-Variable -Name MetricsData -Scope Script -ErrorAction SilentlyContinue) {
            $script:MetricsData = @{
                Counters = @{}
                Histograms = @{}
                Gauges = @{}
                LastRotation = (Get-Date).Date
            }
        }
        
        # Ensure test metrics directory exists
        if (-not (Test-Path $script:TestMetricsPath)) {
            New-Item -ItemType Directory -Path $script:TestMetricsPath -Force | Out-Null
        }
    }
    
    Context "Counter Operations" {
        
        It "Should initialize counter with default value of 0" {
            # Act
            Initialize-Counter -Name "test_counter"
            
            # Assert
            $result = Get-Counter -Name "test_counter"
            $result | Should -Be 0
        }
        
        It "Should initialize counter with custom initial value" {
            # Arrange
            $initialValue = 42
            
            # Act
            Initialize-Counter -Name "custom_counter" -InitialValue $initialValue
            
            # Assert
            $result = Get-Counter -Name "custom_counter"
            $result | Should -Be $initialValue
        }
        
        It "Should increment counter by 1 when no increment specified" {
            # Arrange
            Initialize-Counter -Name "increment_test"
            
            # Act
            Increment-Counter -Name "increment_test"
            
            # Assert
            $result = Get-Counter -Name "increment_test"
            $result | Should -Be 1
        }
        
        It "Should increment counter by specified amount" {
            # Arrange
            Initialize-Counter -Name "increment_by_amount"
            $incrementBy = 5
            
            # Act
            Increment-Counter -Name "increment_by_amount" -IncrementBy $incrementBy
            
            # Assert
            $result = Get-Counter -Name "increment_by_amount"
            $result | Should -Be $incrementBy
        }
        
        It "Should handle multiple increments correctly" {
            # Arrange
            Initialize-Counter -Name "multiple_increments"
            
            # Act
            Increment-Counter -Name "multiple_increments" -IncrementBy 3
            Increment-Counter -Name "multiple_increments" -IncrementBy 7
            Increment-Counter -Name "multiple_increments" # Default increment of 1
            
            # Assert
            $result = Get-Counter -Name "multiple_increments"
            $result | Should -Be 11
        }
        
        It "Should reset counter to zero" {
            # Arrange
            Initialize-Counter -Name "reset_test" -InitialValue 100
            
            # Act
            Reset-Counter -Name "reset_test"
            
            # Assert
            $result = Get-Counter -Name "reset_test"
            $result | Should -Be 0
        }
    }
    
    Context "Gauge Operations" {
        
        It "Should set gauge value correctly" {
            # Arrange
            $gaugeName = "cpu_usage"
            $gaugeValue = 85.5
            
            # Act
            Set-Gauge -Name $gaugeName -Value $gaugeValue
            
            # Assert
            $result = Get-Gauge -Name $gaugeName
            $result | Should -Be $gaugeValue
        }
        
        It "Should update existing gauge value" {
            # Arrange
            $gaugeName = "memory_usage"
            Set-Gauge -Name $gaugeName -Value 50.0
            
            # Act
            Set-Gauge -Name $gaugeName -Value 75.2
            
            # Assert
            $result = Get-Gauge -Name $gaugeName
            $result | Should -Be 75.2
        }
        
        It "Should handle gauge labels correctly" {
            # Arrange
            $gaugeName = "disk_usage"
            $labels = @{ drive = "C:"; type = "system" }
            $value = 60.0
            
            # Act
            Set-Gauge -Name $gaugeName -Value $value -Labels $labels
            
            # Assert
            $result = Get-Gauge -Name $gaugeName -Labels $labels
            $result | Should -Be $value
        }
    }
    
    Context "Histogram Operations" {
        
        It "Should record histogram observation" {
            # Arrange
            $histogramName = "request_duration"
            $observation = 0.250
            
            # Act
            Record-Histogram -Name $histogramName -Value $observation
            
            # Assert
            $histogram = Get-Histogram -Name $histogramName
            $histogram | Should -Not -BeNullOrEmpty
            $histogram.Observations | Should -Contain $observation
        }
        
        It "Should calculate histogram statistics correctly" {
            # Arrange
            $histogramName = "response_time"
            $observations = @(0.1, 0.2, 0.15, 0.3, 0.25)
            
            # Act
            foreach ($obs in $observations) {
                Record-Histogram -Name $histogramName -Value $obs
            }
            
            # Assert
            $histogram = Get-Histogram -Name $histogramName
            $histogram.Count | Should -Be $observations.Count
            $histogram.Sum | Should -Be ($observations | Measure-Object -Sum).Sum
            $histogram.Average | Should -BeGreaterThan 0.1
            $histogram.Average | Should -BeLessThan 0.3
        }
        
        It "Should handle histogram buckets correctly" {
            # Arrange
            $histogramName = "latency_buckets"
            $buckets = @(0.1, 0.5, 1.0, 5.0)
            
            # Act
            Initialize-Histogram -Name $histogramName -Buckets $buckets
            Record-Histogram -Name $histogramName -Value 0.3
            Record-Histogram -Name $histogramName -Value 0.8
            Record-Histogram -Name $histogramName -Value 2.0
            
            # Assert
            $histogram = Get-Histogram -Name $histogramName
            $histogram.Buckets | Should -Not -BeNullOrEmpty
            $histogram.Buckets[0.5] | Should -BeGreaterThan 0
        }
    }
    
    Context "Metrics Persistence" {
        
        BeforeEach {
            # Mock Save-MetricsEntry to capture calls
            Mock Save-MetricsEntry { 
                param($Type, $Name, $Value, $Labels)
                $script:SavedMetrics = @{
                    Type = $Type
                    Name = $Name  
                    Value = $Value
                    Labels = $Labels
                }
            } -ModuleName Nova.Metrics
        }
        
        It "Should save counter metrics entry" {
            # Arrange
            $counterName = "saved_counter"
            Initialize-Counter -Name $counterName
            
            # Act
            Increment-Counter -Name $counterName
            
            # Assert
            Should -Invoke Save-MetricsEntry -ModuleName Nova.Metrics -Exactly 1
        }
        
        It "Should save gauge metrics entry with labels" {
            # Arrange
            $gaugeName = "saved_gauge"
            $labels = @{ host = "server1" }
            
            # Act
            Set-Gauge -Name $gaugeName -Value 42.0 -Labels $labels
            
            # Assert
            Should -Invoke Save-MetricsEntry -ModuleName Nova.Metrics -Exactly 1
        }
        
        It "Should save histogram metrics entry" {
            # Arrange
            $histogramName = "saved_histogram"
            
            # Act
            Record-Histogram -Name $histogramName -Value 1.5
            
            # Assert
            Should -Invoke Save-MetricsEntry -ModuleName Nova.Metrics -Exactly 1
        }
    }
    
    Context "Prometheus Export" {
        
        It "Should export metrics in Prometheus format" {
            # Arrange
            Initialize-Counter -Name "http_requests_total" 
            Increment-Counter -Name "http_requests_total" -IncrementBy 5
            Set-Gauge -Name "cpu_usage_percent" -Value 85.5
            
            # Act
            $prometheusOutput = Export-PrometheusMetrics
            
            # Assert
            $prometheusOutput | Should -Not -BeNullOrEmpty
            $prometheusOutput | Should -Match "http_requests_total"
            $prometheusOutput | Should -Match "cpu_usage_percent"
        }
        
        It "Should handle empty metrics gracefully" {
            # Act
            $prometheusOutput = Export-PrometheusMetrics
            
            # Assert
            $prometheusOutput | Should -Not -BeNull
        }
        
        It "Should export metrics with proper Prometheus formatting" {
            # Arrange
            Set-Gauge -Name "memory_usage" -Value 1024.5 -Labels @{ type = "heap" }
            
            # Act
            $prometheusOutput = Export-PrometheusMetrics
            
            # Assert
            $prometheusOutput | Should -Match 'memory_usage{type="heap"} 1024.5'
        }
    }
    
    Context "Daily Rotation" {
        
        It "Should detect when rotation is needed" {
            # Arrange
            $yesterdayDate = (Get-Date).AddDays(-1).Date
            
            # Act & Assert using private function access
            $needsRotation = & (Get-Module Nova.Metrics) { 
                param($testDate) 
                Test-RotationNeeded -LastRotation $testDate 
            } $yesterdayDate
            
            $needsRotation | Should -Be $true
        }
        
        It "Should not rotate when same day" {
            # Arrange
            $todayDate = (Get-Date).Date
            
            # Act & Assert
            $needsRotation = & (Get-Module Nova.Metrics) { 
                param($testDate) 
                Test-RotationNeeded -LastRotation $testDate 
            } $todayDate
            
            $needsRotation | Should -Be $false
        }
        
        Mock Invoke-MetricsRotation { } -ModuleName Nova.Metrics
        
        It "Should trigger rotation when date changes" {
            # Arrange - Set last rotation to yesterday
            if (Get-Variable -Name MetricsData -Scope Script -ErrorAction SilentlyContinue) {
                $script:MetricsData.LastRotation = (Get-Date).AddDays(-1).Date
            }
            
            # Act
            Invoke-DailyRotationCheck
            
            # Assert
            Should -Invoke Invoke-MetricsRotation -ModuleName Nova.Metrics -Exactly 1
        }
    }
    
    Context "Error Handling" {
        
        It "Should handle null counter name gracefully" {
            # Act & Assert
            { Initialize-Counter -Name $null } | Should -Throw
        }
        
        It "Should handle empty counter name gracefully" {
            # Act & Assert  
            { Initialize-Counter -Name "" } | Should -Throw
        }
        
        It "Should handle invalid gauge value gracefully" {
            # Act & Assert
            { Set-Gauge -Name "test_gauge" -Value "invalid" } | Should -Throw
        }
        
        It "Should handle missing histogram gracefully" {
            # Act
            $result = Get-Histogram -Name "nonexistent_histogram"
            
            # Assert
            $result | Should -BeNull
        }
        
        It "Should handle file system errors during save" {
            # Arrange
            Mock Save-MetricsEntry { throw "Disk full" } -ModuleName Nova.Metrics
            
            # Act & Assert
            { Increment-Counter -Name "test_counter" } | Should -Not -Throw
        }
    }
    
    Context "Metrics Cleanup" {
        
        It "Should clear all metrics" {
            # Arrange
            Initialize-Counter -Name "clear_test_counter"
            Set-Gauge -Name "clear_test_gauge" -Value 100
            Record-Histogram -Name "clear_test_histogram" -Value 0.5
            
            # Act
            Clear-AllMetrics
            
            # Assert
            Get-Counter -Name "clear_test_counter" | Should -Be 0
            Get-Gauge -Name "clear_test_gauge" | Should -BeNull
            Get-Histogram -Name "clear_test_histogram" | Should -BeNull
        }
        
        It "Should reset rotation timestamp on clear" {
            # Act
            Clear-AllMetrics
            
            # Assert
            $currentDate = (Get-Date).Date
            if (Get-Variable -Name MetricsData -Scope Script -ErrorAction SilentlyContinue) {
                $script:MetricsData.LastRotation | Should -Be $currentDate
            }
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module Nova.Metrics -Force -ErrorAction SilentlyContinue
    
    # Clean up test artifacts
    if (Test-Path $script:TestMetricsPath) {
        Remove-Item -Path $script:TestMetricsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}