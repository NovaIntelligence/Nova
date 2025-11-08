# Nova.Skills.psm1 - Sandboxed Skill/Action Layer
# Creators: Tyler McKendry & Nova
# 
# Provides a secure action queue system with approval workflows

# Import logging
$LogShimPath = Join-Path (Split-Path $PSScriptRoot -Parent) "tools\_nova_logshim.psm1"
if (Test-Path $LogShimPath) {
    Import-Module $LogShimPath -Force
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (Get-Command "Write-NovaLog" -ErrorAction SilentlyContinue) {
        Write-NovaLog -Message $Message -Level $Level -Component "Nova.Skills"
    } else {
        Write-Host "[$Level] $(Get-Date -Format 'HH:mm:ss') Nova.Skills: $Message"
    }
}

# Action execution modes
enum ActionMode {
    DryRun
    RequireApproval  
    Execute
}

class NovaAction {
    [string]$Id
    [string]$Skill
    [string]$Command
    [hashtable]$Parameters
    [string]$RequestedBy
    [DateTime]$Timestamp
    [ActionMode]$Mode
    [string]$Status
    [string]$Reason
    [object]$Result
    
    NovaAction([string]$skill, [string]$command, [hashtable]$parameters, [ActionMode]$mode) {
        $this.Id = [System.Guid]::NewGuid().ToString("N")[0..7] -join ''
        $this.Skill = $skill
        $this.Command = $command
        $this.Parameters = $parameters
        $this.RequestedBy = $env:USERNAME
        $this.Timestamp = Get-Date
        $this.Mode = $mode
        $this.Status = "pending"
    }
}

function Submit-Action {
    <#
    .SYNOPSIS
    Submits an action to the Nova Skills queue
    
    .PARAMETER Skill
    Name of the skill to invoke
    
    .PARAMETER Command  
    Command or function to execute within the skill
    
    .PARAMETER Parameters
    Hashtable of parameters to pass to the skill
    
    .PARAMETER Mode
    Execution mode: DryRun (default), RequireApproval, Execute
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Skill,
        
        [Parameter(Mandatory)]
        [string]$Command,
        
        [hashtable]$Parameters = @{},
        
        [ActionMode]$Mode = [ActionMode]::DryRun
    )
    
    Write-Log "Submitting action: $Skill.$Command (Mode: $Mode)"
    
    # Create action object
    $action = [NovaAction]::new($Skill, $Command, $Parameters, $Mode)
    
    # Determine queue path
    $queuePath = switch ($Mode) {
        "DryRun" { "D:\Nova\data\queue\inbox" }
        "RequireApproval" { "D:\Nova\data\queue\inbox" }
        "Execute" { "D:\Nova\data\queue\inbox" }
    }
    
    # Ensure queue directory exists
    if (-not (Test-Path $queuePath)) {
        New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
    }
    
    # Write action to queue
    $actionFile = Join-Path $queuePath "action-$($action.Id).json"
    $action | ConvertTo-Json -Depth 10 | Set-Content $actionFile -Encoding UTF8
    
    Write-Log "Action $($action.Id) submitted to queue: $actionFile"
    
    # Auto-process if Execute mode
    if ($Mode -eq [ActionMode]::Execute) {
        Write-Log "Auto-processing Execute mode action"
        Process-Action -ActionId $action.Id
    }
    
    return $action
}

function Invoke-Action {
    <#
    .SYNOPSIS
    Processes an action from the queue
    
    .PARAMETER ActionId
    Specific action ID to process
    
    .PARAMETER ProcessAll
    Process all pending actions in the queue
    #>
    param(
        [string]$ActionId,
        [switch]$ProcessAll
    )
    
    $inboxPath = "D:\Nova\data\queue\inbox"
    $outboxPath = "D:\Nova\data\queue\outbox"
    
    if (-not (Test-Path $inboxPath)) {
        Write-Log "Inbox path not found: $inboxPath" -Level "ERROR"
        return
    }
    
    # Ensure outbox exists
    if (-not (Test-Path $outboxPath)) {
        New-Item -Path $outboxPath -ItemType Directory -Force | Out-Null
    }
    
    # Get actions to process
    $actions = @()
    if ($ActionId) {
        $actionFile = Join-Path $inboxPath "action-$ActionId.json"
        if (Test-Path $actionFile) {
            $actions += $actionFile
        } else {
            Write-Log "Action $ActionId not found in inbox" -Level "ERROR"
            return
        }
    } elseif ($ProcessAll) {
        $actions = Get-ChildItem "$inboxPath\action-*.json" -ErrorAction SilentlyContinue
    } else {
        Write-Log "Must specify ActionId or ProcessAll" -Level "ERROR"
        return
    }
    
    foreach ($actionFile in $actions) {
        try {
            # Load action
            $actionJson = Get-Content $actionFile.FullName -Raw | ConvertFrom-Json
            
            # Convert parameters back to hashtable
            $parameters = @{}
            if ($actionJson.Parameters) {
                $actionJson.Parameters.PSObject.Properties | ForEach-Object {
                    $parameters[$_.Name] = $_.Value
                }
            }
            
            # Convert mode back to enum
            $mode = switch ($actionJson.Mode) {
                0 { [ActionMode]::DryRun }
                1 { [ActionMode]::RequireApproval }
                2 { [ActionMode]::Execute }
                default { [ActionMode]::DryRun }
            }
            
            $action = [NovaAction]::new($actionJson.Skill, $actionJson.Command, $parameters, $mode)
            $action.Id = $actionJson.Id
            $action.RequestedBy = $actionJson.RequestedBy
            $action.Timestamp = $actionJson.Timestamp
            $action.Status = $actionJson.Status
            $action.Reason = $actionJson.Reason
            
            Write-Log "Processing action $($action.Id): $($action.Skill).$($action.Command)"
            
            # Check if action requires approval
            if ($action.Mode -eq [ActionMode]::RequireApproval -and $action.Status -eq "pending") {
                Write-Log "Action $($action.Id) requires approval - skipping auto-processing"
                continue
            }
            
            # Execute the action
            $result = Invoke-SkillAction -Action $action
            
            # Move to outbox with result
            $action.Result = $result
            $action.Status = if ($result.Success) { "success" } else { "failed" }
            $action.Reason = $result.Message
            
            $outboxFile = Join-Path $outboxPath "action-$($action.Id).json"
            $action | ConvertTo-Json -Depth 10 | Set-Content $outboxFile -Encoding UTF8
            
            # Remove from inbox
            Remove-Item $actionFile.FullName -Force
            
            Write-Log "Action $($action.Id) processed: $($action.Status)"
            
        } catch {
            Write-Log "Failed to process action $($actionFile.Name): $_" -Level "ERROR"
        }
    }
}

function Invoke-SkillAction {
    param([NovaAction]$Action)
    
    $skillsPath = "D:\Nova\skills"
    $skillPath = Join-Path $skillsPath $Action.Skill
    
    # Check if skill exists
    if (-not (Test-Path $skillPath)) {
        Write-Log "Skill not found: $($Action.Skill)" -Level "ERROR"
        return @{ Success = $false; Message = "Skill '$($Action.Skill)' not found" }
    }
    
    # Find skill script
    $skillScript = Get-ChildItem "$skillPath\*.ps1" | Where-Object { $_.BaseName -eq $Action.Skill -or $_.BaseName -eq "main" } | Select-Object -First 1
    
    if (-not $skillScript) {
        Write-Log "No skill script found in $skillPath" -Level "ERROR"
        return @{ Success = $false; Message = "No executable script found for skill '$($Action.Skill)'" }
    }
    
    try {
        Write-Log "Loading skill script: $($skillScript.FullName)"
        
        # Load the skill script
        . $skillScript.FullName
        
        # Check for Invoke-Skill function
        if (-not (Get-Command "Invoke-Skill" -ErrorAction SilentlyContinue)) {
            return @{ Success = $false; Message = "Skill script must export Invoke-Skill function" }
        }
        
        # Prepare parameters
        $invokeParams = @{
            Command = $Action.Command
            Parameters = $Action.Parameters
            Mode = $Action.Mode.ToString()
        }
        
        Write-Log "Invoking skill with command: $($Action.Command)"
        Write-Log "Parameters: $($Action.Parameters | ConvertTo-Json -Compress)" -Level "DEBUG"
        
        # Execute skill
        if ($Action.Mode -eq [ActionMode]::DryRun) {
            Write-Log "DRY RUN - Would execute: $($Action.Skill).$($Action.Command)"
            $result = Invoke-Skill @invokeParams -WhatIf
        } else {
            $result = Invoke-Skill @invokeParams
        }
        
        return @{ 
            Success = $true
            Message = "Skill executed successfully"
            Data = $result
        }
        
    } catch {
        Write-Log "Skill execution failed: $_" -Level "ERROR"
        return @{ 
            Success = $false
            Message = "Skill execution failed: $_"
        }
    }
}

function Get-QueueStatus {
    <#
    .SYNOPSIS
    Gets the current status of action queues
    #>
    
    $inboxPath = "D:\Nova\data\queue\inbox"
    $outboxPath = "D:\Nova\data\queue\outbox"
    
    $inbox = @()
    $outbox = @()
    
    if (Test-Path $inboxPath) {
        $inbox = Get-ChildItem "$inboxPath\action-*.json" | ForEach-Object {
            try {
                Get-Content $_.FullName -Raw | ConvertFrom-Json
            } catch {
                Write-Log "Failed to parse action file: $($_.Name)" -Level "WARN"
            }
        }
    }
    
    if (Test-Path $outboxPath) {
        $outbox = Get-ChildItem "$outboxPath\action-*.json" | ForEach-Object {
            try {
                Get-Content $_.FullName -Raw | ConvertFrom-Json
            } catch {
                Write-Log "Failed to parse action file: $($_.Name)" -Level "WARN"
            }
        }
    }
    
    return @{
        Inbox = $inbox
        Outbox = $outbox
        InboxCount = $inbox.Count
        OutboxCount = $outbox.Count
        PendingApproval = ($inbox | Where-Object { $_.Status -eq "pending" }).Count
    }
}

function Approve-Action {
    <#
    .SYNOPSIS
    Approves a pending action for execution
    
    .PARAMETER ActionId
    ID of the action to approve
    
    .PARAMETER Reason
    Optional reason for approval
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ActionId,
        
        [string]$Reason = "Approved by $env:USERNAME"
    )
    
    $inboxPath = "D:\Nova\data\queue\inbox"
    $actionFile = Join-Path $inboxPath "action-$ActionId.json"
    
    if (-not (Test-Path $actionFile)) {
        Write-Log "Action $ActionId not found" -Level "ERROR"
        return $false
    }
    
    try {
        $actionJson = Get-Content $actionFile -Raw | ConvertFrom-Json
        $actionJson.Status = "approved"
        $actionJson.Reason = $Reason
        
        $actionJson | ConvertTo-Json -Depth 10 | Set-Content $actionFile -Encoding UTF8
        
        Write-Log "Action $ActionId approved: $Reason"
        
        # Auto-process approved action
        Process-Action -ActionId $ActionId
        
        return $true
        
    } catch {
        Write-Log "Failed to approve action $ActionId`: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Deny-Action {
    <#
    .SYNOPSIS
    Denies a pending action
    
    .PARAMETER ActionId
    ID of the action to deny
    
    .PARAMETER Reason
    Reason for denial (required)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ActionId,
        
        [Parameter(Mandatory)]
        [string]$Reason
    )
    
    $inboxPath = "D:\Nova\data\queue\inbox"
    $outboxPath = "D:\Nova\data\queue\outbox"
    $actionFile = Join-Path $inboxPath "action-$ActionId.json"
    
    if (-not (Test-Path $actionFile)) {
        Write-Log "Action $ActionId not found" -Level "ERROR"
        return $false
    }
    
    try {
        $actionJson = Get-Content $actionFile -Raw | ConvertFrom-Json
        $actionJson.Status = "denied"
        $actionJson.Reason = $Reason
        
        # Move to outbox
        if (-not (Test-Path $outboxPath)) {
            New-Item -Path $outboxPath -ItemType Directory -Force | Out-Null
        }
        
        $outboxFile = Join-Path $outboxPath "action-$ActionId.json"
        $actionJson | ConvertTo-Json -Depth 10 | Set-Content $outboxFile -Encoding UTF8
        
        # Remove from inbox
        Remove-Item $actionFile -Force
        
        Write-Log "Action $ActionId denied: $Reason"
        return $true
        
    } catch {
        Write-Log "Failed to deny action $ActionId`: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function Submit-Action, Process-Action, Get-QueueStatus, Approve-Action, Deny-Action