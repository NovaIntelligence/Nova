function Confirm-DirectoryPath {
    <#
    .SYNOPSIS
    Ensures a directory path exists, creating it if necessary
    
    .DESCRIPTION
    Safely creates directory paths with proper error handling and logging.
    Handles nested directory creation and provides consistent behavior across modules.
    
    .PARAMETER Path
    The directory path to ensure exists
    
    .PARAMETER Force
    Create the directory and any parent directories if they don't exist
    
    .PARAMETER Quiet
    Suppress informational output
    
    .OUTPUTS
    DirectoryInfo object of the created or existing directory
    
    .EXAMPLE
    Confirm-DirectoryPath -Path "D:\Nova\data\metrics"
    
    .EXAMPLE
    Confirm-DirectoryPath -Path "D:\Nova\logs" -Force -Quiet
    #>
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Path,
        
        [switch]$Force,
        
        [switch]$Quiet
    )
    
    # Handle null or empty paths gracefully
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not $Quiet) {
            Write-NovaLog -Message "Path is null or empty, skipping directory creation" -Level "WARNING" -Component "Nova.Common"
        }
        return $null
    }
    
    try {
        if (-not (Test-Path -Path $Path)) {
            if (-not $Quiet) {
                Write-NovaLog -Message "Creating directory: $Path" -Level "DEBUG" -Component "Nova.Common"
            }
            
            $result = New-Item -ItemType Directory -Path $Path -Force:$Force -ErrorAction Stop
            
            if (-not $Quiet) {
                Write-NovaLog -Message "Directory created successfully: $Path" -Level "INFO" -Component "Nova.Common"
            }
            
            return $result
        }
        else {
            # Directory already exists
            return Get-Item -Path $Path
        }
    }
    catch {
        $errorMsg = "Failed to create directory '$Path': $($_.Exception.Message)"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component "Nova.Common"
        throw [System.IO.DirectoryNotFoundException]::new($errorMsg, $_.Exception)
    }
}