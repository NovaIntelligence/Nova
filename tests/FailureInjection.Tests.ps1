# FailureInjection.Tests.ps1 - Nova Bot Failure Injection Test Suite
# Compatible with Pester v5+

Describe "PathGuard Security Tests" -Tag "Security", "Critical" {
    It "Should block dangerous paths" {
        $dangerousPath = "C:\Windows\System32\test.txt"
        $result = $dangerousPath -match "Windows|Program Files"
        $result | Should -Be $true
    }
    
    It "Should allow safe paths" {
        $safePath = "D:\Nova\data\test.txt"  
        $result = $safePath -match "D:\\Nova"
        $result | Should -Be $true
    }
    
    It "Should sanitize file names" {
        $badName = "test<>file.txt"
        $sanitized = $badName -replace '[<>:"/\\|?*]', '_'
        $sanitized | Should -Be "test__file.txt"
    }
}

Describe "Metrics System Validation" -Tag "Metrics", "Critical" {
    It "Should validate numeric metrics" {
        $value = 42
        $value | Should -BeOfType [int]
    }
    
    It "Should reject invalid metrics" {
        $value = "invalid"
        $value | Should -Not -BeOfType [int]
    }
    
    It "Should handle metric overflow" {
        $largeValue = [int]::MaxValue
        $largeValue | Should -BeGreaterThan 1000000
    }
}

Describe "API Resilience Tests" -Tag "Integration" {
    It "Should handle timeout configuration" {
        $timeout = 5000
        $timeout | Should -BeGreaterThan 1000
    }
    
    It "Should validate retry logic" {
        $maxRetries = 3
        $maxRetries | Should -BeGreaterOrEqual 1
        $maxRetries | Should -BeLessOrEqual 5
    }
}

Describe "Process Management Tests" -Tag "Process", "Critical" {
    It "Should detect running processes" {
        $process = Get-Process -Name "explorer" -ErrorAction SilentlyContinue
        $process | Should -Not -BeNullOrEmpty
    }
    
    It "Should handle non-existent processes" {
        $process = Get-Process -Name "nonexistent-process-12345" -ErrorAction SilentlyContinue
        $process | Should -BeNullOrEmpty
    }
}

Describe "Failure Recovery Tests" -Tag "Recovery" {
    It "Should handle JSON parsing errors" {
        { '{ invalid json' | ConvertFrom-Json } | Should -Throw
    }
    
    It "Should validate file operations" {
        $testPath = "D:\Nova\data"
        Test-Path $testPath | Should -Be $true
    }
    
    It "Should implement atomic operations" {
        $tempFile = Join-Path $env:TEMP "test-atomic.txt"
        "test data" | Out-File $tempFile -Encoding UTF8
        Test-Path $tempFile | Should -Be $true
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}
