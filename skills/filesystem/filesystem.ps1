# Filesystem Skill - Safe file operations
# Creators: Tyler McKendry & Nova

function Invoke-Skill {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        
        [hashtable]$Parameters = @{},
        
        [string]$Mode = "DryRun",
        
        [switch]$WhatIf
    )
    
    Write-Host "🗂️  Filesystem Skill: $Command" -ForegroundColor Cyan
    
    switch ($Command.ToLower()) {
        "createfile" {
            $path = $Parameters["Path"]
            $content = $Parameters["Content"]
            
            if (-not $path) {
                throw "Path parameter is required for CreateFile command"
            }
            
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would create file: $path"
                    Content = $content
                    Safe = $true
                }
            }
            
            try {
                # Validate path is safe (no system directories)
                $safePaths = @("D:\Nova\data", "D:\Nova\temp", "D:\Nova\output")
                $isSafe = $safePaths | Where-Object { $path.StartsWith($_, "CurrentCultureIgnoreCase") }
                
                if (-not $isSafe) {
                    throw "Path '$path' is not in allowed safe directories"
                }
                
                # Create directory if needed
                $parentDir = Split-Path $path -Parent
                if ($parentDir -and -not (Test-Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }
                
                # Create file
                if ($content) {
                    Set-Content -Path $path -Value $content -Encoding UTF8
                } else {
                    New-Item -Path $path -ItemType File -Force | Out-Null
                }
                
                return @{
                    Action = "Created file: $path"
                    Success = $true
                    Size = (Get-Item $path).Length
                }
            }
            catch {
                throw "Failed to create file: $_"
            }
        }
        
        "listdirectory" {
            $path = $Parameters["Path"]
            
            if (-not $path) {
                $path = "D:\Nova\data"
            }
            
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would list directory: $path"
                    Safe = $true
                }
            }
            
            try {
                if (-not (Test-Path $path)) {
                    throw "Directory '$path' does not exist"
                }
                
                $items = Get-ChildItem $path | Select-Object Name, Length, LastWriteTime
                
                return @{
                    Action = "Listed directory: $path"
                    Items = $items
                    Count = $items.Count
                    Success = $true
                }
            }
            catch {
                throw "Failed to list directory: $_"
            }
        }
        
        "deletetemporary" {
            $pattern = $Parameters["Pattern"]
            
            if (-not $pattern) {
                $pattern = "*.tmp"
            }
            
            $tempPath = "D:\Nova\temp"
            
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would delete temporary files matching '$pattern' in $tempPath"
                    Safe = $true
                }
            }
            
            try {
                if (-not (Test-Path $tempPath)) {
                    return @{
                        Action = "No temp directory found"
                        Success = $true
                        Deleted = 0
                    }
                }
                
                $files = Get-ChildItem "$tempPath\$pattern" -ErrorAction SilentlyContinue
                $deletedCount = 0
                
                foreach ($file in $files) {
                    Remove-Item $file.FullName -Force
                    $deletedCount++
                }
                
                return @{
                    Action = "Deleted $deletedCount temporary files"
                    Pattern = $pattern
                    Success = $true
                    Deleted = $deletedCount
                }
            }
            catch {
                throw "Failed to delete temporary files: $_"
            }
        }
        
        default {
            throw "Unknown command: $Command. Available: CreateFile, ListDirectory, DeleteTemporary"
        }
    }
}

# Function is ready for dot-sourcing
# Export-ModuleMember only works inside modules