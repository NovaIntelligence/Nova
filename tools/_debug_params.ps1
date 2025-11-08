$actionJson = Get-Content 'D:\Nova\data\queue\inbox\action-ab2b4eb5.json' -Raw | ConvertFrom-Json
Write-Host "Raw Parameters:" $actionJson.Parameters
Write-Host "Path Value:" $actionJson.Parameters.Path
Write-Host "Content Value:" $actionJson.Parameters.Content

$parameters = @{}
$actionJson.Parameters.PSObject.Properties | ForEach-Object {
    Write-Host "Adding parameter:" $_.Name "=" $_.Value
    $parameters[$_.Name] = $_.Value
}
Write-Host "Reconstructed hashtable:"
$parameters | Format-Table