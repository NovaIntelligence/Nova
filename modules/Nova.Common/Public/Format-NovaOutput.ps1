function Format-NovaOutput {
    <#
    .SYNOPSIS
    Standardized output formatting for Nova Bot modules
    
    .DESCRIPTION
    Provides consistent output formatting across Nova Bot modules including
    tables, lists, JSON, and custom formats with error handling.
    
    .PARAMETER InputObject
    The object(s) to format
    
    .PARAMETER Format
    Output format type
    
    .PARAMETER Properties
    Specific properties to include (for Table/List formats)
    
    .PARAMETER Title
    Optional title for the output
    
    .OUTPUTS
    Formatted output object or string
    
    .EXAMPLE
    $data | Format-NovaOutput -Format "Table" -Properties "Name", "Status"
    
    .EXAMPLE
    $result | Format-NovaOutput -Format "JSON" -Title "API Response"
    #>
    param(
        [Parameter(ValueFromPipeline, Position = 0)]
        $InputObject,
        
        [Parameter(Position = 1)]
        [ValidateSet("Table", "List", "JSON", "CSV", "Raw", "Summary")]
        [string]$Format = "Table",
        
        [Parameter()]
        [string[]]$Properties,
        
        [Parameter()]
        [string]$Title,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    begin {
        $objects = @()
    }
    
    process {
        if ($null -ne $InputObject) {
            $objects += $InputObject
        }
    }
    
    end {
        if ($objects.Count -eq 0) {
            if (-not $PassThru) {
                Write-Host "No data to display" -ForegroundColor Yellow
            }
            return
        }
        
        # Add title if specified
        if ($Title -and -not $PassThru) {
            Write-Host "`n=== $Title ===" -ForegroundColor Cyan
        }
        
        try {
            switch ($Format) {
                "Table" {
                    if ($Properties) {
                        $output = $objects | Select-Object $Properties | Format-Table -AutoSize
                    } else {
                        $output = $objects | Format-Table -AutoSize
                    }
                }
                "List" {
                    if ($Properties) {
                        $output = $objects | Select-Object $Properties | Format-List
                    } else {
                        $output = $objects | Format-List
                    }
                }
                "JSON" {
                    if ($Properties) {
                        $output = $objects | Select-Object $Properties | ConvertTo-Json -Depth 3
                    } else {
                        $output = $objects | ConvertTo-Json -Depth 3
                    }
                }
                "CSV" {
                    if ($Properties) {
                        $output = $objects | Select-Object $Properties | ConvertTo-Csv -NoTypeInformation
                    } else {
                        $output = $objects | ConvertTo-Csv -NoTypeInformation
                    }
                }
                "Summary" {
                    $count = $objects.Count
                    $output = "Total items: $count"
                    if ($count -gt 0) {
                        $firstType = $objects[0].GetType().Name
                        $output += " (Type: $firstType)"
                    }
                }
                default {
                    $output = $objects
                }
            }
            
            if ($PassThru) {
                return $output
            } else {
                $output
            }
        }
        catch {
            $errorMsg = "Failed to format output as '$Format': $($_.Exception.Message)"
            if ($PassThru) {
                throw $errorMsg
            } else {
                Write-Error $errorMsg
                Write-Host "Raw output:" -ForegroundColor Yellow
                $objects
            }
        }
    }
}