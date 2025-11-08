# Nova.Skills.psm1 - Sandboxed Skill/Action Layer
# Creators: Tyler McKendry & Nova
# 
# Provides a secure action queue system with approval workflows

# Import Nova.Common for shared utilities
$CommonModulePath = Join-Path $PSScriptRoot "Nova.Common\Nova.Common.psm1"
if (Test-Path $CommonModulePath) {
    Import-Module $CommonModulePath -Force
} else {
    # Fallback: try to find Nova.Common in modules directory
    $FallbackPath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Nova.Common\Nova.Common.psm1"
    if (Test-Path $FallbackPath) {
        Import-Module $FallbackPath -Force
    }
}

# Import legacy logging for backward compatibility
$LogShimPath = Join-Path (Split-Path $PSScriptRoot -Parent) "tools\_nova_logshim.psm1"
if (Test-Path $LogShimPath) {
    Import-Module $LogShimPath -Force
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
    
    Write-NovaLog -Level "Info" -Message "Submitting action: $Skill.$Command (Mode: $Mode)" -Component "Nova.Skills"
    
    # Create action object
    $action = [NovaAction]::new($Skill, $Command, $Parameters, $Mode)
    
    # Determine queue path using Nova.Common
    $queuePath = switch ($Mode) {
        "DryRun" { Get-NovaModulePath -Type "Data" | Join-Path -ChildPath "queue\inbox" }
        "RequireApproval" { Get-NovaModulePath -Type "Data" | Join-Path -ChildPath "queue\inbox" }
        "Execute" { Get-NovaModulePath -Type "Data" | Join-Path -ChildPath "queue\inbox" }
    }
    
    # Ensure queue directory exists using Nova.Common
    Confirm-DirectoryPath -Path $queuePath
    
    # Write action to queue
    $actionFile = Join-Path $queuePath "action-$($action.Id).json"
    $action | ConvertTo-Json -Depth 10 | Set-Content $actionFile -Encoding UTF8
    
    Write-NovaLog -Level "Info" -Message "Action $($action.Id) submitted to queue: $actionFile" -Component "Nova.Skills"
    
    # Auto-process if Execute mode
    if ($Mode -eq [ActionMode]::Execute) {
        Write-NovaLog -Level "Info" -Message "Auto-processing Execute mode action" -Component "Nova.Skills"
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
    
    # Base paths using Nova.Common
    $dataPath = Get-NovaModulePath -Type "Data"
    $inboxPath = Join-Path $dataPath "queue\inbox"
    $outboxPath = Join-Path $dataPath "queue\outbox"
    
    # Ensure directories exist using Nova.Common
    Confirm-DirectoryPath -Path $inboxPath
    Confirm-DirectoryPath -Path $outboxPath
    
    # Get actions to process
    $actions = @()
    if ($ActionId) {
        $actionFile = Join-Path $inboxPath "action-$ActionId.json"
        if (Test-Path $actionFile) {
            $actions += $actionFile
        } else {
            Write-NovaLog -Level "Error" -Message "Action $ActionId not found in inbox" -Component "Nova.Skills"
            return
        }
    } elseif ($ProcessAll) {
        $actions = Get-ChildItem "$inboxPath\action-*.json" -ErrorAction SilentlyContinue
    } else {
        Write-NovaLog -Level "Error" -Message "Must specify ActionId or ProcessAll" -Component "Nova.Skills"
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
            
            Write-NovaLog -Level "Info" -Message "Processing action $($action.Id): $($action.Skill).$($action.Command)" -Component "Nova.Skills"
            
            # Check if action requires approval
            if ($action.Mode -eq [ActionMode]::RequireApproval -and $action.Status -eq "pending") {
                Write-NovaLog -Level "Info" -Message "Action $($action.Id) requires approval - skipping auto-processing" -Component "Nova.Skills"
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
            
            Write-NovaLog -Level "Info" -Message "Action $($action.Id) processed: $($action.Status)" -Component "Nova.Skills"
            
        } catch {
            Write-NovaLog -Level "Error" -Message "Failed to process action $($actionFile.Name): $_" -Component "Nova.Skills"
        }
    }
}

function Invoke-SkillAction {
    param([NovaAction]$Action)
    
    $skillsPath = Get-NovaModulePath -Type "Root" | Join-Path -ChildPath "skills"
    $skillPath = Join-Path $skillsPath $Action.Skill
    
    # Check if skill exists
    if (-not (Test-Path $skillPath)) {
        Write-NovaLog -Level "Error" -Message "Skill not found: $($Action.Skill)" -Component "Nova.Skills"
        return @{ Success = $false; Message = "Skill '$($Action.Skill)' not found" }
    }
    
    # Find skill script
    $skillScript = Get-ChildItem "$skillPath\*.ps1" | Where-Object { $_.BaseName -eq $Action.Skill -or $_.BaseName -eq "main" } | Select-Object -First 1
    
    if (-not $skillScript) {
        Write-NovaLog -Level "Error" -Message "No skill script found in $skillPath" -Component "Nova.Skills"
        return @{ Success = $false; Message = "No executable script found for skill '$($Action.Skill)'" }
    }
    
    try {
        Write-NovaLog -Level "Info" -Message "Loading skill script: $($skillScript.FullName)" -Component "Nova.Skills"
        
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
        
        Write-NovaLog -Level "Info" -Message "Invoking skill with command: $($Action.Command)" -Component "Nova.Skills"
        Write-NovaLog -Level "Debug" -Message "Parameters: $($Action.Parameters | ConvertTo-Json -Compress)" -Component "Nova.Skills"
        
        # Execute skill
        if ($Action.Mode -eq [ActionMode]::DryRun) {
            Write-NovaLog -Level "Info" -Message "DRY RUN - Would execute: $($Action.Skill).$($Action.Command)" -Component "Nova.Skills"
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
        Write-NovaLog -Level "Error" -Message "Skill execution failed: $_" -Component "Nova.Skills"
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
    
    $dataPath = Get-NovaModulePath -Type "Data"
    $inboxPath = Join-Path $dataPath "queue\inbox"
    $outboxPath = Join-Path $dataPath "queue\outbox"
    
    $inbox = @()
    $outbox = @()
    
    if (Test-Path $inboxPath) {
        $inbox = Get-ChildItem "$inboxPath\action-*.json" | ForEach-Object {
            try {
                Get-Content $_.FullName -Raw | ConvertFrom-Json
            } catch {
                Write-NovaLog -Level "Warning" -Message "Failed to parse action file: $($_.Name)" -Component "Nova.Skills"
            }
        }
    }
    
    if (Test-Path $outboxPath) {
        $outbox = Get-ChildItem "$outboxPath\action-*.json" | ForEach-Object {
            try {
                Get-Content $_.FullName -Raw | ConvertFrom-Json
            } catch {
                Write-NovaLog -Level "Warning" -Message "Failed to parse action file: $($_.Name)" -Component "Nova.Skills"
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
    
    $dataPath = Get-NovaModulePath -Type "Data"
    $inboxPath = Join-Path $dataPath "queue\inbox"
    $actionFile = Join-Path $inboxPath "action-$ActionId.json"
    
    if (-not (Test-Path $actionFile)) {
        Write-NovaLog -Level "Error" -Message "Action $ActionId not found" -Component "Nova.Skills"
        return $false
    }
    
    try {
        $actionJson = Get-Content $actionFile -Raw | ConvertFrom-Json
        $actionJson.Status = "approved"
        $actionJson.Reason = $Reason
        
        $actionJson | ConvertTo-Json -Depth 10 | Set-Content $actionFile -Encoding UTF8
        
        Write-NovaLog -Level "Info" -Message "Action $ActionId approved: $Reason" -Component "Nova.Skills"
        
        # Auto-process approved action
        Process-Action -ActionId $ActionId
        
        return $true
        
    } catch {
        Write-NovaLog -Level "Error" -Message "Failed to approve action $ActionId`: $($_.Exception.Message)" -Component "Nova.Skills"
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
    
    $dataPath = Get-NovaModulePath -Type "Data"
    $inboxPath = Join-Path $dataPath "queue\inbox"
    $outboxPath = Join-Path $dataPath "queue\outbox"
    $actionFile = Join-Path $inboxPath "action-$ActionId.json"
    
    if (-not (Test-Path $actionFile)) {
        Write-NovaLog -Level "Error" -Message "Action $ActionId not found" -Component "Nova.Skills"
        return $false
    }
    
    try {
        $actionJson = Get-Content $actionFile -Raw | ConvertFrom-Json
        $actionJson.Status = "denied"
        $actionJson.Reason = $Reason
        
        # Move to outbox
        Confirm-DirectoryPath -Path $outboxPath
        
        $outboxFile = Join-Path $outboxPath "action-$ActionId.json"
        $actionJson | ConvertTo-Json -Depth 10 | Set-Content $outboxFile -Encoding UTF8
        
        # Remove from inbox
        Remove-Item $actionFile -Force
        
        Write-NovaLog -Level "Info" -Message "Action $ActionId denied: $Reason" -Component "Nova.Skills"
        return $true
        
    } catch {
        Write-NovaLog -Level "Error" -Message "Failed to deny action $ActionId`: $($_.Exception.Message)" -Component "Nova.Skills"
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function Submit-Action, Process-Action, Get-QueueStatus, Approve-Action, Deny-Action