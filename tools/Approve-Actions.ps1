# Approve-Actions.ps1 - Interactive Action Approval Tool
# Creators: Tyler McKendry & Nova
# 
# Simple TUI to review and approve/deny queued actions

param(
    [switch]$AutoRefresh,
    [int]$RefreshInterval = 5
)

# Import required modules
$SkillsModule = Join-Path $PSScriptRoot "..\modules\Nova.Skills.psm1"
if (Test-Path $SkillsModule) {
    Import-Module $SkillsModule -Force
}

$LogShimPath = Join-Path $PSScriptRoot "_nova_logshim.psm1"
if (Test-Path $LogShimPath) {
    Import-Module $LogShimPath -Force
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (Get-Command "Write-NovaLog" -ErrorAction SilentlyContinue) {
        Write-NovaLog -Message $Message -Level $Level -Component "Approve-Actions"
    }
}

function Show-Header {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    Nova Bot Action Approval                      ║" -ForegroundColor Cyan  
    Write-Host "║                   Creators: Tyler McKendry & Nova                ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-QueueStatus {
    $status = Get-QueueStatus
    
    Write-Host "📊 Queue Status:" -ForegroundColor Yellow
    Write-Host "   Inbox: $($status.InboxCount) items" -ForegroundColor White
    Write-Host "   Outbox: $($status.OutboxCount) items" -ForegroundColor White
    Write-Host "   Pending Approval: $($status.PendingApproval) items" -ForegroundColor $(if ($status.PendingApproval -gt 0) { "Red" } else { "Green" })
    Write-Host ""
}

function Show-PendingActions {
    $status = Get-QueueStatus
    $pendingActions = $status.Inbox | Where-Object { $_.Status -eq "pending" }
    
    if ($pendingActions.Count -eq 0) {
        Write-Host "✅ No actions pending approval" -ForegroundColor Green
        return $null
    }
    
    Write-Host "⏳ Pending Actions:" -ForegroundColor Yellow
    Write-Host ""
    
    for ($i = 0; $i -lt $pendingActions.Count; $i++) {
        $action = $pendingActions[$i]
        $num = $i + 1
        
        Write-Host "[$num] Action ID: $($action.Id)" -ForegroundColor Cyan
        Write-Host "    Skill: $($action.Skill)" -ForegroundColor White
        Write-Host "    Command: $($action.Command)" -ForegroundColor White
        Write-Host "    Requested By: $($action.RequestedBy)" -ForegroundColor White
        Write-Host "    Timestamp: $($action.Timestamp)" -ForegroundColor Gray
        Write-Host "    Mode: $($action.Mode)" -ForegroundColor White
        
        if ($action.Parameters -and $action.Parameters.PSObject.Properties.Count -gt 0) {
            Write-Host "    Parameters:" -ForegroundColor White
            $action.Parameters.PSObject.Properties | ForEach-Object {
                Write-Host "      $($_.Name): $($_.Value)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    return $pendingActions
}

function Show-RecentActions {
    param([int]$Count = 5)
    
    $status = Get-QueueStatus
    $recent = $status.Outbox | Sort-Object Timestamp -Descending | Select-Object -First $Count
    
    if ($recent.Count -eq 0) {
        return
    }
    
    Write-Host "📋 Recent Actions:" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($action in $recent) {
        $statusColor = switch ($action.Status) {
            "success" { "Green" }
            "denied" { "Red" }
            "failed" { "Red" }
            default { "Gray" }
        }
        
        $statusIcon = switch ($action.Status) {
            "success" { "✅" }
            "denied" { "❌" }
            "failed" { "💥" }
            default { "❓" }
        }
        
        Write-Host "$statusIcon $($action.Skill).$($action.Command) - " -NoNewline
        Write-Host $action.Status.ToUpper() -ForegroundColor $statusColor
        Write-Host "    ID: $($action.Id) | By: $($action.RequestedBy)" -ForegroundColor Gray
        if ($action.Reason) {
            Write-Host "    Reason: $($action.Reason)" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

function Get-UserChoice {
    param(
        [array]$PendingActions
    )
    
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  [1-9]     - Select action to review" -ForegroundColor White
    Write-Host "  [r]efresh - Refresh queue status" -ForegroundColor White
    Write-Host "  [q]uit    - Exit approval tool" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter choice"
    return $choice.ToLower().Trim()
}

function Review-Action {
    param([object]$Action)
    
    Show-Header
    Write-Host "🔍 Reviewing Action" -ForegroundColor Cyan
    Write-Host "══════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "ID: $($Action.Id)" -ForegroundColor White
    Write-Host "Skill: $($Action.Skill)" -ForegroundColor White  
    Write-Host "Command: $($Action.Command)" -ForegroundColor White
    Write-Host "Requested By: $($Action.RequestedBy)" -ForegroundColor White
    Write-Host "Timestamp: $($Action.Timestamp)" -ForegroundColor White
    Write-Host "Mode: $($Action.Mode)" -ForegroundColor White
    Write-Host ""
    
    if ($Action.Parameters -and $Action.Parameters.PSObject.Properties.Count -gt 0) {
        Write-Host "Parameters:" -ForegroundColor Yellow
        $Action.Parameters.PSObject.Properties | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor White
        }
        Write-Host ""
    }
    
    Write-Host "Actions:" -ForegroundColor Yellow
    Write-Host "  [a]pprove - Approve this action for execution" -ForegroundColor Green
    Write-Host "  [d]eny    - Deny this action" -ForegroundColor Red
    Write-Host "  [b]ack    - Return to main menu" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter choice"
    
    switch ($choice.ToLower().Trim()) {
        "a" {
            $reason = Read-Host "Approval reason (optional)"
            if (-not $reason) {
                $reason = "Approved by $env:USERNAME via Approve-Actions tool"
            }
            
            Write-Host "Approving action..." -ForegroundColor Yellow
            $result = Approve-Action -ActionId $Action.Id -Reason $reason
            
            if ($result) {
                Write-Host "✅ Action approved successfully" -ForegroundColor Green
                Write-Log "Action $($Action.Id) approved: $reason"
            } else {
                Write-Host "❌ Failed to approve action" -ForegroundColor Red
            }
            
            Read-Host "Press Enter to continue"
        }
        
        "d" {
            $reason = Read-Host "Denial reason (required)"
            if (-not $reason) {
                Write-Host "❌ Denial reason is required" -ForegroundColor Red
                Read-Host "Press Enter to continue"
                return
            }
            
            Write-Host "Denying action..." -ForegroundColor Yellow
            $result = Deny-Action -ActionId $Action.Id -Reason $reason
            
            if ($result) {
                Write-Host "❌ Action denied" -ForegroundColor Red
                Write-Log "Action $($Action.Id) denied: $reason"
            } else {
                Write-Host "❌ Failed to deny action" -ForegroundColor Red
            }
            
            Read-Host "Press Enter to continue"
        }
        
        "b" {
            # Return to main menu
        }
        
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
            Read-Host "Press Enter to continue"
        }
    }
}

# Main loop
try {
    Write-Log "Starting Action Approval Tool"
    
    while ($true) {
        Show-Header
        Show-QueueStatus
        
        $pendingActions = Show-PendingActions
        
        if ($pendingActions) {
            Write-Host ""
            Show-RecentActions -Count 3
            Write-Host ""
            
            $choice = Get-UserChoice -PendingActions $pendingActions
            
            switch ($choice) {
                "q" {
                    Write-Host "Exiting..." -ForegroundColor Yellow
                    Write-Log "Action Approval Tool closed by user"
                    exit 0
                }
                
                "r" {
                    # Refresh - continue loop
                    continue
                }
                
                default {
                    # Try to parse as action number
                    if ($choice -match '^\d+$') {
                        $actionIndex = [int]$choice - 1
                        if ($actionIndex -ge 0 -and $actionIndex -lt $pendingActions.Count) {
                            Review-Action -Action $pendingActions[$actionIndex]
                        } else {
                            Write-Host "Invalid action number" -ForegroundColor Red
                            Read-Host "Press Enter to continue"
                        }
                    } else {
                        Write-Host "Invalid choice" -ForegroundColor Red
                        Read-Host "Press Enter to continue"
                    }
                }
            }
        } else {
            Show-RecentActions -Count 5
            Write-Host ""
            Write-Host "No pending actions. Press [r] to refresh or [q] to quit:" -ForegroundColor Yellow
            
            $choice = Read-Host
            
            if ($choice.ToLower() -eq "q") {
                Write-Host "Exiting..." -ForegroundColor Yellow
                break
            }
            
            if ($AutoRefresh) {
                Write-Host "Auto-refreshing in $RefreshInterval seconds..." -ForegroundColor Gray
                Start-Sleep -Seconds $RefreshInterval
            }
        }
    }
} catch {
    Write-Host "Error in approval tool: $_" -ForegroundColor Red
    Write-Log "Approval tool error: $_" -Level "ERROR"
    exit 1
}