# System Skill - Safe system operations  
# Creators: Tyler McKendry & Nova

function Invoke-Skill {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        
        [hashtable]$Parameters = @{},
        
        [string]$Mode = "DryRun",
        
        [switch]$WhatIf
    )
    
    Write-Host "⚙️  System Skill: $Command" -ForegroundColor Green
    
    switch ($Command.ToLower()) {
        "getstatus" {
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would get system status"
                    Safe = $true
                }
            }
            
            try {
                $cpu = Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average
                $memory = Get-WmiObject Win32_OperatingSystem
                $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
                
                return @{
                    Action = "Retrieved system status"
                    CPU_Usage = "$([math]::Round($cpu.Average, 2))%"
                    Memory_Free = "$([math]::Round($memory.FreePhysicalMemory/1KB, 2)) MB"
                    Memory_Total = "$([math]::Round($memory.TotalPhysicalMemory/1KB, 2)) MB" 
                    Disk_Free = "$([math]::Round($disk.FreeSpace/1GB, 2)) GB"
                    Disk_Total = "$([math]::Round($disk.Size/1GB, 2)) GB"
                    Success = $true
                }
            }
            catch {
                throw "Failed to get system status: $_"
            }
        }
        
        "getprocesses" {
            $nameFilter = $Parameters["NameFilter"]
            
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would get process list $(if ($nameFilter) { "filtered by '$nameFilter'" })"
                    Safe = $true
                }
            }
            
            try {
                $processes = Get-Process
                
                if ($nameFilter) {
                    $processes = $processes | Where-Object { $_.ProcessName -like "*$nameFilter*" }
                }
                
                $processInfo = $processes | Select-Object ProcessName, Id, CPU, WorkingSet | Sort-Object WorkingSet -Descending | Select-Object -First 20
                
                return @{
                    Action = "Retrieved process list"
                    Filter = $nameFilter
                    Processes = $processInfo
                    Count = $processInfo.Count
                    Success = $true
                }
            }
            catch {
                throw "Failed to get processes: $_"
            }
        }
        
        "getservices" {
            $status = $Parameters["Status"]
            
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would get services $(if ($status) { "with status '$status'" })"
                    Safe = $true
                }
            }
            
            try {
                $services = Get-Service
                
                if ($status) {
                    $services = $services | Where-Object { $_.Status -eq $status }
                }
                
                $serviceInfo = $services | Select-Object Name, Status, StartType | Sort-Object Name
                
                return @{
                    Action = "Retrieved services list"
                    StatusFilter = $status
                    Services = $serviceInfo
                    Count = $serviceInfo.Count
                    Success = $true
                }
            }
            catch {
                throw "Failed to get services: $_"
            }
        }
        
        "restartservice" {
            $serviceName = $Parameters["ServiceName"]
            
            if (-not $serviceName) {
                throw "ServiceName parameter is required for RestartService command"
            }
            
            # Safety check - only allow Nova-related services
            $allowedServices = @("Nova*", "Spooler", "Themes")  # Example safe services
            $isAllowed = $allowedServices | Where-Object { $serviceName -like $_ }
            
            if (-not $isAllowed -and $Mode -ne "DryRun") {
                throw "Service '$serviceName' is not in the allowed restart list for safety"
            }
            
            if ($WhatIf -or $Mode -eq "DryRun") {
                return @{
                    Action = "Would restart service: $serviceName"
                    Safe = $isAllowed
                    Warning = if (-not $isAllowed) { "Service not in allowed list" }
                }
            }
            
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                
                if ($service.Status -eq "Running") {
                    Stop-Service -Name $serviceName -Force
                    Start-Sleep -Seconds 2
                }
                
                Start-Service -Name $serviceName
                
                return @{
                    Action = "Restarted service: $serviceName"
                    PreviousStatus = $service.Status
                    CurrentStatus = (Get-Service -Name $serviceName).Status
                    Success = $true
                }
            }
            catch {
                throw "Failed to restart service '$serviceName': $_"
            }
        }
        
        default {
            throw "Unknown command: $Command. Available: GetStatus, GetProcesses, GetServices, RestartService"
        }
    }
}

# Function is ready for dot-sourcing
# Export-ModuleMember only works inside modules