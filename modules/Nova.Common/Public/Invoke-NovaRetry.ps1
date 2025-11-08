function Invoke-NovaRetry {
    <#
    .SYNOPSIS
    Standardized retry logic for Nova Bot operations
    
    .DESCRIPTION
    Provides consistent retry behavior across Nova Bot modules with
    configurable retry counts, delays, and error handling.
    
    .PARAMETER ScriptBlock
    The script block to execute with retry logic
    
    .PARAMETER MaxRetries
    Maximum number of retry attempts (default: 3)
    
    .PARAMETER DelaySeconds
    Delay between retries in seconds (default: 1)
    
    .PARAMETER ExponentialBackoff
    Use exponential backoff for delays
    
    .PARAMETER RetryOn
    Types of exceptions to retry on (default: all)
    
    .OUTPUTS
    Result of successful script block execution
    
    .EXAMPLE
    $result = Invoke-NovaRetry -ScriptBlock { Get-WebData } -MaxRetries 5
    
    .EXAMPLE
    Invoke-NovaRetry -ScriptBlock { 
        Test-Connection "example.com" 
    } -MaxRetries 3 -DelaySeconds 2 -ExponentialBackoff
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [ValidateRange(0, 60)]
        [double]$DelaySeconds = 1,
        
        [Parameter()]
        [switch]$ExponentialBackoff,
        
        [Parameter()]
        [string[]]$RetryOn = @("*"),
        
        [Parameter()]
        [switch]$Silent
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -le $MaxRetries) {
        try {
            $attempt++
            
            if (-not $Silent -and $attempt -gt 1) {
                Write-NovaLog -Level "Info" -Message "Retry attempt $($attempt-1)/$MaxRetries" -Component "NovaRetry"
            }
            
            # Execute the script block
            $result = & $ScriptBlock
            
            # Success - return result
            if (-not $Silent -and $attempt -gt 1) {
                Write-NovaLog -Level "Info" -Message "Operation succeeded on attempt $attempt" -Component "NovaRetry"
            }
            
            return $result
        }
        catch {
            $lastError = $_
            
            # Check if we should retry this type of error
            $shouldRetry = $false
            foreach ($pattern in $RetryOn) {
                if ($pattern -eq "*" -or $_.Exception.GetType().Name -like $pattern) {
                    $shouldRetry = $true
                    break
                }
            }
            
            if (-not $shouldRetry) {
                if (-not $Silent) {
                    Write-NovaLog -Level "Warning" -Message "Not retrying due to error type: $($_.Exception.GetType().Name)" -Component "NovaRetry"
                }
                throw
            }
            
            # Check if we've exhausted retries
            if ($attempt -gt $MaxRetries) {
                if (-not $Silent) {
                    Write-NovaLog -Level "Error" -Message "Operation failed after $MaxRetries retries: $($_.Exception.Message)" -Component "NovaRetry"
                }
                throw
            }
            
            # Calculate delay
            if ($DelaySeconds -gt 0) {
                $currentDelay = $DelaySeconds
                if ($ExponentialBackoff) {
                    $currentDelay = $DelaySeconds * [Math]::Pow(2, $attempt - 1)
                }
                
                if (-not $Silent) {
                    Write-NovaLog -Level "Warning" -Message "Attempt $attempt failed: $($_.Exception.Message). Retrying in $currentDelay seconds..." -Component "NovaRetry"
                }
                
                Start-Sleep -Seconds $currentDelay
            }
        }
    }
    
    # This should never be reached, but just in case
    if ($lastError) {
        throw $lastError
    }
}