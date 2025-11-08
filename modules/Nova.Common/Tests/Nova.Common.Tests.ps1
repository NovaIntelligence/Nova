# Nova.Common Module Tests
# Tests for shared utility functions

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot ".." "Nova.Common.psm1"
    Import-Module $ModulePath -Force
}

Describe "Nova.Common Module" {
    Context "Module Loading" {
        It "Should load all public functions" {
            $commands = Get-Command -Module Nova.Common
            $commands.Count | Should -BeGreaterThan 0
        }
        
        It "Should expose expected public functions" {
            $expectedFunctions = @(
                "Write-NovaLog",
                "Confirm-DirectoryPath", 
                "Test-NovaPath",
                "Guard-NotNull",
                "Guard-NotEmpty",
                "Guard-Range", 
                "Guard-Path",
                "Get-NovaModulePath",
                "Convert-NovaDateTime",
                "Format-NovaOutput",
                "Invoke-NovaRetry"
            )
            
            foreach ($func in $expectedFunctions) {
                Get-Command $func -Module Nova.Common | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe "Write-NovaLog" {
    It "Should write log messages without error" {
        { Write-NovaLog -Level "Info" -Message "Test message" } | Should -Not -Throw
    }
    
    It "Should handle null messages gracefully" {
        { Write-NovaLog -Level "Info" -Message $null } | Should -Not -Throw
    }
    
    It "Should accept different log levels" {
        { Write-NovaLog -Level "Debug" -Message "Debug test" } | Should -Not -Throw
        { Write-NovaLog -Level "Warning" -Message "Warning test" } | Should -Not -Throw
        { Write-NovaLog -Level "Error" -Message "Error test" } | Should -Not -Throw
    }
}

Describe "Confirm-DirectoryPath" {
    It "Should create directory when it doesn't exist" {
        $testPath = Join-Path $TestDrive "TestDirectory"
        Confirm-DirectoryPath -Path $testPath
        Test-Path $testPath | Should -Be $true
    }
    
    It "Should not error when directory exists" {
        $testPath = Join-Path $TestDrive "ExistingDir"
        New-Item -Path $testPath -ItemType Directory -Force
        { Confirm-DirectoryPath -Path $testPath } | Should -Not -Throw
    }
    
    It "Should handle null or empty paths" {
        { Confirm-DirectoryPath -Path $null } | Should -Not -Throw
        { Confirm-DirectoryPath -Path "" } | Should -Not -Throw
    }
}

Describe "Test-NovaPath" {
    It "Should validate existing paths" {
        $result = Test-NovaPath -Path $TestDrive -Type "Directory"
        $result | Should -Be $true
    }
    
    It "Should reject non-existent paths" {
        $result = Test-NovaPath -Path "C:\NonExistent\Path" -Type "Directory"
        $result | Should -Be $false
    }
    
    It "Should validate file vs directory correctly" {
        $testFile = Join-Path $TestDrive "testfile.txt"
        "test content" | Out-File $testFile
        
        Test-NovaPath -Path $testFile -Type "File" | Should -Be $true
        Test-NovaPath -Path $testFile -Type "Directory" | Should -Be $false
    }
}

Describe "Guard-Arguments" {
    Context "Guard-NotNull" {
        It "Should not throw for valid objects" {
            { Guard-NotNull -Value "test" -Name "TestParam" } | Should -Not -Throw
        }
        
        It "Should throw for null values" {
            { Guard-NotNull -Value $null -Name "TestParam" } | Should -Throw
        }
    }
    
    Context "Guard-NotEmpty" {
        It "Should not throw for non-empty strings" {
            { Guard-NotEmpty -Value "test" -Name "TestParam" } | Should -Not -Throw
        }
        
        It "Should throw for empty strings" {
            { Guard-NotEmpty -Value "" -Name "TestParam" } | Should -Throw
        }
    }
    
    Context "Guard-Range" {
        It "Should accept values within range" {
            { Guard-Range -Value 5 -Min 1 -Max 10 -Name "TestParam" } | Should -Not -Throw
        }
        
        It "Should throw for values outside range" {
            { Guard-Range -Value 15 -Min 1 -Max 10 -Name "TestParam" } | Should -Throw
        }
    }
}

Describe "Get-NovaModulePath" {
    It "Should return valid paths for different types" {
        $rootPath = Get-NovaModulePath -Type "Root"
        $rootPath | Should -Not -BeNullOrEmpty
        
        $dataPath = Get-NovaModulePath -Type "Data"
        $dataPath | Should -Not -BeNullOrEmpty
        $dataPath | Should -Match "data$"
    }
    
    It "Should handle module-specific paths" {
        $modulePath = Get-NovaModulePath -Type "Modules" -ModuleName "TestModule"
        $modulePath | Should -Match "Nova\.TestModule$"
    }
}

Describe "Convert-NovaDateTime" {
    It "Should format datetime objects correctly" {
        $testDate = Get-Date "2025-01-24T14:30:22"
        
        $timestamp = Convert-NovaDateTime -DateTime $testDate -Format "Timestamp"
        $timestamp | Should -Match "^\d{8}_\d{6}$"
        
        $display = Convert-NovaDateTime -DateTime $testDate -Format "Display"
        $display | Should -Match "^\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}$"
    }
    
    It "Should handle null input gracefully" {
        $result = Convert-NovaDateTime -DateTime $null
        $result | Should -BeNullOrEmpty
    }
    
    It "Should parse string dates" {
        $result = Convert-NovaDateTime -DateTime "2025-01-24T14:30:22Z" -Format "Display"
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "Format-NovaOutput" {
    It "Should format objects as table" {
        $testData = @(
            [PSCustomObject]@{ Name = "Test1"; Value = 1 }
            [PSCustomObject]@{ Name = "Test2"; Value = 2 }
        )
        
        { $testData | Format-NovaOutput -Format "Table" -PassThru } | Should -Not -Throw
    }
    
    It "Should convert to JSON" {
        $testData = @{ Name = "Test"; Value = 123 }
        $result = $testData | Format-NovaOutput -Format "JSON" -PassThru
        $result | Should -Match "^\s*\{"
    }
    
    It "Should handle empty input" {
        { @() | Format-NovaOutput -Format "Table" } | Should -Not -Throw
    }
}

Describe "Invoke-NovaRetry" {
    It "Should execute successful operations without retry" {
        $result = Invoke-NovaRetry -ScriptBlock { "success" } -Silent
        $result | Should -Be "success"
    }
    
    It "Should retry failing operations" {
        $script:attempts = 0
        $result = Invoke-NovaRetry -ScriptBlock { 
            $script:attempts++
            if ($script:attempts -lt 3) { throw "Test failure" }
            return "success"
        } -MaxRetries 3 -DelaySeconds 0 -Silent
        
        $result | Should -Be "success"
        $script:attempts | Should -Be 3
    }
    
    It "Should throw after max retries" {
        { 
            Invoke-NovaRetry -ScriptBlock { 
                throw "Always fails" 
            } -MaxRetries 2 -DelaySeconds 0 -Silent
        } | Should -Throw
    }
}

AfterAll {
    # Clean up
    Remove-Module Nova.Common -Force -ErrorAction SilentlyContinue
}